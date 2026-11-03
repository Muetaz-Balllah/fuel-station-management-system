import mimetypes
import re
from pathlib import Path

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from config import settings

_LOCAL_DIR = Path("uploads")
_SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]+$")


class ImageStore:
    """Local disk (dev) or S3-compatible object storage (Render / Tigris / R2 / MinIO)."""

    def __init__(self) -> None:
        self._s3 = None

    def is_s3(self) -> bool:
        return bool(settings.aws_endpoint_url_s3 and settings.s3_bucket)

    def ping(self) -> bool:
        if not self.is_s3():
            return _LOCAL_DIR.is_dir()
        try:
            self._client().head_bucket(Bucket=settings.s3_bucket)
            return True
        except (BotoCoreError, ClientError):
            return False

    def delete_stem(self, stem: str) -> None:
        if not _SAFE_NAME.match(stem):
            return
        if self.is_s3():
            stem_prefix = self._object_key(f"{stem}.")
            try:
                client = self._client()
                response = client.list_objects_v2(Bucket=settings.s3_bucket, Prefix=stem_prefix)
                for item in response.get("Contents", []):
                    client.delete_object(Bucket=settings.s3_bucket, Key=item["Key"])
            except (BotoCoreError, ClientError):
                pass
            return
        if _LOCAL_DIR.is_dir():
            for old in _LOCAL_DIR.glob(f"{stem}.*"):
                old.unlink(missing_ok=True)

    def save(self, *, data: bytes, filename: str, content_type: str) -> None:
        if not _SAFE_NAME.match(filename):
            raise ValueError("invalid filename")
        if self.is_s3():
            try:
                self._client().put_object(
                    Bucket=settings.s3_bucket,
                    Key=self._object_key(filename),
                    Body=data,
                    ContentType=content_type,
                )
            except (BotoCoreError, ClientError) as exc:
                raise OSError("s3 upload failed") from exc
            return
        _LOCAL_DIR.mkdir(parents=True, exist_ok=True)
        (_LOCAL_DIR / filename).write_bytes(data)

    def load(self, filename: str) -> tuple[bytes, str]:
        if not _SAFE_NAME.match(filename):
            raise FileNotFoundError(filename)
        if self.is_s3():
            response = self._client().get_object(
                Bucket=settings.s3_bucket,
                Key=self._object_key(filename),
            )
            body = response["Body"].read()
            ctype = response.get("ContentType") or _guess_type(filename)
            return body, ctype
        path = _LOCAL_DIR / filename
        if not path.is_file():
            raise FileNotFoundError(filename)
        return path.read_bytes(), _guess_type(filename)

    def public_path(self, filename: str, *, version: int) -> str:
        base = settings.s3_public_base_url.rstrip("/") if (self.is_s3() and settings.s3_public_base_url) else None
        if base:
            return f"{base}/{self._object_key(filename)}?v={version}"
        return f"/api/v1/media/{filename}?v={version}"

    def _object_key(self, filename: str) -> str:
        prefix = settings.s3_prefix.strip("/")
        return f"{prefix}/{filename}" if prefix else filename

    def _client(self):
        if self._s3 is None:
            kwargs: dict = {}
            if settings.aws_endpoint_url_s3:
                kwargs["endpoint_url"] = settings.aws_endpoint_url_s3
            if settings.aws_region and settings.aws_region != "auto":
                kwargs["region_name"] = settings.aws_region
            self._s3 = boto3.client("s3", **kwargs)
        return self._s3


def _guess_type(filename: str) -> str:
    guessed, _ = mimetypes.guess_type(filename)
    return guessed or "application/octet-stream"


image_store = ImageStore()
