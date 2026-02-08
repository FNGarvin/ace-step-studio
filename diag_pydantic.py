from backend.app.schemas.generation import GenerationCreate
import json

payload = {
    "title": "Final Migration Test",
    "inputs": {
        "prompt": "A triumphant electronic track celebration.",
        "instrumental": True
    }
}

try:
    obj = GenerationCreate(**payload)
    print("Success!")
    print(obj.model_dump_json())
except Exception as e:
    print(f"Error: {e}")
