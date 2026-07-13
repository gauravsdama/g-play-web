FROM python:3.12.12-slim-bookworm
WORKDIR /app
ENV PYTHONUNBUFFERED=1
ENV PORT=9137
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*
COPY backend/requirements.txt backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt
RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin vantabeat \
    && mkdir -p /app/library /app/edited /app/playlists /app/logs \
    && chown -R vantabeat:vantabeat /app
COPY --chown=vantabeat:vantabeat backend ./backend
USER vantabeat
EXPOSE 9137
CMD ["/bin/sh", "-c", "uvicorn backend.app.main:app --host 0.0.0.0 --port ${PORT} --no-access-log"]
