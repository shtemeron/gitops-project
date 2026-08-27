import os
import string
import random
import time

import psycopg2
from flask import Flask, g, jsonify, redirect, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

app = Flask(__name__)

REQUEST_COUNT = Counter(
    "app_requests_total", "Total HTTP requests", ["endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "app_request_latency_seconds", "Request latency in seconds", ["endpoint"]
)

# added by me to trigger ci-cd
# second time
# third time

@app.before_request
def _start_timer():
    g.start_time = time.time()


@app.after_request
def _record_metrics(response):
    # request.endpoint is None for 404s on unmatched routes — nothing
    # meaningful to label those with, so skip rather than lump them
    # under a fake name. Also skip /metrics itself, or Prometheus's own
    # scrapes show up as traffic in the app's own metrics.
    if request.endpoint and request.endpoint != "metrics":
        REQUEST_LATENCY.labels(endpoint=request.endpoint).observe(
            time.time() - g.start_time
        )
        REQUEST_COUNT.labels(
            endpoint=request.endpoint, status=response.status_code
        ).inc()
    return response

# Plain string, not a template file — this is a one-page manual test
# harness for exercising /shorten + /<code> from a browser instead of
# chaining two curl commands, nothing more.
INDEX_HTML = """<!doctype html>
<title>url-shortener test</title>
<h1>url-shortener test</h1>
<input id="url" size="60" placeholder="https://example.com" value="https://example.com">
<button onclick="shorten()">Shorten</button>
<p id="result"></p>
<script>
async function shorten() {
  const res = await fetch("/shorten", {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({url: document.getElementById("url").value})
  });
  const data = await res.json();
  document.getElementById("result").innerHTML = res.ok
    ? `short_code: <b>${data.short_code}</b> &mdash; <a href="/${data.short_code}" target="_blank">follow it</a>`
    : `error: ${data.error}`;
}
</script>
"""

DB_CONFIG = {
    "host": os.environ["DB_HOST"],
    "port": os.environ.get("DB_PORT", "5432"),
    "dbname": os.environ.get("DB_NAME", "urlshortener"),
    "user": os.environ["DB_USER"],
    "password": os.environ["DB_PASSWORD"],
}


def get_connection():
    return psycopg2.connect(**DB_CONFIG)


def init_db():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS urls (
                    short_code VARCHAR(10) PRIMARY KEY,
                    original_url TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT NOW()
                )
                """
            )
        conn.commit()


def generate_short_code(length=6):
    alphabet = string.ascii_letters + string.digits
    return "".join(random.choices(alphabet, k=length))


@app.route("/", methods=["GET"])
def index():
    return INDEX_HTML


@app.route("/shorten", methods=["POST"])
def shorten():
    body = request.get_json(silent=True) or {}
    original_url = body.get("url")
    if not original_url:
        return jsonify({"error": "missing 'url' in request body"}), 400

    short_code = generate_short_code()
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO urls (short_code, original_url) VALUES (%s, %s)",
                (short_code, original_url),
            )
        conn.commit()

    return jsonify({"short_code": short_code, "original_url": original_url}), 201


@app.route("/<short_code>", methods=["GET"])
def resolve(short_code):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT original_url FROM urls WHERE short_code = %s", (short_code,)
            )
            row = cur.fetchone()

    if row is None:
        return jsonify({"error": "short code not found"}), 404

    return redirect(row[0], code=302)


@app.route("/healthz", methods=["GET"])
def healthz():
    # Liveness: the process is up. Deliberately no DB check here — a
    # Postgres outage should stop traffic being routed to this pod
    # (readyz's job), not restart a perfectly healthy process.
    return jsonify({"status": "ok"}), 200


@app.route("/readyz", methods=["GET"])
def readyz():
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
    except psycopg2.OperationalError:
        return jsonify({"status": "db unreachable"}), 503
    return jsonify({"status": "ok"}), 200


@app.route("/metrics", methods=["GET"])
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
