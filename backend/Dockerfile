FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt ./requirements.txt
RUN python -m pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080
CMD ["gunicorn", "-c", "gunicorn_conf.py", "app.main:app"]
