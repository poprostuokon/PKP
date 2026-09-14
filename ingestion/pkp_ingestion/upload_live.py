"""
upload_live.py
--------------
Upload delt LIVE z TODO/LIVE/DATA do osobnego bucketu (bronze-pkp-live).
Model jak daily: KAZDY plik niezaleznie (izolacja bledu).
  - upload + MD5 OK  -> ARCHIVE/LIVE/<date>  (delta zostaje na zawsze = zrodlo do replay)
  - blad             -> ERR/LIVE/<date> + slad w err_<run_ts>.txt
Partycja <date> = data ingestii (run_ts[:8]); delta moze miec kilka operatingDate,
wlasciwa partycja per rekord jest w DB.
"""

import shutil
import traceback
from datetime import datetime, timezone
from pathlib import Path

from .storage.oci_uploader import OciUploader
from .settings import OCI_BUCKET_LIVE
from .paths import (
    todo_live_data_dir,
    bucket_object_name_live,
    parse_filename,
    archive_live_dir,
    err_live_dir,
    err_filename,
)


def _collect_live_files() -> list[Path]:
    d = todo_live_data_dir()
    return sorted(d.glob("*.json")) if d.exists() else []


def _move(src: Path, dst_dir: Path) -> Path:
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / src.name
    shutil.move(str(src), str(dst))
    return dst


def _write_err(part_date: str, run_ts: str, filename: str, exc: Exception) -> None:
    target = err_live_dir(part_date)
    target.mkdir(parents=True, exist_ok=True)
    entry = (
        f"[{datetime.now(timezone.utc).isoformat()}] UPLOAD LIVE ERROR\n"
        f"  plik      : {filename}\n"
        f"  wyjatek   : {exc.__class__.__name__}: {exc}\n"
        f"  traceback :\n{traceback.format_exc()}\n"
        f"{'-' * 60}\n"
    )
    with open(target / err_filename(run_ts), "a", encoding="utf-8") as f:
        f.write(entry)


def run_upload_live() -> set[str]:
    run_ts = datetime.now().strftime("%Y%m%d%H%M%S")
    uploader = OciUploader(bucket=OCI_BUCKET_LIVE)

    files = _collect_live_files()
    ok_files: set[str] = set()
    if not files:
        return ok_files
    print(f"LIVE do wgrania: {len(files)} plikow (bucket={uploader.bucket})")

    ok = err = 0
    for path in files:
        filename = path.name
        _, _, part_date = parse_filename(filename)
        try:
            object_name = bucket_object_name_live(filename)
            uploader.upload_file(path, object_name)
            dst = _move(path, archive_live_dir(part_date))
            print(f"OK   {filename} -> oci:{object_name} | archive:{dst}")
            ok += 1
            ok_files.add(filename)          # <- zapamietaj sukces
        except Exception as exc:
            _move(path, err_live_dir(part_date))
            _write_err(part_date, run_ts, filename, exc)
            print(f"ERR  {filename} -> ERR/LIVE/{part_date} ({exc.__class__.__name__})")
            err += 1

    print(f"LIVE zakonczono: OK={ok}, ERR={err}")
    return ok_files


if __name__ == "__main__":
    run_upload_live()