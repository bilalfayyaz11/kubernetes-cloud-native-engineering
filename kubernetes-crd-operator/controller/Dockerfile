FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install \
    --no-cache-dir \
    -r requirements.txt

COPY webapp-controller.py .

USER 65532:65532

CMD ["python3", "/app/webapp-controller.py"]
