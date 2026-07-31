"""
oci_uploader.py
---------------
Upload plikow do OCI Object Storage (bucket bronze) z weryfikacja MD5.

Auth: profil z ~/.oci/config (klucz API uzytkownika) - NIE wallet DB.
Namespace pobierany automatycznie (get_namespace).
Weryfikacja: liczymy MD5 lokalnie, przekazujemy jako content_md5 (OCI waliduje
po stronie serwera) i dodatkowo porownujemy z opc-content-md5 z odpowiedzi.
"""

import base64
import hashlib
from pathlib import Path

import oci

from ..settings import OCI_PROFILE, OCI_BUCKET


class OciUploader:
    def __init__(self, profile: str = OCI_PROFILE, bucket: str = OCI_BUCKET):
        config = oci.config.from_file(profile_name=profile)
        self.client = oci.object_storage.ObjectStorageClient(config)
        self.namespace = self.client.get_namespace().data
        self.bucket = bucket

    def upload_file(self, local_path: Path, object_name: str) -> None:
        """
        Wgrywa plik pod object_name. Rzuca wyjatek gdy MD5 sie nie zgadza
        lub SDK zglosi blad - obsluga (ERR) jest po stronie wolajacego.
        """
        data = local_path.read_bytes()
        md5_b64 = base64.b64encode(hashlib.md5(data).digest()).decode("ascii")

        resp = self.client.put_object(
            namespace_name=self.namespace,
            bucket_name=self.bucket,
            object_name=object_name,
            put_object_body=data,
            content_md5=md5_b64,          # OCI odrzuci (400) przy niezgodnosci
        )

        # Twarda weryfikacja: echo MD5 z serwera musi sie zgadzac
        returned = resp.headers.get("opc-content-md5")
        if returned != md5_b64:
            raise ValueError(
                f"Niezgodnosc MD5 dla '{object_name}': serwer={returned} lokalny={md5_b64}"
            )