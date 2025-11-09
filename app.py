from flask import Flask, request, jsonify
import sqlite3, os

DB_PATH = os.environ.get("SQLITE_PATH", "/data/app.db")
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT)")
    return conn

app = Flask(__name__)

@app.route("/")
def health():
    return "OK", 200

@app.route("/notes", methods=["GET", "POST"])
def notes():
    conn = get_conn()
    if request.method == "POST":
        txt = request.json.get("text", "")
        conn.execute("INSERT INTO notes(text) VALUES(?)", (txt,))
        conn.commit()
    cur = conn.execute("SELECT id, text FROM notes ORDER BY id DESC")
    return jsonify([{"id": r[0], "text": r[1]} for r in cur.fetchall()])
