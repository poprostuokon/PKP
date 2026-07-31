"""
upload.py
---------
Drugi etap pipeline: wgranie plikow z TODO do OCI Object Storage.

Model produkcyjny: KAZDY plik obslugiwany niezaleznie (izolacja bledu).
  - upload + weryfikacja MD5 OK -> przeniesienie do ARCHIVE/DAILY/<date>
  - blad (upload/MD5/sieciowy)   -> przeniesienie do ERR/DAILY/<date>
                                    + dopisanie sladu do err_<run_ts>.txt
Blad jednego pliku NIE przerywa reszty - petla leci dalej.
"""

import shutil
import traceback
from datetime import datetime, timezone
from pathlib import Path

from .storage.oci_uploader import OciUploader
from .paths import (
    todo_dict_dir,
    todo_data_dir,
    bucket_object_name,
    parse_filename,
    archive_dir,
    err_dir,
    err_filename,
)


def _collect_todo_files() -> list[Path]:
    """Wszystkie pliki .json czekajace w TODO (DICT + DATA)."""
    files: list[Path] = []
    for directory in (todo_dict_dir(), todo_data_dir()):
        if directory.exists():
            files.extend(sorted(directory.glob("*.json")))
    return files


def _move(src: Path, dst_dir: Path) -> Path:
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / src.name
    shutil.move(str(src), str(dst))
    return dst


def _write_err(part_date: str, run_ts: str, filename: str, exc: Exception) -> None:
    """Dopisuje wpis o bledzie do err_<run_ts>.txt w ERR/DAILY/<date>."""
    target = err_dir(part_date)
    target.mkdir(parents=True, exist_ok=True)
    entry = (
        f"[{datetime.now(timezone.utc).isoformat()}] UPLOAD ERROR\n"
        f"  plik      : {filename}\n"
        f"  wyjatek   : {exc.__class__.__name__}: {exc}\n"
        f"  traceback :\n{traceback.format_exc()}\n"
        f"{'-' * 60}\n"
    )
    with open(target / err_filename(run_ts), "a", encoding="utf-8") as f:
        f.write(entry)


def run_upload() -> None:
    """Przebieg uploadu wszystkich plikow z TODO."""
    run_ts = datetime.now().strftime("%Y%m%d%H%M%S")
    uploader = OciUploader()

    files = _collect_todo_files()
    print(f"Do wgrania: {len(files)} plikow (bucket={uploader.bucket})")

    ok = err = 0
    for path in files:
        filename = path.name
        _, _, part_date = parse_filename(filename)
        try:
            object_name = bucket_object_name(filename)
            uploader.upload_file(path, object_name)
            dst = _move(path, archive_dir(part_date))
            print(f"OK   {filename} -> oci:{object_name} | archive:{dst}")
            ok += 1
        except Exception as exc:  # izolacja bledu per plik
            _move(path, err_dir(part_date))
            _write_err(part_date, run_ts, filename, exc)
            print(f"ERR  {filename} -> ERR/DAILY/{part_date} ({exc.__class__.__name__})")
            err += 1

    print(f"Zakonczono: OK={ok}, ERR={err}")


if __name__ == "__main__":
    run_upload()