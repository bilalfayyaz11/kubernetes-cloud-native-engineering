FROM python:3.12-alpine

WORKDIR /app

COPY app/server.py /app/server.py

RUN addgroup -S appgroup \
    && adduser -S -G appgroup -u 10001 appuser \
    && chown -R appuser:appgroup /app

USER 10001:10001

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health')" || exit 1

CMD ["python", "/app/server.py"]
