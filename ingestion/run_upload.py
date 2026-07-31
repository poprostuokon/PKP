"""
run_upload.py
-------------
Entrypoint: wgranie plikow z TODO do OCI (drugi etap).
Uruchamiaj z katalogu 'ingestion':  python run_upload.py
"""

from pkp_ingestion.upload import run_upload

if __name__ == "__main__":
    run_upload()