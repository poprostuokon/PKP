"""
oci_reader.py
-------------
Odczyt obiektow z OCI Object Storage (bucket bronze) - pobieranie do prepare_stg.
Ten sam profil ~/.oci/config co uploader; namespace pobierany automatycznie.
"""

import oci

from ..settings import OCI_PROFILE, OCI_BUCKET


class OciReader:
    def __init__(self, profile: str = OCI_PROFILE, bucket: str = OCI_BUCKET):
        config = oci.config.from_file(profile_name=profile)
        self.client = oci.object_storage.ObjectStorageClient(config)
        self.namespace = self.client.get_namespace().data
        self.bucket = bucket

    def list_objects(self, prefix: str) -> list[str]:
        """Zwraca nazwy obiektow pod prefiksem (z obsluga paginacji listy)."""
        names: list[str] = []
        start = None
        while True:
            resp = self.client.list_objects(
                self.namespace, self.bucket, prefix=prefix, start=start, fields="name"
            )
            names.extend(o.name for o in resp.data.objects)
            start = resp.data.next_start_with
            if not start:
                break
        return names

    def download_text(self, object_name: str) -> str:
        """Pobiera obiekt i zwraca jego tresc jako tekst (surowy JSON)."""
        resp = self.client.get_object(self.namespace, self.bucket, object_name)
        return resp.data.content.decode("utf-8")