import requests
import json

payload = {
    "title": "Final Migration Test",
    "inputs": {
        "prompt": "A triumphant electronic track celebration.",
        "instrumental": True
    }
}

try:
    r = requests.post("http://localhost:8788/api/generations", json=payload)
    print(f"Status: {r.status_code}")
    print(f"Response: {r.text}")
except Exception as e:
    print(f"Error: {e}")
