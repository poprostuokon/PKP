# send_report_tasks.py
# -----------------------------------------------------------------------------
# Wysylka raportu utrzymaniowego PKP mailem przez MailerSend (SDK 2.0.3).
# Zalaczniki z data/<ENV>/RAPORT (katalog wyliczany z PKP_ENV w report_excel).
# Przelaczasz instancje na PROD -> task siega do data/PROD/RAPORT automatycznie.
#
# Zmienne srodowiskowe:
#   MAILERSEND_API_KEY  - token z MailerSend
#   SENDER_EMAIL        - adres na zweryfikowanej domenie (sandbox: ...@test-xxx.mlsender.net)
#   REPORT_EMAIL        - odbiorca (SANDBOX: musi byc adres administratora konta MailerSend)
#
# DAG: PythonOperator(task_id="send_report", python_callable=send_report,
#                     trigger_rule="all_done")
# Test reczny: python send_report_tasks.py
# -----------------------------------------------------------------------------

import os
import glob
from datetime import date

from mailersend import MailerSendClient, EmailBuilder

try:
    from report_excel import ENV, REPORTS_DIR
except ImportError:
    from tasks.report_excel import ENV, REPORTS_DIR

try:
    from audit import SET_RUN_DATE_TASK
except ImportError:
    SET_RUN_DATE_TASK = "set_run_date"   # fallback, gdy audit niedostępny standalone


ATTACHMENT_PATTERNS = [
    "summary_*.pdf",
    "report_steps_*.xlsx",
    "report_schema_sizes_*.xlsx",
]


def _collect_attachments() -> list[str]:
    found: list[str] = []
    for pattern in ATTACHMENT_PATTERNS:
        found.extend(sorted(glob.glob(os.path.join(REPORTS_DIR, pattern))))
    return [p for p in found if os.path.exists(p)]


def _resolve_run_date(context) -> str:
    ti = context.get("ti")
    if ti is not None:
        val = ti.xcom_pull(task_ids=SET_RUN_DATE_TASK, key="run_date")
        if val:
            return val
    return date.today().isoformat()


def send_report(**context):
    """Wysyla mail z zalacznikami z data/<ENV>/RAPORT. Zawsze (trigger_rule=all_done)."""
    run_date = _resolve_run_date(context)

    api_key = os.environ.get("MAILERSEND_API_KEY")
    sender_email = os.environ.get("SENDER_EMAIL")
    report_email = os.environ.get("REPORT_EMAIL")
    sender_name =  os.environ.get("SENDER_NAME")

    if not api_key:
        raise Exception("[send_report] Brak MAILERSEND_API_KEY!")
    if not sender_email:
        raise Exception("[send_report] Brak SENDER_EMAIL!")
    if not report_email:
        raise Exception("[send_report] Brak REPORT_EMAIL!")

    subject = f"Raport utrzymaniowy PKP [{ENV}] - {run_date}"
    body_text = (
        "=" * 55 + "\n"
        "  Raport utrzymaniowy wygenerowany automatycznie (Airflow)\n"
        f"  Srodowisko: {ENV} | Data: {run_date}\n"
        + "=" * 55
    )

    attachments = _collect_attachments()

    builder = (
        EmailBuilder()
        .from_email(sender_email, sender_name)
        .to_many([{"email": report_email}])
        .subject(subject)
        .text(body_text)
    )
    for path in attachments:
        builder = builder.attach_file(path)   # SDK 2.x sam czyta i koduje plik

    email = builder.build()

    added = [os.path.basename(p) for p in attachments]
    if not added:
        print(f"[send_report] UWAGA: brak zalacznikow w {REPORTS_DIR} - wysylam sam mail.")
    print(f"[send_report] Wysylam: {subject}")
    print(f"[send_report] Zalaczniki ({len(added)}): {added}")

    client = MailerSendClient(api_key=api_key)
    response = client.emails.send(email)

    status = getattr(response, "status_code", None)
    print(f"[send_report] Status MailerSend: {status}")
    if status not in (200, 201, 202):
        body = getattr(response, "content", getattr(response, "body", ""))
        raise Exception(f"[send_report] Blad wysylania: {status} {body}")

    print("[send_report] Email wyslany pomyslnie.")


if __name__ == "__main__":
    print(f"[send_report] ENV={ENV}  katalog={REPORTS_DIR}")
    send_report()