import sqlite3
import json

def check_errors():
    conn = sqlite3.connect('data/ace_step.db')
    c = conn.cursor()
    c.execute("SELECT id, title, status, error_message FROM generations ORDER BY created_at DESC LIMIT 5")
    rows = c.fetchall()
    print(json.dumps(rows, indent=2))
    conn.close()

if __name__ == '__main__':
    check_errors()
