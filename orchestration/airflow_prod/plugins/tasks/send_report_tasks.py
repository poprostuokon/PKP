# send_report_tasks.py
# -----------------------------------------------------------------------------
# Wysylka raportu utrzymaniowego PKP mailem przez SMTP OVH (MX Plan).
# Zalaczniki z data/<ENV>/RAPORT (katalog wyliczany z PKP_ENV w report_excel).
# Przelaczasz instancje na PROD -> task siega do data/PROD/RAPORT automatycznie.
#
# Zmienne srodowiskowe:
#   SMTP_HOST      - serwer SMTP (OVH: ssl0.ovh.net)
#   SMTP_PORT      - port (465 = SSL/TLS)
#   SMTP_USER      - pelny adres skrzynki (raport@bokoniewski.pl)
#   SMTP_PASSWORD  - haslo skrzynki
#   SENDER_EMAIL   - adres nadawcy (zwykle == SMTP_USER)
#   SENDER_NAME    - nazwa nadawcy (opcjonalna)
#   REPORT_EMAIL   - odbiorca raportu
#
# DAG: PythonOperator(task_id="send_report", python_callable=send_report,
#                     trigger_rule="all_done")
# Test reczny: python send_report_tasks.py
# -----------------------------------------------------------------------------

import os
import ssl
import glob
import smtplib
from datetime import date
from email.message import EmailMessage
from email.utils import formataddr

try:
    from report_excel import ENV, REPORTS_DIR
except ImportError:
    from tasks.report_excel import ENV, REPORTS_DIR


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
        val = ti.xcom_pull(task_ids="set_run_date", key="run_date")
        if val:
            return val
    return date.today().isoformat()


def send_report(**context):
    """Wysyla mail z zalacznikami z data/<ENV>/RAPORT. Zawsze (trigger_rule=all_done)."""
    run_date = _resolve_run_date(context)

    smtp_host = os.environ.get("SMTP_HOST")
    smtp_port = int(os.environ.get("SMTP_PORT", "465"))
    smtp_user = os.environ.get("SMTP_USER")
    smtp_password = os.environ.get("SMTP_PASSWORD")
    sender_email = os.environ.get("SENDER_EMAIL") or smtp_user
    sender_name = os.environ.get("SENDER_NAME")
    report_email = os.environ.get("REPORT_EMAIL")

    if not smtp_host:
        raise Exception("[send_report] Brak SMTP_HOST!")
    if not smtp_user:
        raise Exception("[send_report] Brak SMTP_USER!")
    if not smtp_password:
        raise Exception("[send_report] Brak SMTP_PASSWORD!")
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

    msg = EmailMessage()
    msg["From"] = formataddr((sender_name, sender_email)) if sender_name else sender_email
    msg["To"] = report_email
    msg["Subject"] = subject
    msg.set_content(body_text)

    for path in attachments:
        with open(path, "rb") as f:
            data = f.read()
        msg.add_attachment(
            data,
            maintype="application",
            subtype="octet-stream",
            filename=os.path.basename(path),
        )

    added = [os.path.basename(p) for p in attachments]
    if not added:
        print(f"[send_report] UWAGA: brak zalacznikow w {REPORTS_DIR} - wysylam sam mail.")
    print(f"[send_report] Wysylam: {subject}")
    print(f"[send_report] Zalaczniki ({len(added)}): {added}")

    context_ssl = ssl.create_default_context()
    with smtplib.SMTP_SSL(smtp_host, smtp_port, context=context_ssl) as server:
        server.login(smtp_user, smtp_password)
        server.send_message(msg)

    print(f"[send_report] Email wyslany pomyslnie -> {report_email}")


if __name__ == "__main__":
    print(f"[send_report] ENV={ENV}  katalog={REPORTS_DIR}")
    send_report()