#!/usr/bin/env python3
"""Build caRINA's local AgentOps dashboard."""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sqlite3
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping


DEFAULT_DOCUMENTS_DIR = Path.home() / "Documents"
DEFAULT_AGENTOPS_DIR = Path(os.environ.get("CARINA_AGENTOPS_DIR", DEFAULT_DOCUMENTS_DIR / "AgentOps"))
DEFAULT_CODEX_DIR = Path(os.environ.get("CARINA_CODEX_DIR", DEFAULT_DOCUMENTS_DIR / "Codex"))
DEFAULT_ARCHIVE_MANIFEST = (
    DEFAULT_CODEX_DIR / "_archive" / "2026-07-04-agentops-review" / "manifest.json"
)
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "dist" / "dashboard.html"
DEFAULT_FORGE_DB = Path.home() / "Library/Application Support/CARINA/forge/forge.db"
DEFAULT_GUARDIAN_STATE = (
    Path.home() / "Library/Application Support/CARINA/deployment/state.json"
)
DEFAULT_PROJECT_SNAPSHOT = os.environ.get("CARINA_PROJECT_SNAPSHOT", "").strip()
DOC_ORDER = (
    "agents.md",
    "projects.md",
    "services.md",
    "skills.md",
    "tokens.md",
    "schedule.md",
    "inbox.md",
)


@dataclass
class Listener:
    command: str
    pid: str
    port: str
    address: str


@dataclass
class CodexFolder:
    name: str
    path: Path
    date: str
    size_bytes: int
    files: int
    status: str
    reason: str


@dataclass
class ArchiveSummary:
    path: Path
    mode: str
    item_count: int
    archive_dir: str
    generated_at: str


@dataclass
class ProjectSnapshot:
    name: str
    path: str
    branch: str
    dirty_files: int
    commits_7d: int
    ahead: int
    behind: int
    last_commit_at: str
    last_commit: str


def run_git(path: Path, arguments: list[str], timeout: int = 5) -> str:
    try:
        completed = subprocess.run(
            ["git", "-C", str(path), *arguments],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return completed.stdout.strip() if completed.returncode == 0 else ""


def discover_repositories(root: Path, max_depth: int = 4, limit: int = 20) -> list[Path]:
    if not root.is_dir():
        return []
    ignored = {
        ".artifacts", ".codex", ".deriveddata", ".venv", "deriveddata",
        "library", "node_modules", "build", "dist", "vendor",
    }
    found: list[Path] = []
    root_depth = len(root.parts)
    for current, directories, _ in os.walk(root):
        current_path = Path(current)
        depth = len(current_path.parts) - root_depth
        directories[:] = [
            name for name in directories
            if name.casefold() not in ignored and not name.startswith(".")
        ]
        if (current_path / ".git").exists():
            found.append(current_path)
            directories[:] = []
            continue
        if depth >= max_depth:
            directories[:] = []
    found.sort(
        key=lambda path: (path / ".git").stat().st_mtime if (path / ".git").exists() else 0,
        reverse=True,
    )
    return found[:limit]


def collect_projects(root: Path = DEFAULT_DOCUMENTS_DIR) -> list[ProjectSnapshot]:
    projects: list[ProjectSnapshot] = []
    for path in discover_repositories(root):
        status = run_git(path, ["status", "--porcelain=v1", "--branch"])
        lines = status.splitlines()
        header = lines[0] if lines else ""
        branch, ahead, behind = parse_git_status_header(header)
        commits_text = run_git(path, ["rev-list", "--count", "--since=7.days", "HEAD"])
        last = run_git(path, ["log", "-1", "--format=%cI|%h %s"])
        last_at, separator, last_summary = last.partition("|")
        projects.append(
            ProjectSnapshot(
                name=path.name,
                path=str(path),
                branch=branch,
                dirty_files=max(0, len(lines) - 1),
                commits_7d=int(commits_text) if commits_text.isdigit() else 0,
                ahead=ahead,
                behind=behind,
                last_commit_at=last_at if separator else "",
                last_commit=last_summary if separator else last,
            )
        )
    return projects


def write_project_snapshot(path: Path, projects: list[ProjectSnapshot]) -> None:
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "projects": [project.__dict__ for project in projects],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def read_project_snapshot(path: Path) -> tuple[list[ProjectSnapshot], str]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return [], "unavailable"
    raw_projects = payload.get("projects", []) if isinstance(payload, Mapping) else []
    projects: list[ProjectSnapshot] = []
    for item in raw_projects:
        if not isinstance(item, Mapping):
            continue
        try:
            projects.append(ProjectSnapshot(**{field: item[field] for field in ProjectSnapshot.__dataclass_fields__}))
        except (KeyError, TypeError):
            continue
    generated_at = str(payload.get("generated_at", "unknown")) if isinstance(payload, Mapping) else "unknown"
    return projects, generated_at


def read_json_object(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return {}
    return dict(payload) if isinstance(payload, Mapping) else {}


def collect_forge_metrics(path: Path = DEFAULT_FORGE_DB) -> dict[str, Any]:
    if not path.is_file():
        return {"total": 0, "ready": 0, "quarantined": 0, "latest_ingest": None, "operations": []}
    try:
        connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=3)
        connection.row_factory = sqlite3.Row
        counts = connection.execute(
            """
            SELECT COUNT(*) total,
                   SUM(CASE WHEN trust_state='ready' THEN 1 ELSE 0 END) ready,
                   SUM(CASE WHEN trust_state='quarantined' THEN 1 ELSE 0 END) quarantined,
                   MAX(ingested_at) latest_ingest
            FROM documents
            """
        ).fetchone()
        operations = connection.execute(
            """
            SELECT component, success, duration_ms, item_count, detail, created_at
            FROM operations ORDER BY id DESC LIMIT 12
            """
        ).fetchall()
    except (OSError, sqlite3.Error):
        return {"total": 0, "ready": 0, "quarantined": 0, "latest_ingest": None, "operations": []}
    finally:
        if "connection" in locals():
            connection.close()
    return {
        "total": int(counts["total"] or 0),
        "ready": int(counts["ready"] or 0),
        "quarantined": int(counts["quarantined"] or 0),
        "latest_ingest": counts["latest_ingest"],
        "operations": [dict(row) for row in operations],
    }


def read_docs(agentops_dir: Path) -> dict[str, str]:
    docs: dict[str, str] = {}
    for name in DOC_ORDER:
        path = agentops_dir / name
        docs[name] = path.read_text(encoding="utf-8") if path.exists() else ""
    return docs


def collect_listeners() -> list[Listener]:
    try:
        result = subprocess.run(
            ["lsof", "-nP", "-iTCP", "-sTCP:LISTEN"],
            check=False,
            capture_output=True,
            text=True,
            timeout=8,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []

    return parse_lsof_listeners(result.stdout)


def parse_lsof_listeners(output: str) -> list[Listener]:
    listeners: list[Listener] = []
    for line in output.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 9:
            continue
        name = " ".join(parts[8:])
        match = re.search(r":(\d+)\s+\(LISTEN\)$", name)
        if not match:
            continue
        listeners.append(
            Listener(command=parts[0], pid=parts[1], port=match.group(1), address=name)
        )
    return listeners


def parse_git_status_header(header: str) -> tuple[str, int, int]:
    no_commit_match = re.match(r"## No commits yet on (.+)$", header)
    if no_commit_match:
        return no_commit_match.group(1).strip(), 0, 0
    branch_match = re.match(r"##\s+(.+?)(?:\.\.\.|$)", header)
    branch = branch_match.group(1).strip() if branch_match else "detached"
    ahead_match = re.search(r"ahead (\d+)", header)
    behind_match = re.search(r"behind (\d+)", header)
    return (
        branch,
        int(ahead_match.group(1)) if ahead_match else 0,
        int(behind_match.group(1)) if behind_match else 0,
    )


def collect_codex_folders(codex_dir: Path) -> list[CodexFolder]:
    if not codex_dir.exists():
        return []

    folders: list[CodexFolder] = []
    for date_dir in sorted(codex_dir.iterdir()):
        if not date_dir.is_dir() or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date_dir.name):
            continue
        for project_dir in sorted(path for path in date_dir.iterdir() if path.is_dir()):
            size_bytes, files = folder_stats(project_dir)
            status, reason = classify_codex_folder(project_dir, size_bytes, files)
            folders.append(
                CodexFolder(
                    name=project_dir.name,
                    path=project_dir,
                    date=date_dir.name,
                    size_bytes=size_bytes,
                    files=files,
                    status=status,
                    reason=reason,
                )
            )
    return folders


def read_archive_summary(path: Path = DEFAULT_ARCHIVE_MANIFEST) -> ArchiveSummary | None:
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return ArchiveSummary(
        path=path,
        mode=str(data.get("mode", "unknown")),
        item_count=len(data.get("items", [])),
        archive_dir=str(data.get("archive_dir", "")),
        generated_at=str(data.get("generated_at", "")),
    )


def folder_stats(path: Path) -> tuple[int, int]:
    size = 0
    files = 0
    for item in path.rglob("*"):
        try:
            if item.is_file():
                files += 1
                size += item.stat().st_size
        except OSError:
            continue
    return size, files


def classify_codex_folder(path: Path, size_bytes: int, files: int) -> tuple[str, str]:
    markers = {item.name for item in path.iterdir()} if path.exists() else set()
    if ".git" in markers or "package.json" in markers or "pyproject.toml" in markers:
        return "keep", "Looks like a repository or runnable project."
    if path.name in {"i", "x"} and size_bytes < 1_000_000:
        return "delete candidate", "Tiny scratch folder with a placeholder name."
    if files == 0:
        return "delete candidate", "No files found."
    if "outputs" in markers or "work" in markers:
        return "archive", "Codex session folder with work/output history."
    if size_bytes < 250_000:
        return "archive", "Small session folder; likely historical context."
    return "review", "Contains enough material to inspect before deciding."


def human_size(size_bytes: int) -> str:
    units = ("B", "KB", "MB", "GB")
    value = float(size_bytes)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024


def parse_markdown_tables(markdown: str) -> list[list[list[str]]]:
    tables: list[list[list[str]]] = []
    current: list[list[str]] = []
    for line in markdown.splitlines():
        stripped = line.strip()
        if stripped.startswith("|") and stripped.endswith("|"):
            cells = [cell.strip().strip("`") for cell in stripped.strip("|").split("|")]
            if all(set(cell) <= {"-", ":", " "} for cell in cells):
                continue
            current.append(cells)
        elif current:
            tables.append(current)
            current = []
    if current:
        tables.append(current)
    return tables


def parse_bullets(markdown: str) -> list[str]:
    bullets: list[str] = []
    for line in markdown.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            bullets.append(stripped[2:])
    return bullets


def render_table(table: list[list[str]]) -> str:
    if not table:
        return ""
    header, *rows = table
    head_html = "".join(f"<th>{inline(cell)}</th>" for cell in header)
    body_rows = []
    for row in rows:
        body_rows.append("<tr>" + "".join(f"<td>{inline(cell)}</td>" for cell in row) + "</tr>")
    return f"<table><thead><tr>{head_html}</tr></thead><tbody>{''.join(body_rows)}</tbody></table>"


def render_tables(tables: list[list[list[str]]], empty_message: str) -> str:
    if not tables:
        return f"<p>{inline(empty_message)}</p>"
    return "".join(render_table(table) for table in tables)


def render_codex_folder_table(folders: list[CodexFolder]) -> str:
    rows = []
    for folder in folders:
        rows.append(
            "<tr>"
            f"<td>{inline(folder.date)}</td>"
            f"<td><code>{inline(folder.name)}</code></td>"
            f"<td><span class='pill {css_class(folder.status)}'>{inline(folder.status)}</span></td>"
            f"<td>{inline(human_size(folder.size_bytes))}</td>"
            f"<td>{folder.files}</td>"
            f"<td>{inline(folder.reason)}</td>"
            "</tr>"
        )
    if not rows:
        rows.append("<tr><td colspan='6'>No dated Codex folders found.</td></tr>")
    return (
        "<table><thead><tr>"
        "<th>Date</th><th>Folder</th><th>Suggestion</th><th>Size</th><th>Files</th><th>Reason</th>"
        "</tr></thead><tbody>"
        + "".join(rows)
        + "</tbody></table>"
    )


def render_archive_summary(summary: ArchiveSummary | None) -> str:
    if summary is None:
        return "<p>No archive manifest found yet.</p>"
    return f"""
      <div class="archive-summary">
        <p><strong>{summary.item_count}</strong> folders archived in <code>{inline(summary.mode)}</code> mode.</p>
        <p>Generated: <code>{inline(summary.generated_at)}</code></p>
        <p>Archive: <code>{inline(summary.archive_dir)}</code></p>
        <p>Manifest: <code>{inline(str(summary.path))}</code></p>
      </div>
    """


def folder_counts(folders: list[CodexFolder]) -> dict[str, int]:
    counts = {"keep": 0, "archive": 0, "delete candidate": 0, "review": 0}
    for folder in folders:
        counts[folder.status] = counts.get(folder.status, 0) + 1
    return counts


def css_class(status: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", status.lower()).strip("-")


def inline(text: str) -> str:
    escaped = html.escape(text)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    return escaped


def status_for_port(port: str, listeners: list[Listener]) -> str:
    return "online" if any(listener.port == port for listener in listeners) else "check"


def render_project_table(projects: list[ProjectSnapshot]) -> str:
    rows = []
    for project in projects:
        state = "clean" if project.dirty_files == 0 else f"{project.dirty_files} changed"
        sync = "synced"
        if project.ahead or project.behind:
            sync = f"+{project.ahead} / -{project.behind}"
        rows.append(
            "<tr>"
            f"<td><strong>{inline(project.name)}</strong><br><small>{inline(project.path)}</small></td>"
            f"<td><code>{inline(project.branch)}</code></td>"
            f"<td><span class='pill {'keep' if project.dirty_files == 0 else 'archive'}'>{inline(state)}</span></td>"
            f"<td>{project.commits_7d}</td>"
            f"<td>{inline(sync)}</td>"
            f"<td>{inline(project.last_commit or 'No commit')}</td>"
            "</tr>"
        )
    if not rows:
        rows.append("<tr><td colspan='6'>No Git project snapshot is available.</td></tr>")
    return (
        "<table><thead><tr><th>Project</th><th>Branch</th><th>Worktree</th>"
        "<th>Commits 7d</th><th>Ahead / Behind</th><th>Latest</th></tr></thead><tbody>"
        + "".join(rows)
        + "</tbody></table>"
    )


def render_operations(operations: list[Mapping[str, Any]]) -> str:
    rows = []
    for operation in operations:
        success = bool(operation.get("success"))
        rows.append(
            "<tr>"
            f"<td>{inline(str(operation.get('created_at', '')))}</td>"
            f"<td>{inline(str(operation.get('component', 'unknown')))}</td>"
            f"<td><span class='pill {'keep' if success else 'delete-candidate'}'>{'passed' if success else 'failed'}</span></td>"
            f"<td>{int(operation.get('duration_ms', 0))} ms</td>"
            f"<td>{int(operation.get('item_count', 0))}</td>"
            "</tr>"
        )
    if not rows:
        rows.append("<tr><td colspan='5'>No recorded operations.</td></tr>")
    return (
        "<table><thead><tr><th>Time</th><th>Operation</th><th>Result</th>"
        "<th>Duration</th><th>Items</th></tr></thead><tbody>"
        + "".join(rows)
        + "</tbody></table>"
    )


def planning_priorities(
    projects: list[ProjectSnapshot],
    forge: Mapping[str, Any],
    guardian: Mapping[str, Any],
    services_online: int,
    services_total: int,
) -> list[str]:
    priorities: list[str] = []
    if not guardian.get("success"):
        priorities.append("Restore the deployment guardian before expanding device features.")
    days = guardian.get("profile_days_remaining")
    if isinstance(days, (int, float)) and days <= 2:
        priorities.append(f"Refresh CARINA signing now; only {days:.1f} days remain.")
    dirty = sum(1 for project in projects if project.dirty_files)
    if dirty:
        priorities.append(f"Close or commit work in {dirty} dirty repositories before a broad integration move.")
    behind = sum(1 for project in projects if project.behind)
    if behind:
        priorities.append(f"Review {behind} repositories that are behind their tracked remote.")
    quarantined = int(forge.get("quarantined", 0) or 0)
    if quarantined:
        priorities.append(f"Review {quarantined} quarantined Forge documents without exposing their contents.")
    if services_online < services_total:
        priorities.append(f"Recover {services_total - services_online} offline core services before load testing.")
    if not priorities:
        priorities.append("Core operations are stable; plan the next CARINA capability around the highest-activity project.")
    return priorities[:5]


def build_html(
    docs: dict[str, str],
    listeners: list[Listener],
    folders: list[CodexFolder],
    archive_summary: ArchiveSummary | None,
    agentops_dir: Path,
    projects: list[ProjectSnapshot] | None = None,
    project_snapshot_generated: str = "live",
    forge: Mapping[str, Any] | None = None,
    guardian: Mapping[str, Any] | None = None,
) -> str:
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    agent_tables = parse_markdown_tables(docs.get("agents.md", ""))
    project_tables = parse_markdown_tables(docs.get("projects.md", ""))
    service_tables = parse_markdown_tables(docs.get("services.md", ""))
    skill_tables = parse_markdown_tables(docs.get("skills.md", ""))
    token_tables = parse_markdown_tables(docs.get("tokens.md", ""))
    inbox_items = parse_bullets(docs.get("inbox.md", ""))
    counts = folder_counts(folders)
    projects = projects or []
    forge = forge or {}
    guardian = guardian or {}

    cards = [
        ("CARINA HTTP", "51001", status_for_port("51001", listeners)),
        ("CARINA WebSocket", "51002", status_for_port("51002", listeners)),
        ("OpenClaw Gateway", "18789", status_for_port("18789", listeners)),
        ("Ollama", "11434", status_for_port("11434", listeners)),
        ("Device Control", "4723", status_for_port("4723", listeners)),
        ("Dashboard", "51003", status_for_port("51003", listeners)),
    ]
    online_count = sum(1 for _, _, state in cards if state == "online")
    card_html = "\n".join(
        f"""
        <article class="status-card {state}">
          <div>
            <p>{html.escape(title)}</p>
            <strong>{html.escape(port)}</strong>
          </div>
          <span>{state}</span>
        </article>
        """
        for title, port, state in cards
    )

    listener_rows = "\n".join(
        f"<tr><td>{html.escape(item.command)}</td><td>{html.escape(item.pid)}</td><td>{html.escape(item.port)}</td><td><code>{html.escape(item.address)}</code></td></tr>"
        for item in listeners
    )

    inbox_html = "\n".join(f"<li>{inline(item)}</li>" for item in inbox_items)
    folder_summary = "\n".join(
        f"<article class='metric'><strong>{count}</strong><span>{inline(label)}</span></article>"
        for label, count in counts.items()
    )
    total_commits = sum(project.commits_7d for project in projects)
    dirty_projects = sum(1 for project in projects if project.dirty_files)
    profile_days = guardian.get("profile_days_remaining")
    profile_display = f"{profile_days:.1f}d" if isinstance(profile_days, (int, float)) else "—"
    operations = forge.get("operations", [])
    operations = operations if isinstance(operations, list) else []
    priorities = planning_priorities(projects, forge, guardian, online_count, len(cards))
    priority_html = "".join(f"<li>{inline(item)}</li>" for item in priorities)
    top_metrics = [
        (str(len(projects)), "Git projects"),
        (str(total_commits), "Commits · 7 days"),
        (str(dirty_projects), "Dirty worktrees"),
        (str(forge.get("ready", 0)), "Forge sources"),
        (profile_display, "Signing runway"),
        (f"{online_count}/{len(cards)}", "Services online"),
    ]
    top_metric_html = "".join(
        f"<article class='metric'><strong>{inline(value)}</strong><span>{inline(label)}</span></article>"
        for value, label in top_metrics
    )

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="60">
  <title>caRINA AgentOps</title>
  <style>
    :root {{
      color-scheme: dark;
      --ink: #f3f6ff;
      --muted: #929cb8;
      --line: rgba(155, 168, 220, .16);
      --paper: #070a17;
      --panel: rgba(17, 22, 46, .76);
      --panel-strong: rgba(21, 28, 59, .94);
      --green: #45e6a6;
      --amber: #ffb764;
      --blue: #62c8ff;
      --violet: #997dff;
      --rose: #ff6b9d;
      --shadow: 0 24px 70px rgba(0, 0, 0, .3);
    }}
    * {{ box-sizing: border-box; }}
    html {{ scroll-behavior: smooth; }}
    body {{
      margin: 0;
      min-height: 100vh;
      background:
        radial-gradient(circle at 88% -8%, rgba(104, 72, 255, .28), transparent 36rem),
        radial-gradient(circle at -8% 70%, rgba(25, 192, 225, .14), transparent 32rem),
        var(--paper);
      color: var(--ink);
      font: 15px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif;
      -webkit-font-smoothing: antialiased;
    }}
    header {{
      position: relative;
      overflow: hidden;
      padding: 48px clamp(22px, 6vw, 84px) 38px;
      background: linear-gradient(145deg, rgba(19, 25, 57, .92), rgba(8, 11, 28, .7));
      border-bottom: 1px solid var(--line);
      backdrop-filter: blur(28px) saturate(135%);
    }}
    header::after {{
      content: "";
      position: absolute;
      width: 420px;
      height: 420px;
      right: -90px;
      top: -260px;
      border-radius: 50%;
      background: conic-gradient(from 30deg, var(--blue), var(--violet), transparent, var(--blue));
      filter: blur(42px);
      opacity: .28;
      pointer-events: none;
    }}
    .eyebrow {{
      margin: 0 0 10px;
      color: var(--blue);
      font-size: 12px;
      font-weight: 750;
      letter-spacing: .22em;
      text-transform: uppercase;
    }}
    header h1 {{
      margin: 0;
      font-size: clamp(36px, 6vw, 70px);
      line-height: 1;
      letter-spacing: -.045em;
      background: linear-gradient(110deg, #fff 20%, #9ce9ff 55%, #b7a6ff 90%);
      -webkit-background-clip: text;
      color: transparent;
    }}
    header p {{ margin: 14px 0 0; color: var(--muted); max-width: 760px; }}
    .hero-meta {{
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 24px;
    }}
    .hero-meta span {{
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      border: 1px solid var(--line);
      border-radius: 999px;
      background: rgba(255, 255, 255, .045);
      color: #c8d0e8;
      font-size: 12px;
    }}
    .hero-meta .live::before {{
      content: "";
      width: 7px;
      height: 7px;
      border-radius: 50%;
      background: var(--green);
      box-shadow: 0 0 14px var(--green);
    }}
    main {{
      width: min(1320px, calc(100% - 32px));
      margin: 26px auto 70px;
      display: grid;
      gap: 20px;
    }}
    section {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 24px;
      padding: clamp(18px, 2.5vw, 28px);
      box-shadow: var(--shadow);
      backdrop-filter: blur(22px) saturate(125%);
    }}
    h2 {{ margin: 0 0 18px; font-size: 19px; letter-spacing: -.015em; }}
    h2::before {{
      content: "";
      display: inline-block;
      width: 8px;
      height: 8px;
      margin: 0 10px 2px 0;
      border-radius: 50%;
      background: var(--violet);
      box-shadow: 0 0 14px rgba(153, 125, 255, .7);
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
      gap: 14px;
    }}
    .status-card {{
      position: relative;
      overflow: hidden;
      min-height: 122px;
      border: 1px solid var(--line);
      border-radius: 19px;
      padding: 18px;
      display: flex;
      justify-content: space-between;
      gap: 12px;
      background: linear-gradient(145deg, rgba(255, 255, 255, .065), rgba(255, 255, 255, .02));
      transition: transform .18s ease, border-color .18s ease;
    }}
    .status-card:hover {{ transform: translateY(-2px); border-color: rgba(153, 125, 255, .38); }}
    .status-card::after {{
      content: "";
      position: absolute;
      inset: auto -30px -45px auto;
      width: 110px;
      height: 110px;
      border-radius: 50%;
      background: var(--amber);
      filter: blur(38px);
      opacity: .12;
    }}
    .status-card.online::after {{ background: var(--green); opacity: .16; }}
    .status-card p {{ margin: 0 0 12px; color: var(--muted); font-size: 13px; }}
    .status-card strong {{ display: block; font-size: 23px; letter-spacing: -.03em; }}
    .status-card span {{
      height: 26px;
      padding: 4px 9px;
      border-radius: 999px;
      background: rgba(255, 183, 100, .1);
      color: var(--amber);
      font-size: 10px;
      font-weight: 750;
      letter-spacing: .08em;
      text-transform: uppercase;
    }}
    .status-card.online span {{ background: rgba(69, 230, 166, .1); color: var(--green); }}
    .status-card.online span::before {{ content: "● "; }}
    table {{
      width: 100%;
      border-collapse: collapse;
      overflow-wrap: anywhere;
    }}
    th, td {{
      text-align: left;
      vertical-align: top;
      border-bottom: 1px solid rgba(155, 168, 220, .1);
      padding: 12px 10px;
    }}
    th {{ color: var(--muted); font-size: 11px; letter-spacing: .08em; text-transform: uppercase; }}
    tbody tr {{ transition: background .15s ease; }}
    tbody tr:hover {{ background: rgba(255, 255, 255, .025); }}
    code {{
      font-family: "SFMono-Regular", Consolas, monospace;
      font-size: 0.92em;
      background: rgba(98, 200, 255, .08);
      color: #a8e4ff;
      padding: 2px 6px;
      border-radius: 6px;
    }}
    ul {{ margin: 0; padding-left: 20px; }}
    li + li {{ margin-top: 6px; }}
    .two-col {{
      display: grid;
      grid-template-columns: minmax(0, 1.1fr) minmax(300px, 0.9fr);
      gap: 18px;
    }}
    .notice {{
      border-color: rgba(255, 107, 157, .22);
      background: linear-gradient(145deg, rgba(255, 107, 157, .08), var(--panel));
    }}
    .archive-summary {{
      margin: 12px 0 16px;
      padding: 14px;
      border: 1px solid var(--line);
      border-radius: 15px;
      background: rgba(98, 200, 255, .045);
    }}
    .archive-summary p {{ margin: 4px 0; }}
    .metric {{
      border: 1px solid var(--line);
      border-radius: 16px;
      padding: 15px;
      background: rgba(255, 255, 255, .035);
    }}
    .metric strong {{
      display: block;
      font-size: 28px;
      line-height: 1;
    }}
    .metric span {{
      color: var(--muted);
      text-transform: uppercase;
      font-size: 12px;
    }}
    small {{ color: var(--muted); font-size: 11px; }}
    .source-note {{ color: var(--muted); font-size: 12px; margin: -8px 0 16px; }}
    .pill {{
      display: inline-block;
      min-width: 70px;
      padding: 2px 8px;
      border-radius: 999px;
      font-size: 12px;
      text-align: center;
      background: rgba(98, 200, 255, .1);
      color: var(--blue);
    }}
    .pill.keep {{ background: rgba(69, 230, 166, .1); color: var(--green); }}
    .pill.archive {{ background: rgba(255, 183, 100, .1); color: var(--amber); }}
    .pill.delete-candidate {{ background: rgba(255, 107, 157, .1); color: var(--rose); }}
    @media (max-width: 820px) {{
      .two-col {{ grid-template-columns: 1fr; }}
      th, td {{ padding: 8px 6px; }}
      header {{ padding-top: 34px; }}
    }}
  </style>
</head>
<body>
  <header>
    <p class="eyebrow">MagnoliaOS · Autonomous systems console</p>
    <h1>CARINA Command Core</h1>
    <p>One truthful view of projects, delivery health, local models, and live Mac operations.</p>
    <div class="hero-meta">
      <span class="live">{online_count} of {len(cards)} core services online</span>
      <span>OpenClaw + Ollama preferred</span>
      <span>Generated {html.escape(now)}</span>
      <span>Project snapshot {html.escape(project_snapshot_generated)}</span>
    </div>
  </header>
  <main>
    <section>
      <h2>Operating Pulse</h2>
      <div class="grid">{top_metric_html}</div>
    </section>
    <section>
      <h2>Live Services</h2>
      <div class="grid">{card_html}</div>
    </section>
    <section>
      <h2>Project Performance</h2>
      <p class="source-note">Source: local Git metadata · snapshot {html.escape(project_snapshot_generated)}</p>
      {render_project_table(projects)}
    </section>
    <section class="two-col">
      <div>
        <h2>Next Big Move</h2>
        <ol>{priority_html}</ol>
      </div>
      <div>
        <h2>Device Delivery</h2>
        <p><strong>{inline(str(guardian.get('outcome', 'unavailable')))}</strong></p>
        <p>iPhone: {inline(str(guardian.get('device', {}).get('name', 'unavailable')) if isinstance(guardian.get('device'), Mapping) else 'unavailable')}</p>
        <p>Last check: <code>{inline(str(guardian.get('checked_at', 'unavailable')))}</code></p>
        <p>Profile expires: <code>{inline(str(guardian.get('profile_expires_at', 'unavailable')))}</code></p>
      </div>
    </section>
    <section>
      <h2>Operational Performance</h2>
      <p class="source-note">Source: Forge operation ledger · latest ingest {inline(str(forge.get('latest_ingest', 'unavailable')))}</p>
      {render_operations(operations)}
    </section>
    <section>
      <h2>Codex Folder Review</h2>
      <div class="grid">{folder_summary}</div>
      {render_archive_summary(archive_summary)}
      {render_codex_folder_table(folders)}
    </section>
    <section class="two-col">
      <div>
        <h2>Build Priorities</h2>
        {render_table(project_tables[0]) if project_tables else "<p>No project table found.</p>"}
      </div>
      <div class="notice">
        <h2>Inbox</h2>
        <ul>{inbox_html or "<li>No inbox items.</li>"}</ul>
      </div>
    </section>
    <section>
      <h2>Agents</h2>
      {render_tables(agent_tables, "No agent tables found.")}
    </section>
    <section class="two-col">
      <div>
        <h2>Skills</h2>
        {render_tables(skill_tables, "No skill tables found.")}
      </div>
      <div>
        <h2>Token Registry</h2>
        {render_table(token_tables[0]) if token_tables else "<p>No token table found.</p>"}
      </div>
    </section>
    <section>
      <h2>Service Register</h2>
      {render_table(service_tables[0]) if service_tables else "<p>No service table found.</p>"}
    </section>
    <section>
      <h2>Observed TCP Listeners</h2>
      <table>
        <thead><tr><th>Command</th><th>PID</th><th>Port</th><th>Address</th></tr></thead>
        <tbody>{listener_rows or "<tr><td colspan='4'>No listeners detected.</td></tr>"}</tbody>
      </table>
    </section>
  </main>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the caRINA AgentOps dashboard.")
    parser.add_argument("--agentops-dir", type=Path, default=DEFAULT_AGENTOPS_DIR)
    parser.add_argument("--codex-dir", type=Path, default=DEFAULT_CODEX_DIR)
    parser.add_argument("--documents-root", type=Path, default=DEFAULT_DOCUMENTS_DIR)
    parser.add_argument(
        "--project-snapshot",
        type=Path,
        default=Path(DEFAULT_PROJECT_SNAPSHOT) if DEFAULT_PROJECT_SNAPSHOT else None,
    )
    parser.add_argument("--write-project-snapshot", type=Path, default=None)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    docs = read_docs(args.agentops_dir)
    listeners = collect_listeners()
    folders = collect_codex_folders(args.codex_dir)
    archive_manifest = args.codex_dir / "_archive/2026-07-04-agentops-review/manifest.json"
    archive_summary = read_archive_summary(archive_manifest)
    if args.project_snapshot and args.project_snapshot.is_file():
        projects, project_snapshot_generated = read_project_snapshot(args.project_snapshot)
    else:
        projects = collect_projects(args.documents_root)
        project_snapshot_generated = "live " + datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    if args.write_project_snapshot:
        write_project_snapshot(args.write_project_snapshot, projects)
        project_snapshot_generated = read_project_snapshot(args.write_project_snapshot)[1]
    forge = collect_forge_metrics()
    guardian = read_json_object(DEFAULT_GUARDIAN_STATE)
    html_text = build_html(
        docs,
        listeners,
        folders,
        archive_summary,
        args.agentops_dir,
        projects,
        project_snapshot_generated,
        forge,
        guardian,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(html_text, encoding="utf-8")
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
