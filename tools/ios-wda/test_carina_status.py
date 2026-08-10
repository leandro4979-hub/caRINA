from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import Any

import requests


CARINA_BASE_URL = "http://127.0.0.1:51001"
STATUS_ENDPOINT_CANDIDATES = (
    "/system/status",
    "/status",
)


@dataclass(frozen=True)
class StatusResult:
    iteration: int
    endpoint: str
    status_code: int
    payload: dict[str, Any]


def request_status(
    session: requests.Session,
    iteration: int,
) -> StatusResult:
    failures: list[str] = []

    for endpoint in STATUS_ENDPOINT_CANDIDATES:
        url = f"{CARINA_BASE_URL}{endpoint}"

        try:
            response = session.get(url, timeout=5)
        except requests.RequestException as exc:
            failures.append(f"{endpoint}: {type(exc).__name__}: {exc}")
            continue

        if not response.ok:
            failures.append(f"{endpoint}: HTTP {response.status_code}")
            continue

        try:
            payload = response.json()
        except ValueError:
            failures.append(f"{endpoint}: response was not valid JSON")
            continue

        return StatusResult(
            iteration=iteration,
            endpoint=endpoint,
            status_code=response.status_code,
            payload=payload,
        )

    raise AssertionError(
        "CARINA status could not be obtained. Attempts:\n" + "\n".join(failures)
    )


def payload_looks_healthy(payload: dict[str, Any]) -> bool:
    healthy_values = {
        "ok",
        "ready",
        "healthy",
        "online",
        "running",
        "success",
    }

    for key in ("status", "state", "health", "result"):
        value = payload.get(key)
        if isinstance(value, str) and value.strip().lower() in healthy_values:
            return True

    if payload.get("ok") is True:
        return True

    if payload.get("ready") is True:
        return True

    return False


def test_carina_status_five_consecutive_runs() -> None:
    results: list[StatusResult] = []

    with requests.Session() as session:
        for iteration in range(1, 6):
            result = request_status(
                session=session,
                iteration=iteration,
            )

            assert payload_looks_healthy(result.payload), (
                f"CARINA status iteration {iteration} returned an unhealthy payload:\n"
                f"{json.dumps(result.payload, indent=2)}"
            )

            results.append(result)

            print(
                f"\n[{iteration}/5] PASS "
                f"{result.endpoint} "
                f"{json.dumps(result.payload, sort_keys=True)}"
            )

            if iteration < 5:
                time.sleep(1.0)

    assert len(results) == 5
