"""
oci_reader.py
-------------
Odczyt obiektow z OCI Object Storage (bucket bronze) - pobieranie do prepare_stg.
Ten sam profil ~/.oci/config co uploader; namespace pobierany automatycznie.
Timeout (connect, read/write) + strojony retry - spojne z OciUploader.
"""

import oci

from ..settings import (
    OCI_PROFILE, OCI_BUCKET,
    OCI_CONNECT_TIMEOUT, OCI_READ_TIMEOUT,
    OCI_RETRY_MAX_ATTEMPTS, OCI_RETRY_TOTAL_SECONDS,
)


class OciReader:
    def __init__(self, profile: str = OCI_PROFILE, bucket: str = OCI_BUCKET):
        config = oci.config.from_file(profile_name=profile)
        self.client = oci.object_storage.ObjectStorageClient(
            config,
            timeout=(OCI_CONNECT_TIMEOUT, OCI_READ_TIMEOUT),
        )
        self.namespace = self.client.get_namespace().data
        self.bucket = bucket
        self._retry = self._build_retry_strategy()

    @staticmethod
    def _build_retry_strategy():
        """Strojona strategia retry: backoff + jitter, ponawia bledy przejsciowe."""
        return oci.retry.RetryStrategyBuilder(
            max_attempts_check=True, max_attempts=OCI_RETRY_MAX_ATTEMPTS,
            total_elapsed_time_check=True, total_elapsed_time_seconds=OCI_RETRY_TOTAL_SECONDS,
            retry_base_sleep_time_seconds=2,
            retry_max_wait_between_calls_seconds=30,
            backoff_type=oci.retry.BACKOFF_FULL_JITTER_EQUAL_ON_THROTTLE_VALUE,
            service_error_check=True,
            service_error_retry_on_any_5xx=True,
            connection_error_check=True,   # 'Connection aborted' / read timed out
            timeout_check=True,            # read/write timeout
        ).get_retry_strategy()

    def list_objects(self, prefix: str) -> list[str]:
        """Zwraca nazwy obiektow pod prefiksem (z obsluga paginacji listy)."""
        names: list[str] = []
        start = None
        while True:
            resp = self.client.list_objects(
                self.namespace, self.bucket, prefix=prefix, start=start, fields="name",
                retry_strategy=self._retry,
            )
            names.extend(o.name for o in resp.data.objects)
            start = resp.data.next_start_with
            if not start:
                break
        return names

    def download_text(self, object_name: str) -> str:
        """Pobiera obiekt i zwraca jego tresc jako tekst (surowy JSON)."""
        resp = self.client.get_object(
            self.namespace, self.bucket, object_name,
            retry_strategy=self._retry,
        )
        return resp.data.content.decode("utf-8")