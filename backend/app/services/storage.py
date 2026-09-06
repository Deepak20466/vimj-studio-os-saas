import base64
import io
import os
import uuid

from fastapi import HTTPException, status
from PIL import Image

from app.config import settings


def _ensure_dir(upload_dir: str) -> str:
    os.makedirs(upload_dir, exist_ok=True)
    return upload_dir


def _save_compressed_image(base64_data: str, upload_dir: str, name_hint: str, max_size_kb: int) -> str:
    """Decode a base64 image, compress to <= max_size_kb, store outside the webroot.

    Returns the relative storage path (not a public URL) to persist on the record.
    """
    if "," in base64_data:
        base64_data = base64_data.split(",", 1)[1]

    try:
        raw = base64.b64decode(base64_data)
        image = Image.open(io.BytesIO(raw))
        image = image.convert("RGB")
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid image data")

    _ensure_dir(upload_dir)
    filename = f"{uuid.uuid4().hex}_{name_hint}.jpg"
    filepath = os.path.join(upload_dir, filename)

    quality = 85
    max_bytes = max_size_kb * 1024
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=quality)

    while buffer.tell() > max_bytes and quality > 20:
        quality -= 10
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", quality=quality)

    with open(filepath, "wb") as f:
        f.write(buffer.getvalue())

    return filepath


def save_selfie(base64_data: str, student_id: int) -> str:
    return _save_compressed_image(base64_data, settings.UPLOAD_DIR, str(student_id), settings.MAX_SELFIE_SIZE_KB)


def save_student_photo(base64_data: str, student_id: int) -> str:
    return _save_compressed_image(base64_data, settings.STUDENT_PHOTO_DIR, str(student_id), settings.MAX_SELFIE_SIZE_KB)


def save_class_photo(base64_data: str, class_id: int) -> str:
    return _save_compressed_image(base64_data, settings.CLASS_PHOTO_DIR, str(class_id), settings.MAX_SELFIE_SIZE_KB)


def _read_image(filepath: str, allowed_dir: str) -> bytes:
    if not filepath or not os.path.abspath(filepath).startswith(os.path.abspath(allowed_dir)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")
    if not os.path.exists(filepath):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")
    with open(filepath, "rb") as f:
        return f.read()


def read_selfie(filepath: str) -> bytes:
    return _read_image(filepath, settings.UPLOAD_DIR)


def read_student_photo(filepath: str) -> bytes:
    return _read_image(filepath, settings.STUDENT_PHOTO_DIR)


def read_class_photo(filepath: str) -> bytes:
    return _read_image(filepath, settings.CLASS_PHOTO_DIR)
