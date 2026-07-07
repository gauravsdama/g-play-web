FROM python:3.12-slim
WORKDIR /app
ENV PYTHONUNBUFFERED=1
ENV PORT=9137
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*
COPY backend/requirements.txt backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt
COPY backend ./backend
EXPOSE 9137
CMD ["/bin/sh", "-c", "uvicorn backend.app.main:app --host 0.0.0.0 --port ${PORT} --no-access-log"]
