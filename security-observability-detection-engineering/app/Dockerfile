FROM python:3.12-alpine

WORKDIR /app

COPY requirements.txt .

RUN pip install \
    --no-cache-dir \
    -r requirements.txt

COPY exporter.py .

EXPOSE 8000

USER 65532:65532

CMD ["python", "/app/exporter.py", "--mode", "normal"]
