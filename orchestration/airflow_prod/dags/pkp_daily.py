# pkp_daily.py — dzienny pipeline PKP: ingest -> upload -> stg -> silver -> gold -> maintenance -> raport
from datetime import datetime
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.utils.trigger_rule import TriggerRule

from audit import (
    SET_RUN_DATE_TASK, create_pipeline_run,
    on_task_start, on_task_success, on_task_failure, on_task_skipped,
    finalize_pipeline_success, finalize_pipeline_error,
)

MAINT_SCHEMAS = ["SILVER", "GOLD", "MAINTENANCE"]


def _drain(cur):
    line = cur.var(str); status = cur.var(int)
    while True:
        cur.callproc("dbms_output.get_line", (line, status))
        if status.getvalue() != 0:
            break
        print(line.getvalue())


# ── ingest / upload / load ──
def t_all_dictionaries(**_):
    from pkp_ingestion.domains.dictionaries import run_all_dictionaries
    run_all_dictionaries()

def t_schedules(**_):
    from pkp_ingestion.domains.schedules import run_schedules
    run_schedules()

def t_operations(**_):
    from pkp_ingestion.domains.operations import run_operations
    run_operations()

def t_disruptions(**_):
    from pkp_ingestion.domains.disruptions import run_disruptions
    run_disruptions()

def t_upload(**_):
    from pkp_ingestion.upload import run_upload
    run_upload()

def t_prepare_stg(**_):
    import db
    from pkp_ingestion.stg_load import prepare_stg
    with db.get_connection() as conn:
        prepare_stg(conn)

def t_silver(**_):
    import db
    with db.get_connection() as conn, conn.cursor() as cur:
        cur.callproc("dbms_output.enable", (None,))
        cur.callproc("silver.pkg_silver_load.p_load_all")
        _drain(cur)

def t_gold(**_):
    import db
    with db.get_connection() as conn, conn.cursor() as cur:
        cur.callproc("dbms_output.enable", (None,))
        cur.callproc("gold.pkg_gold_load.p_load_dimensions", [False])
        cur.callproc("gold.pkg_gold_load.p_load_facts_daily", [3])
        _drain(cur)


# ── maintenance (kolejka wspoldzielona -> table PRZED index, sekwencyjnie) ──
def t_clear_queue(**_):
    import db
    with db.get_connection() as conn, conn.cursor() as cur:
        cur.callproc("dbms_output.enable", (None,))
        cur.callproc("maintenance.pkg_maintenance.p_clear_queue")
        _drain(cur)
        
def t_table_maint(**_):
    import db
    with db.get_connection() as conn, conn.cursor() as cur:
        cur.callproc("dbms_output.enable", (None,))
        for s in MAINT_SCHEMAS:
            cur.callproc("maintenance.pkg_maintenance.p_gen_table_move_schema", [s, 8, 50])
        try:
            cur.callproc("maintenance.pkg_maintenance.p_run_compress_queue")
        finally:
            _drain(cur)

def t_index_maint(**_):
    import db
    with db.get_connection() as conn, conn.cursor() as cur:
        cur.callproc("dbms_output.enable", (None,))
        for s in MAINT_SCHEMAS:
            cur.callproc("maintenance.pkg_maintenance.p_gen_index_rebuild_schema", [s, 15, 15])
        try:
            cur.callproc("maintenance.pkg_maintenance.p_run_compress_queue")
        finally:
            _drain(cur)


# ── raport: prepare (NOWY wrapper na generatory) + send (istniejacy) ──
def t_prepare_report(**context):
    # TYLKO sprzatanie starych plikow -> task konczy sie szybko = SUCCESS
    from tasks.report_excel import cleanup_reports
    for pat in ("report_steps_*.xlsx", "report_schema_sizes_*.xlsx", "summary_*.pdf"):
        cleanup_reports(pat)


def t_send_report(**context):
    # generowanie PRZENIESIONE tutaj -> w tym momencie prepare_report jest juz SUCCESS
    from tasks.report_excel import generate_steps_excel, generate_schema_sizes_excel, _db
    from tasks.report_pdf import generate_summary_pdf
    from tasks.send_report_tasks import send_report
    ti = context["ti"]
    run_date = ti.xcom_pull(task_ids=SET_RUN_DATE_TASK, key="run_date")
    run_id   = ti.xcom_pull(task_ids=SET_RUN_DATE_TASK, key="pipeline_run_id")
    conn = _db.get_connection()
    try:
        generate_steps_excel(run_date, run_id, conn)
        generate_schema_sizes_excel(run_date, conn)
        generate_summary_pdf(run_date, conn)
    finally:
        conn.close()
    send_report(**context)


default_args = {
    "pre_execute":         on_task_start,
    "on_success_callback": on_task_success,
    "on_failure_callback": on_task_failure,
    "on_skipped_callback": on_task_skipped,
}

with DAG(
    dag_id="pkp_daily",
    description="PKP dzienny: ingest -> upload -> stg -> silver -> gold -> maintenance -> raport",
    start_date=datetime(2026, 9, 1),
    schedule="0 4 * * *",
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    tags=["pkp", "daily", "etl"],
) as dag:

    set_run_date = PythonOperator(task_id=SET_RUN_DATE_TASK, python_callable=create_pipeline_run)

    all_dictionaries   = PythonOperator(task_id="all_dictionaries",   python_callable=t_all_dictionaries)
    schedules   = PythonOperator(task_id="schedules",   python_callable=t_schedules)
    operations  = PythonOperator(task_id="operations",  python_callable=t_operations)
    disruptions = PythonOperator(task_id="disruptions", python_callable=t_disruptions)

    upload   = PythonOperator(task_id="upload",      python_callable=t_upload)
    prep_stg = PythonOperator(task_id="prepare_stg", python_callable=t_prepare_stg)
    silver   = PythonOperator(task_id="silver_load", python_callable=t_silver)
    gold     = PythonOperator(task_id="gold_load",   python_callable=t_gold)


    clear_queue = PythonOperator(task_id="clear_queue", python_callable=t_clear_queue)
    table_maint = PythonOperator(task_id="table_maintenance", python_callable=t_table_maint)
    index_maint = PythonOperator(task_id="index_maintenance", python_callable=t_index_maint)

    finalize_ok  = PythonOperator(task_id="finalize_success",
                                  python_callable=finalize_pipeline_success,
                                  trigger_rule=TriggerRule.ALL_SUCCESS)
    finalize_err = PythonOperator(task_id="finalize_error",
                                  python_callable=finalize_pipeline_error,
                                  trigger_rule=TriggerRule.ONE_FAILED)

    prepare_report = PythonOperator(task_id="prepare_report", python_callable=t_prepare_report,
                                    trigger_rule=TriggerRule.ALL_DONE)
    send_report    = PythonOperator(task_id="send_report", python_callable=t_send_report,
                                    trigger_rule=TriggerRule.ALL_DONE)

    # ── przeplyw ──
    set_run_date >> [all_dictionaries, schedules, operations, disruptions] >> upload >> prep_stg >> silver >> gold
    gold >> clear_queue >> table_maint >> index_maint

    chain = [set_run_date, all_dictionaries, schedules, operations, disruptions,
             upload, prep_stg, silver, gold, clear_queue, table_maint, index_maint]
    for t in chain:
        t >> finalize_ok
        t >> finalize_err

    [finalize_ok, finalize_err] >> prepare_report >> send_report