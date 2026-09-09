import base64
import io

from fastapi import HTTPException, status
from PIL import Image

from app.config import settings


def _compress_image(base64_data: str, max_size_kb: int) -> bytes:
    """Decode a base64 image and compress it to <= max_size_kb, returning raw JPEG bytes.

    Images are stored as bytes directly on the owning row (selfie_photo / profile_photo /
    photo_path columns) rather than as files on local disk. This app's target deployment
    (Render's free tier) has an EPHEMERAL filesystem: anything written to disk is wiped on
    every restart/redeploy and on every free-tier cold-start after ~15 min idle, which is
    constant. A file-based store would (and did) silently lose every photo shortly after
    upload with no error at read time — just a 404 next time someone viewed it. Storing the
    bytes in Postgres, which Render's free tier persists properly, avoids that whole class of
    failure without needing a separate object-storage service.
    """
    if "," in base64_data:
        base64_data = base64_data.split(",", 1)[1]

    try:
        raw = base64.b64decode(base64_data)
        image = Image.open(io.BytesIO(raw))
        image = image.convert("RGB")
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid image data")

    quality = 85
    max_bytes = max_size_kb * 1024
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=quality)

    while buffer.tell() > max_bytes and quality > 20:
        quality -= 10
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", quality=quality)

    return buffer.getvalue()


def save_selfie(base64_data: str) -> bytes:
    return _compress_image(base64_data, settings.MAX_SELFIE_SIZE_KB)


def save_student_photo(base64_data: str) -> bytes:
    return _compress_image(base64_data, settings.MAX_SELFIE_SIZE_KB)


def save_class_photo(base64_data: str) -> bytes:
    return _compress_image(base64_data, settings.MAX_SELFIE_SIZE_KB)
