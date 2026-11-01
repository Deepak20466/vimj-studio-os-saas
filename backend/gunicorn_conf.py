import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8000')}"
# Cloud Run's 1-vCPU/1-GiB instance has limited memory. Four Uvicorn workers
# each import the full API and start their own APScheduler, increasing startup time and
# duplicating scheduled jobs. Use one worker by default; larger plans can opt in
# to more with WEB_CONCURRENCY.
workers = max(1, int(os.environ.get("WEB_CONCURRENCY", "1")))
worker_class = "uvicorn.workers.UvicornWorker"
timeout = 30
graceful_timeout = 30
keepalive = 5
accesslog = "-"
errorlog = "-"
loglevel = "info"
