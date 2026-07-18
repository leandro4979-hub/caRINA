#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import logging
import os
import plistlib
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any, Mapping, Sequence


LOGGER = logging.getLogger("CarinaDeploymentGuardian")
BUNDLE_IDENTIFIER = "com.leandrofajardo.carina"
DEFAULT_DEVICE_NAME = "17promax"
REFRESH_BEFORE_SECONDS = 48 * 60 * 60
MAX_INSTALL_AGE_SECONDS = 4 * 24 * 60 * 60
MAX_LOG_CHARACTERS = 8_000


def iso8601(value: dt.datetime | None = None) -> str:
    current = value or dt.datetime.now(dt.timezone.utc)
    return current.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def parse_timestamp(value: object) -> dt.datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(dt.timezone.utc)
    except ValueError:
        return None


def mask_identifier(value: str) -> str:
    return f"…{value[-4:]}" if len(value) >= 4 else "unavailable"


def atomic_write_json(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(path)


def run_command(
    command: Sequence[str],
    *,
    environment: Mapping[str, str],
    timeout: int,
) -> subprocess.CompletedProcess[str]:
    LOGGER.info("running %s", command[0])
    return subprocess.run(
        list(command),
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
        env=dict(environment),
    )


def profile_expiration(app_path: Path, environment: Mapping[str, str]) -> dt.datetime | None:
    profile = app_path / "embedded.mobileprovision"
    if not profile.is_file():
        return None
    completed = subprocess.run(
        ["/usr/bin/security", "cms", "-D", "-i", str(profile)],
        capture_output=True,
        timeout=20,
        check=False,
        env=dict(environment),
    )
    if completed.returncode != 0:
        return None
    try:
        payload = plistlib.loads(completed.stdout)
    except (plistlib.InvalidFileException, ValueError):
        return None
    expiration = payload.get("ExpirationDate") if isinstance(payload, Mapping) else None
    if not isinstance(expiration, dt.datetime):
        return None
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=dt.timezone.utc)
    return expiration.astimezone(dt.timezone.utc)


def deployment_reason(
    *,
    force: bool,
    installed: bool,
    app_exists: bool,
    revision: str,
    deployed_revision: str,
    profile_expires: dt.datetime | None,
    last_success: dt.datetime | None,
    now: dt.datetime,
) -> str | None:
    if force:
        return "forced"
    if not installed:
        return "app-not-installed"
    if not app_exists:
        return "local-build-missing"
    if deployed_revision and revision and deployed_revision != revision:
        return "ios-source-changed"
    if profile_expires is None:
        return "profile-expiration-unknown"
    if (profile_expires - now).total_seconds() <= REFRESH_BEFORE_SECONDS:
        return "profile-near-expiration"
    if last_success and (now - last_success).total_seconds() >= MAX_INSTALL_AGE_SECONDS:
        return "scheduled-refresh"
    return None


class DeploymentGuardian:
    def __init__(self) -> None:
        runtime = Path(
            os.environ.get(
                "CARINA_DEPLOYMENT_ROOT",
                Path.home() / "Library/Application Support/CARINA/deployment",
            )
        ).expanduser().resolve()
        self.runtime = runtime
        self.project_root = Path(os.environ.get("CARINA_DEPLOYMENT_PROJECT", runtime / "project")).resolve()
        self.derived_data = runtime / "DerivedData"
        self.app_path = self.derived_data / "Build/Products/Debug-iphoneos/Carina.app"
        self.state_path = runtime / "state.json"
        self.lock_path = runtime / "guardian.lock"
        self.revision = os.environ.get("CARINA_IOS_REVISION", "snapshot").strip() or "snapshot"
        self.device_name = os.environ.get("CARINA_DEVICE_NAME", DEFAULT_DEVICE_NAME).strip()
        self.developer_dir = Path(
            os.environ.get(
                "DEVELOPER_DIR", Path.home() / "Downloads/Xcode-beta.app/Contents/Developer"
            )
        ).expanduser().resolve()
        self.environment = os.environ.copy()
        self.environment["DEVELOPER_DIR"] = str(self.developer_dir)

    def _load_state(self) -> dict[str, Any]:
        try:
            decoded = json.loads(self.state_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, PermissionError, UnicodeDecodeError, json.JSONDecodeError):
            return {}
        return dict(decoded) if isinstance(decoded, Mapping) else {}

    def _devicectl_json(self, arguments: Sequence[str], timeout: int = 60) -> dict[str, Any]:
        self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        with tempfile.NamedTemporaryFile(dir=self.runtime, suffix=".json", delete=False) as handle:
            output_path = Path(handle.name)
        try:
            completed = run_command(
                ["/usr/bin/xcrun", "devicectl", *arguments, "--json-output", str(output_path)],
                environment=self.environment,
                timeout=timeout,
            )
            if completed.returncode != 0:
                detail = (completed.stderr or completed.stdout).strip()[-MAX_LOG_CHARACTERS:]
                raise RuntimeError(detail or "devicectl failed")
            decoded = json.loads(output_path.read_text(encoding="utf-8"))
            if not isinstance(decoded, Mapping):
                raise RuntimeError("devicectl returned an invalid object")
            return dict(decoded)
        finally:
            output_path.unlink(missing_ok=True)

    def device(self) -> dict[str, Any]:
        payload = self._devicectl_json(["list", "devices"])
        result = payload.get("result", {})
        devices = result.get("devices", []) if isinstance(result, Mapping) else []
        for candidate in devices:
            if not isinstance(candidate, Mapping):
                continue
            properties = candidate.get("deviceProperties", {})
            connection = candidate.get("connectionProperties", {})
            name = properties.get("name", "") if isinstance(properties, Mapping) else ""
            if str(name).casefold() != self.device_name.casefold():
                continue
            if not isinstance(connection, Mapping) or connection.get("pairingState") != "paired":
                continue
            identifier = candidate.get("identifier")
            if not isinstance(identifier, str) or not identifier:
                continue
            return {
                "identifier": identifier,
                "masked_identifier": mask_identifier(identifier),
                "name": name,
                "model": candidate.get("hardwareProperties", {}).get("marketingName", "iPhone"),
                "os_version": properties.get("osVersionNumber"),
                "developer_mode": properties.get("developerModeStatus"),
                "transport": connection.get("transportType"),
                "tunnel_state": connection.get("tunnelState"),
            }
        raise RuntimeError(f"paired device {self.device_name!r} is unavailable")

    def is_installed(self, identifier: str) -> bool:
        payload = self._devicectl_json(
            ["device", "info", "apps", "--device", identifier, "--bundle-id", BUNDLE_IDENTIFIER]
        )
        result = payload.get("result", {})
        apps = result.get("apps", []) if isinstance(result, Mapping) else []
        return any(
            isinstance(app, Mapping) and app.get("bundleIdentifier") == BUNDLE_IDENTIFIER
            for app in apps
        )

    def build(self) -> None:
        project = self.project_root / "apps/ios/Carina.xcodeproj"
        if not project.is_dir():
            raise RuntimeError(f"deployment snapshot is missing {project}")
        completed = run_command(
            [
                "/usr/bin/xcodebuild",
                "-project",
                str(project),
                "-scheme",
                "Carina",
                "-configuration",
                "Debug",
                "-destination",
                "generic/platform=iOS",
                "-derivedDataPath",
                str(self.derived_data),
                "-allowProvisioningUpdates",
                "build",
            ],
            environment=self.environment,
            timeout=1_200,
        )
        if completed.returncode != 0:
            detail = (completed.stderr + "\n" + completed.stdout)[-MAX_LOG_CHARACTERS:]
            raise RuntimeError(f"xcodebuild failed\n{detail}")

    def install(self, identifier: str) -> None:
        if not self.app_path.is_dir():
            raise RuntimeError("signed CARINA app was not produced")
        self._devicectl_json(
            ["device", "install", "app", "--device", identifier, str(self.app_path)],
            timeout=180,
        )

    def launch(self, identifier: str) -> str:
        try:
            self._devicectl_json(
                ["device", "process", "launch", "--device", identifier, BUNDLE_IDENTIFIER],
                timeout=60,
            )
            return "launched"
        except RuntimeError as exc:
            LOGGER.warning("install succeeded but launch needs an unlocked phone: %s", exc)
            return "installed-phone-locked"

    def run(self, force: bool = False, dry_run: bool = False) -> dict[str, Any]:
        started = time.monotonic()
        now = dt.datetime.now(dt.timezone.utc)
        self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        with self.lock_path.open("a+", encoding="utf-8") as lock_handle:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            state = self._load_state()
            try:
                device = self.device()
                installed = self.is_installed(device["identifier"])
                expiration = profile_expiration(self.app_path, self.environment)
                last_success = parse_timestamp(state.get("last_success_at"))
                deployed_revision = str(state.get("deployed_revision", ""))
                reason = deployment_reason(
                    force=force,
                    installed=installed,
                    app_exists=self.app_path.is_dir(),
                    revision=self.revision,
                    deployed_revision=deployed_revision,
                    profile_expires=expiration,
                    last_success=last_success,
                    now=now,
                )
                adopted = not state and reason is None
                if adopted:
                    reason = None
                if reason and not dry_run:
                    self.build()
                    expiration = profile_expiration(self.app_path, self.environment)
                    self.install(device["identifier"])
                    launch_state = self.launch(device["identifier"])
                    outcome = "deployed"
                    last_success_at = iso8601()
                elif reason:
                    launch_state = "not-requested"
                    outcome = "deployment-required"
                    last_success_at = state.get("last_success_at")
                else:
                    launch_state = "not-requested"
                    outcome = "adopted-existing-install" if adopted else "fresh"
                    last_success_at = state.get("last_success_at") or iso8601()
                result = {
                    "success": True,
                    "outcome": outcome,
                    "reason": reason,
                    "checked_at": iso8601(),
                    "last_success_at": last_success_at,
                    "deployed_revision": self.revision if not reason or not dry_run else deployed_revision,
                    "profile_expires_at": iso8601(expiration) if expiration else None,
                    "profile_days_remaining": round((expiration - now).total_seconds() / 86400, 2) if expiration else None,
                    "app_installed": installed if not reason or dry_run else True,
                    "launch_state": launch_state,
                    "device": {key: value for key, value in device.items() if key != "identifier"},
                    "duration_ms": round((time.monotonic() - started) * 1000),
                }
            except (OSError, RuntimeError, subprocess.TimeoutExpired, BlockingIOError) as exc:
                result = {
                    "success": False,
                    "outcome": "failed",
                    "error": str(exc)[-MAX_LOG_CHARACTERS:],
                    "checked_at": iso8601(),
                    "last_success_at": state.get("last_success_at"),
                    "deployed_revision": state.get("deployed_revision"),
                    "duration_ms": round((time.monotonic() - started) * 1000),
                }
            atomic_write_json(self.state_path, result)
            return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Keep CARINA signed and installed on the paired iPhone")
    parser.add_argument("command", nargs="?", choices=("run", "status"), default="run")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    args = parse_args()
    guardian = DeploymentGuardian()
    if args.command == "status":
        result = guardian._load_state()
        if not result:
            result = {"success": False, "outcome": "never-run"}
    else:
        result = guardian.run(force=args.force, dry_run=args.dry_run)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("success") else 1


if __name__ == "__main__":
    raise SystemExit(main())
