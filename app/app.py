import os
import string
import random

import psycopg2
from flask import Flask, jsonify, redirect, request

app = Flask(__name__)

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


init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
