from fastapi import APIRouter, Response

from core.storage import image_store
from errors import AppError

router = APIRouter(tags=["media"])


@router.get("/media/{filename}")
def get_media(filename: str) -> Response:
    try:
        data, content_type = image_store.load(filename)
    except FileNotFoundError as exc:
        raise AppError("NOT_FOUND", "الصورة غير موجودة.", 404) from exc
    return Response(content=data, media_type=content_type, headers={"Cache-Control": "public, max-age=86400"})
