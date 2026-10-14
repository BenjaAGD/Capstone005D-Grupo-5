import os
import json
import requests
from dotenv import load_dotenv

load_dotenv()

NVIDIA_API_KEY = os.getenv("NVIDIA_API_KEY")
MODELO = os.getenv("NVIDIA_CHAT_MODEL", "nvidia/nemotron-3-super-120b-a12b")

print("=" * 60)
print("MODELO:", MODELO)
print("KEY:", NVIDIA_API_KEY[:15] + "..." if NVIDIA_API_KEY else "FALTA")
print("=" * 60)

r = requests.post(
    "https://integrate.api.nvidia.com/v1/chat/completions",
    headers={
        "Authorization": f"Bearer {NVIDIA_API_KEY}",
        "Content-Type": "application/json",
    },
    json={
        "model": MODELO,
        "messages": [{"role": "user", "content": "Responde solo: ok"}],
        "max_tokens": 50,
    },
    timeout=60,
)

print("STATUS:", r.status_code)
print("=" * 60)
print("RESPUESTA CRUDA:")
print(json.dumps(r.json(), indent=2, ensure_ascii=False))