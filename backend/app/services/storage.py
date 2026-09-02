import base64
import io
import os
import uuid

from fastapi import HTTPException, status
from PIL import Image

from app.config import settings


def _ensure_upload_dir() -> str:
    os.makedirs(settings.UPLOAD_DIR, exist_ok=True)
    return settings.UPLOAD_DIR


def save_selfie(base64_data: str, student_id: int) -> str:
    """Decode a base64 selfie, compress to <= MAX_SELFIE_SIZE_KB, store outside the webroot.

    Returns the relative storage path (not a public URL) to persist on the attendance record.
    """
    if "," in base64_data:
        base64_data = base64_data.split(",", 1)[1]

    try:
        raw = base64.b64decode(base64_data)
        image = Image.open(io.BytesIO(raw))
        image = image.convert("RGB")
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid selfie image data")

    upload_dir = _ensure_upload_dir()
    filename = f"{uuid.uuid4().hex}_{student_id}.jpg"
    filepath = os.path.join(upload_dir, filename)

    quality = 85
    max_bytes = settings.MAX_SELFIE_SIZE_KB * 1024
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=quality)

    while buffer.tell() > max_bytes and quality > 20:
        quality -= 10
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", quality=quality)

    with open(filepath, "wb") as f:
        f.write(buffer.getvalue())

    return filepath


def read_selfie(filepath: str) -> bytes:
    if not filepath or not os.path.abspath(filepath).startswith(os.path.abspath(settings.UPLOAD_DIR)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Selfie not found")
    if not os.path.exists(filepath):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Selfie not found")
    with open(filepath, "rb") as f:
        return f.read()
