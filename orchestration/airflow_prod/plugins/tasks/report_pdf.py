# report_pdf.py
# -----------------------------------------------------------------------------
# Generator PDF z ogolnym podsumowaniem raportu utrzymaniowego PKP:
#   - zajetosc bazy: suma MB per schemat + TOTAL,
#   - Object Storage: wiersz per bucket (daily + live): obiekty + rozmiar MB,
#   - API: limity klucza, zuzycie wczoraj/dzis, ranking Top endpoints.
#
# Bez szczegolow (te sa w Excelach). Plik tymczasowy w <root>/data/<ENV>/RAPORT.
# Reuzywa helpery z report_excel.py (ENV, katalog, _safe_fetch, connection).
#
# Test reczny (venv + env-y PKP):  python report_pdf.py
# -----------------------------------------------------------------------------

import os
import sys
from datetime import date, datetime, timedelta

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont






# -- Reuzycie helperow z report_excel (dual-import: standalone / Airflow) ------
try:
    from report_excel import (
        _db, ENV, REPORTS_DIR, REPORT_SCHEMAS, _safe_fetch, cleanup_reports,
    )
except ImportError:
    from tasks.report_excel import (
        _db, ENV, REPORTS_DIR, REPORT_SCHEMAS, _safe_fetch, cleanup_reports,
    )



# -- Czcionka z polskimi znakami (cross-platform) -----------------------------
def _register_font():
    candidates = [
        (os.environ.get("PKP_FONT_REGULAR"), os.environ.get("PKP_FONT_BOLD")),
        ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
         "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
        (r"C:\Windows\Fonts\arial.ttf", r"C:\Windows\Fonts\arialbd.ttf"),
    ]
    for regular, bold in candidates:
        if regular and bold and os.path.exists(regular) and os.path.exists(bold):
            try:
                pdfmetrics.registerFont(TTFont("PKPFont", regular))
                pdfmetrics.registerFont(TTFont("PKPFont-Bold", bold))
                print(f"[report_pdf] Czcionka: {regular}")
                return "PKPFont", "PKPFont-Bold"
            except Exception as e:
                print(f"[report_pdf] Nie udalo sie zaladowac {regular}: {e}")
    print("[report_pdf] Fallback Helvetica (brak polskich znakow).")
    return "Helvetica", "Helvetica-Bold"


FONT_NORMAL, FONT_BOLD = _register_font()

COLOR_DARK_BLUE = colors.HexColor("#1F4E79")
COLOR_LIGHT = colors.HexColor("#F5F5F5")
COLOR_BORDER = colors.HexColor("#CCCCCC")


def _styles():
    return {
        "title": ParagraphStyle("title", fontName=FONT_BOLD, fontSize=16,
                                textColor=COLOR_DARK_BLUE, spaceAfter=4, alignment=TA_CENTER),
        "subtitle": ParagraphStyle("subtitle", fontName=FONT_NORMAL, fontSize=10, 
                                   textColor=colors.grey, spaceBefore=6, spaceAfter=6, alignment=TA_CENTER),
        "section": ParagraphStyle("section", fontName=FONT_BOLD, fontSize=12,
                                  textColor=COLOR_DARK_BLUE, spaceBefore=10, spaceAfter=8),
        "sub": ParagraphStyle("sub", fontName=FONT_BOLD, fontSize=9,
                              textColor=colors.black, spaceBefore=8, spaceAfter=2),
        "normal": ParagraphStyle("normal", fontName=FONT_NORMAL, fontSize=9),
        "cell": ParagraphStyle("cell", fontName=FONT_NORMAL, fontSize=7, alignment=TA_LEFT,
                               leading=8),
        "footer": ParagraphStyle("footer", fontName=FONT_NORMAL, fontSize=8,
                                 textColor=colors.grey, alignment=TA_CENTER),
    }


def _table(data, col_widths, align_right_from=1):
    t = Table(data, colWidths=col_widths)
    t.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (-1, -1), FONT_NORMAL),
        ("FONTNAME", (0, 0), (-1, 0), FONT_BOLD),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("BACKGROUND", (0, 0), (-1, 0), COLOR_DARK_BLUE),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, COLOR_LIGHT]),
        ("GRID", (0, 0), (-1, -1), 0.4, COLOR_BORDER),
        ("ALIGN", (align_right_from, 0), (-1, -1), "RIGHT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    return t


def _esc(text) -> str:
    """Escape pod Paragraph (query stringi maja & -> encja)."""
    return (str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


# -- Zrodla danych (kazde odporne na blad) ------------------------------------
def _schema_sizes(conn, schemas):
    rows, total = [], 0.0
    for schema in schemas:
        _, res = _safe_fetch(
            conn,
            "SELECT ROUND(SUM(bytes)/1024/1024, 2) FROM dba_segments WHERE owner = :owner",
            {"owner": schema},
        )
        mb = (res[0][0] if res and res[0] and res[0][0] is not None else None)
        rows.append((schema, mb))
        if mb:
            total += mb
    return rows, round(total, 2)


def _bucket_rows():
    """[(nazwa, obiekty, mb), ...] dla obu bucketow. Blad jednego -> N/A w wierszu."""
    rows = []
    try:
        try:
            from pkp_ingestion.storage.oci_uploader import OciUploader
            from pkp_ingestion.settings import OCI_BUCKET, OCI_BUCKET_LIVE
        except ImportError:
            from ingestion.pkp_ingestion.storage.oci_uploader import OciUploader
            from ingestion.pkp_ingestion.settings import OCI_BUCKET, OCI_BUCKET_LIVE

        up = OciUploader()  # potrzebny tylko client + namespace
        for name in (OCI_BUCKET, OCI_BUCKET_LIVE):
            try:
                resp = up.client.get_bucket(
                    up.namespace, name,
                    fields=["approximateSize", "approximateCount"],
                )
                size_b = getattr(resp.data, "approximate_size", None)
                cnt = getattr(resp.data, "approximate_count", None)
                mb = round(size_b / 1024 / 1024, 2) if size_b is not None else None
                rows.append((name, cnt, mb))
            except Exception as e:
                print(f"[report_pdf] get_bucket({name}) blad: {e}")
                rows.append((name, None, None))
    except Exception as e:
        print(f"[report_pdf] Blad OCI (klient/namespace): {e}")
    return rows


def _api_data():
    """Zwraca (info_data, usage_data) - zawartosc pola 'data'. Blad -> ({}, {})."""
    try:
        from pkp_ingestion.domains import apikey
    except ImportError:
        try:
            from ingestion.pkp_ingestion.domains import apikey
        except Exception as e:
            print(f"[report_pdf] Blad importu apikey: {e}")
            return {}, {}
    info_data, usage_data = {}, {}
    try:
        info_data = (apikey.get_info() or {}).get("data", {}) or {}
    except Exception as e:
        print(f"[report_pdf] apikey/info blad: {e}")
    try:
        usage_data = (apikey.get_usage() or {}).get("data", {}) or {}
    except Exception as e:
        print(f"[report_pdf] apikey/usage blad: {e}")
    return info_data, usage_data


# -- Generator PDF ------------------------------------------------------------
def generate_summary_pdf(run_date: str, conn) -> str:
    st = _styles()
    page_w = A4[0] - 4 * cm
    elems = []

    elems.append(Paragraph("Raport utrzymaniowy PKP", st["title"]))
    elems.append(Paragraph(f"{run_date} &nbsp;|&nbsp; srodowisko: {ENV}", st["subtitle"]))
    elems.append(HRFlowable(width="100%", thickness=1.2, color=COLOR_DARK_BLUE))

    # ---- Zajetosc bazy ----
    elems.append(Paragraph("Zajetosc bazy (per schemat)", st["section"]))
    schema_rows, total_mb = _schema_sizes(conn, REPORT_SCHEMAS)
    data = [["Schemat", "Rozmiar [MB]"]]
    for schema, mb in schema_rows:
        data.append([schema, "N/A" if mb is None else f"{mb:,.2f}"])
    data.append(["TOTAL", f"{total_mb:,.2f}"])
    t = _table(data, [page_w * 0.6, page_w * 0.4])
    t.setStyle(TableStyle([("FONTNAME", (0, -1), (-1, -1), FONT_BOLD),
                           ("BACKGROUND", (0, -1), (-1, -1), COLOR_LIGHT)]))
    elems.append(t)

    # ---- Object Storage (dwa buckety) ----
    elems.append(Paragraph("Object Storage (buckety)", st["section"]))
    data = [["Bucket", "Obiekty", "Rozmiar [MB]"]]
    b_rows = _bucket_rows()
    if b_rows:
        for name, cnt, mb in b_rows:
            data.append([
                name,
                "N/A" if cnt is None else f"{cnt:,}",
                "N/A" if mb is None else f"{mb:,.2f}",
            ])
    else:
        data.append(["N/A", "N/A", "N/A"])
    elems.append(_table(data, [page_w * 0.5, page_w * 0.25, page_w * 0.25]))

    # ---- API ----
    elems.append(Paragraph("API - limity i zuzycie", st["section"]))
    info, usage = _api_data()
    daily_limit = info.get("dailyRateLimit")

    # (a) limity klucza
    elems.append(Paragraph("Klucz", st["sub"]))
    data = [
        ["Poziom dostepu", str(info.get("accessLevel", "N/A"))],
        ["Limit dzienny", str(daily_limit if daily_limit is not None else "N/A")],
        ["Limit godzinowy", str(info.get("hourlyRateLimit", "N/A"))],
        ["Zapytania lacznie (klucz)", str(info.get("totalRequests", "N/A"))],
    ]
    elems.append(_table(data, [page_w * 0.6, page_w * 0.4]))

    # (b) zuzycie wczoraj / dzis
    elems.append(Paragraph("Zuzycie: wczoraj i dzis", st["sub"]))
    by_date = {d.get("date"): d for d in usage.get("dailyUsage", [])}
    today_s = run_date
    yday_s = (date.fromisoformat(run_date) - timedelta(days=1)).isoformat()

    def _usage_row(label, dstr):
        d = by_date.get(dstr, {})
        req = d.get("requestCount", 0)
        avg = d.get("averageResponseTime")
        err = d.get("errorCount", 0)
        pct = (f"{req / daily_limit * 100:.1f}%"
               if daily_limit else "N/A")
        avg_s = "-" if avg is None else f"{avg:.0f}"
        return [f"{label} ({dstr})", f"{req:,}", pct, avg_s, str(err)]

    data = [["Dzien", "Zapytania", "% limitu dz.", "Sr. czas [ms]", "Bledy"],
            _usage_row("Wczoraj", yday_s),
            _usage_row("Dzis", today_s)]
    elems.append(_table(data, [page_w * 0.34, page_w * 0.16, page_w * 0.18,
                               page_w * 0.18, page_w * 0.14]))

    # (c) ranking top endpoints
    elems.append(Paragraph("Top endpoints (okno API)", st["sub"]))
    top = usage.get("topEndpoints", []) or []
    if top:
        data = [["#", "Endpoint", "Zapytania"]]
        for i, ep in enumerate(top[:10], 1):
            data.append([
                str(i),
                Paragraph(_esc(ep.get("endpoint", "")), st["cell"]),
                f"{ep.get('requestCount', 0):,}",
            ])
        t = _table(data, [page_w * 0.06, page_w * 0.78, page_w * 0.16], align_right_from=2)
        t.setStyle(TableStyle([("ALIGN", (0, 0), (0, -1), "CENTER")]))
        elems.append(t)
    else:
        elems.append(Paragraph("Brak danych o endpointach.", st["normal"]))

    # ---- Stopka ----
    elems.append(Spacer(1, 0.5 * cm))
    elems.append(HRFlowable(width="100%", thickness=0.5, color=COLOR_BORDER))
    elems.append(Paragraph(
        f"Wygenerowano automatycznie {datetime.now():%Y-%m-%d %H:%M:%S} | ENV={ENV}",
        st["footer"]))

    file_path = os.path.join(REPORTS_DIR, f"summary_{run_date}.pdf")
    doc = SimpleDocTemplate(file_path, pagesize=A4,
                            leftMargin=2 * cm, rightMargin=2 * cm,
                            topMargin=2 * cm, bottomMargin=2 * cm)
    doc.build(elems)
    print(f"[report_pdf] Zapisano: {file_path}")
    return file_path


# -- Test reczny --------------------------------------------------------------
if __name__ == "__main__":
    today = date.today().isoformat()
    print(f"[report_pdf] ENV={ENV}  katalog={REPORTS_DIR}")
    cleanup_reports("summary_*.pdf")
    conn = _db.get_connection()
    try:
        generate_summary_pdf(today, conn)
    finally:
        conn.close()
    print("Gotowe.")