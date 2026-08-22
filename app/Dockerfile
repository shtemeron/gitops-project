FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Non-root — Kyverno (Stage 7) will enforce this cluster-wide later;
# building it in now rather than retrofitting it then.
RUN useradd --uid 1000 --create-home appuser
USER appuser

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
