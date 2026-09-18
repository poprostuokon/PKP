FROM apache/airflow:2.9.0-python3.10

USER root
# minimalne zaleznosci systemowe (bez Chrome/Selenium — PKP ciagnie z API)
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc g++ curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

USER airflow

# zaleznosci PKP dla Airflow (Oracle thin, OCI, walidacja, raport, mail)
COPY orchestration/airflow_prod/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt