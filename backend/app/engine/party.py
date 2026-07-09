from __future__ import annotations

import secrets
import threading
from typing import Any, Dict

from fastapi import HTTPException

PARTY_STATE: Dict[str, Any] = {"code": None, "queue": []}
PARTY_LOCK = threading.Lock()
PARTY_SEQ = 0


def generate_party_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(secrets.choice(alphabet) for _ in range(6))


def add_party_item(track: Dict[str, Any]) -> Dict[str, Any]:
    global PARTY_SEQ
    with PARTY_LOCK:
        PARTY_SEQ += 1
        item = {"id": str(PARTY_SEQ), "track": track}
        PARTY_STATE["queue"].append(item)
        return item


def require_party_code(code: str) -> None:
    active = PARTY_STATE.get("code")
    if not active or code.strip().upper() != active:
        raise HTTPException(status_code=403, detail="Invalid party code")


def start_party() -> str:
    global PARTY_SEQ
    code = generate_party_code()
    with PARTY_LOCK:
        PARTY_STATE["code"] = code
        PARTY_STATE["queue"] = []
        PARTY_SEQ = 0
    return code


def stop_party() -> None:
    with PARTY_LOCK:
        PARTY_STATE["code"] = None
        PARTY_STATE["queue"] = []


def party_queue_snapshot() -> list[Dict[str, Any]]:
    with PARTY_LOCK:
        return list(PARTY_STATE.get("queue", []))
