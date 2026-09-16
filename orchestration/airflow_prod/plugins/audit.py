# audit.py
# -----------------------------------------------------------------------------
# Warstwa audytu pipeline'u Airflow dla PKP (Oracle ADB, python-oracledb).
# Rejestruje kazdy krok w maintenance.pipeline_run / pipeline_run_step.
#
# Polaczenie reuzywane z ingestion/db.py (get_connection, wallet inline, thin mode).
# Modul sam odnajduje ingestion/db.py idac w gore od swojej lokalizacji, wiec
# dziala niezaleznie od docelowego ukladu katalogow Airflow/Docker.
#
# Uzycie w DAG-u (default_args):
#   default_args = {
#       "pre_execute":         on_task_start,
#       "on_success_callback": on_task_success,
#       "on_failure_callback": on_task_failure,
#       "on_skipped_callback": on_task_skipped,
#   }
# oraz pierwszy task:
#   PythonOperator(task_id=SET_RUN_DATE_TASK, python_callable=create_pipeline_run)
# a domkniecie runu:
#   PythonOperator(task_id="finalize_pipeline",
#                  python_callable=finalize_pipeline_success,   # lub _error
#                  trigger_rule="all_done")
# -----------------------------------------------------------------------------

import sys
import traceback
from datetime import date, datetime
from pathlib import Path

import oracledb


# ── Odnalezienie i import ingestion/db.py (layout-independent) ────────────────
def _bootstrap_db():
    """Szuka ingestion/db.py w gore od tego pliku i dokleja do sys.path."""
    here = Path(__file__).resolve()
    for parent in here.parents:
        candidate = parent / "ingestion" / "db.py"
        if candidate.exists():
            ingestion_dir = str(parent / "ingestion")
            if ingestion_dir not in sys.path:
                sys.path.insert(0, ingestion_dir)
            break
    import db  # ingestion/db.py -> db.get_connection()
    return db


_db = _bootstrap_db()


# ── Konfiguracja ─────────────────────────────────────────────────────────────
# Nazwa pierwszego taska, ktory zaklada rekord w pipeline_run i wrzuca
# pipeline_run_id do XCom. Zmien tu, jesli nazwiesz task inaczej.
SET_RUN_DATE_TASK = "set_run_date"


# ── Pomocnicze ───────────────────────────────────────────────────────────────
def _get_pipeline_run_id(context):
    """Pobiera pipeline_run_id z XCom (wrzucony przez create_pipeline_run)."""
    return context["ti"].xcom_pull(task_ids=SET_RUN_DATE_TASK, key="pipeline_run_id")


# ── Tabela glowna: pipeline_run ──────────────────────────────────────────────
def create_pipeline_run(**context) -> int:
    """
    Zaklada rekord w pipeline_run (PENDING) na starcie runu.
    Wrzuca run_date (str) i pipeline_run_id do XCom dla pozostalych taskow.
    Zwraca id nowego rekordu.
    """
    run_date_d = date.today()
    dag_run_id = context["run_id"]

    conn = _db.get_connection()
    try:
        with conn.cursor() as cur:
            new_id = cur.var(oracledb.DB_TYPE_NUMBER)
            cur.execute(
                """
                INSERT INTO maintenance.pipeline_run (run_date, dag_run_id, status)
                VALUES (:run_date, :dag_run_id, 'PENDING')
                RETURNING id INTO :new_id
                """,
                {"run_date": run_date_d, "dag_run_id": dag_run_id, "new_id": new_id},
            )
            pipeline_run_id = int(new_id.getvalue()[0])
            conn.commit()

        print(f"[audit] Utworzono pipeline_run id={pipeline_run_id} "
              f"dla dag_run_id={dag_run_id}")

        context["ti"].xcom_push(key="run_date", value=run_date_d.isoformat())
        context["ti"].xcom_push(key="pipeline_run_id", value=pipeline_run_id)
        return pipeline_run_id
    finally:
        conn.close()


def finalize_pipeline_run(status: str, **context):
    """Domyka rekord pipeline_run: ustawia end_time i status koncowy."""
    pipeline_run_id = _get_pipeline_run_id(context)
    if not pipeline_run_id:
        print("[audit] Brak pipeline_run_id w XCom — pomijam finalizacje.")
        return

    conn = _db.get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE maintenance.pipeline_run
                SET end_time = SYSTIMESTAMP,
                    status   = :status
                WHERE id = :id
                """,
                {"status": status, "id": pipeline_run_id},
            )
            conn.commit()
        print(f"[audit] pipeline_run id={pipeline_run_id} → status={status}")
    finally:
        conn.close()


def finalize_pipeline_success(**context):
    finalize_pipeline_run(status="SUCCESS", **context)


def finalize_pipeline_error(**context):
    finalize_pipeline_run(status="ERROR", **context)


# ── Tabela krokow: pipeline_run_step ─────────────────────────────────────────
def on_task_start(context):
    """
    pre_execute — zaklada rekord kroku (PENDING) tuz przed wykonaniem tasku.
    Krok samego SET_RUN_DATE_TASK nie zostanie zapisany: pipeline_run_id
    nie istnieje jeszcze w XCom w momencie jego pre_execute (to swiadome).
    """
    pipeline_run_id = _get_pipeline_run_id(context)
    if not pipeline_run_id:
        return

    step_name = context["task"].task_id

    conn = _db.get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO maintenance.pipeline_run_step
                    (pipeline_run_id, step_name, status)
                VALUES (:run_id, :step_name, 'PENDING')
                """,
                {"run_id": pipeline_run_id, "step_name": step_name},
            )
            conn.commit()
        print(f"[audit] Krok '{step_name}' → PENDING")
    finally:
        conn.close()


def on_task_success(context):
    """on_success_callback — domyka krok jako SUCCESS."""
    pipeline_run_id = _get_pipeline_run_id(context)
    if not pipeline_run_id:
        return

    step_name = context["task"].task_id

    conn = _db.get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE maintenance.pipeline_run_step
                SET end_time = SYSTIMESTAMP,
                    status   = 'SUCCESS'
                WHERE pipeline_run_id = :run_id
                  AND step_name       = :step_name
                  AND status          = 'PENDING'
                """,
                {"run_id": pipeline_run_id, "step_name": step_name},
            )
            conn.commit()
        print(f"[audit] Krok '{step_name}' → SUCCESS")
    finally:
        conn.close()


def on_task_failure(context):
    """on_failure_callback — domyka krok jako ERROR + zapisuje stack trace."""
    pipeline_run_id = _get_pipeline_run_id(context)
    if not pipeline_run_id:
        return

    step_name = context["task"].task_id

    exception = context.get("exception")
    error_message = str(exception) if exception else "Nieznany blad"
    error_tb = "".join(
        traceback.format_exception(type(exception), exception, exception.__traceback__)
    ) if exception else ""

    error_details = (
        f"=== BLAD TASKU: {step_name} ===\n"
        f"Czas: {datetime.now()}\n"
        f"DAG run ID: {context.get('run_id', 'N/A')}\n"
        f"Wiadomosc: {error_message}\n\n"
        f"=== STACK TRACE ===\n"
        f"{error_tb}"
    )

    conn = _db.get_connection()
    try:
        with conn.cursor() as cur:
            # CLOB: jawny typ wejscia chroni przed limitem dlugosci przy dlugim trace
            cur.setinputsizes(error_details=oracledb.DB_TYPE_CLOB)
            cur.execute(
                """
                UPDATE maintenance.pipeline_run_step
                SET end_time      = SYSTIMESTAMP,
                    status        = 'ERROR',
                    error_details = :error_details
                WHERE pipeline_run_id = :run_id
                  AND step_name       = :step_name
                  AND status          = 'PENDING'
                """,
                {
                    "error_details": error_details,
                    "run_id": pipeline_run_id,
                    "step_name": step_name,
                },
            )
            conn.commit()
        print(f"[audit] Krok '{step_name}' → ERROR")
    finally:
        conn.close()


def on_task_skipped(context):
    """on_skipped_callback — domyka krok jako SKIPPED (np. loader po padnietym scraperze)."""
    pipeline_run_id = _get_pipeline_run_id(context)
    if not pipeline_run_id:
        return

    step_name = context["task"].task_id

    conn = _db.get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE maintenance.pipeline_run_step
                SET end_time = SYSTIMESTAMP,
                    status   = 'SKIPPED'
                WHERE pipeline_run_id = :run_id
                  AND step_name       = :step_name
                  AND status          = 'PENDING'
                """,
                {"run_id": pipeline_run_id, "step_name": step_name},
            )
            conn.commit()
        print(f"[audit] Krok '{step_name}' → SKIPPED")
    finally:
        conn.close()