"""
oci_uploader.py
---------------
Upload plikow do OCI Object Storage (bucket bronze) z weryfikacja MD5.

Auth: profil z ~/.oci/config (klucz API uzytkownika) - NIE wallet DB.
Timeout: (connect, read/write) z settings - read/write chroni przed urwaniem body.
Retry: strojona strategia (ponawia timeouty, zerwane polaczenia, 429, 5xx) -
       plik trafia do ERR dopiero po wyczerpaniu prob.
"""

import base64
import hashlib
from pathlib import Path

import oci

from ..settings import (
    OCI_PROFILE, OCI_BUCKET,
    OCI_CONNECT_TIMEOUT, OCI_UPLOAD_TIMEOUT,
    OCI_RETRY_MAX_ATTEMPTS, OCI_RETRY_TOTAL_SECONDS,
)


class OciUploader:
    def __init__(self, profile: str = OCI_PROFILE, bucket: str = OCI_BUCKET):
        config = oci.config.from_file(profile_name=profile)
        self.client = oci.object_storage.ObjectStorageClient(
            config,
            timeout=(OCI_CONNECT_TIMEOUT, OCI_UPLOAD_TIMEOUT),
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
            connection_error_check=True,   # 'Connection aborted' / write timed out
            timeout_check=True,            # read/write timeout
        ).get_retry_strategy()

    def upload_file(self, local_path: Path, object_name: str) -> None:
        """
        Wgrywa plik pod object_name. Rzuca wyjatek gdy MD5 sie nie zgadza
        lub SDK zglosi blad po wyczerpaniu prob - obsluga (ERR) po stronie wolajacego.
        """
        data = local_path.read_bytes()
        md5_b64 = base64.b64encode(hashlib.md5(data).digest()).decode("ascii")

        resp = self.client.put_object(
            namespace_name=self.namespace,
            bucket_name=self.bucket,
            object_name=object_name,
            put_object_body=data,
            content_md5=md5_b64,          # OCI odrzuci (400) przy niezgodnosci
            retry_strategy=self._retry,   # ponawianie bledow przejsciowych
        )

        # Twarda weryfikacja: echo MD5 z serwera musi sie zgadzac
        returned = resp.headers.get("opc-content-md5")
        if returned != md5_b64:
            raise ValueError(
                f"Niezgodnosc MD5 dla '{object_name}': serwer={returned} lokalny={md5_b64}"
            )