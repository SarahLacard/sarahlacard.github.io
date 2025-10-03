#!/usr/bin/env python3
"""Site build pipeline implemented in Python."""
from __future__ import annotations

import datetime as _dt
import html
import json
import re
import sys
from pathlib import Path
from typing import List

ROOT = Path(__file__).resolve().parent
LOG_FILE = ROOT / "build.log"
FILENAME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-\d{4}$")


def log(message: str) -> None:
    timestamp = _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {message}"
    print(line)
    try:
        with LOG_FILE.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError as exc:  # fall back to stdout-only if log write fails
        print(f"[WARN] Could not write to log file: {exc}", file=sys.stderr)


def ensure_repo_root() -> None:
    if not (ROOT / ".git").exists():
        raise SystemExit("Must run from repository root directory")


def ensure_directories() -> None:
    required = [
        "_weblogs",
        "_dialogues",
        "_vera",
        "_sessions",
        "_templates",
        "weblogs",
        "dialogues",
        "vera",
        "sessions",
    ]
    for rel in required:
        path = ROOT / rel
        log(f"Checking directory: {rel}")
        if not path.exists():
            log(f"Creating directory: {rel}")
            path.mkdir(parents=True, exist_ok=True)


def remove_orphaned_html(source_dir: str, output_dir: str, source_extension: str = ".txt") -> None:
    log(f"Cleaning up orphaned HTML files in {output_dir}")
    output_path = ROOT / output_dir
    if not output_path.exists():
        return

    for html_file in sorted(output_path.glob("*.html")):
        if source_dir == "_vera":
            source_file = ROOT / source_dir / "log.txt"
        else:
            source_file = ROOT / source_dir / (html_file.stem + source_extension)

        if not source_file.exists():
            log(f"Removing orphaned file: {html_file.name}")
            try:
                html_file.unlink()
            except OSError as exc:
                log(f"Failed to remove {html_file}: {exc}")


def read_template(rel_path: str) -> str:
    path = ROOT / rel_path
    if not path.exists():
        raise FileNotFoundError(f"Required template file not found: {rel_path}")
    return path.read_text(encoding="utf-8")


def _filename_to_date(stem: str) -> str:
    return f"{stem[0:4]}-{stem[5:7]}-{stem[8:10]} {stem[11:13]}:{stem[13:15]}"


def convert_text_section(source_dir: str, output_dir: str, template: str) -> List[str]:
    log(f"Converting section: {source_dir} -> {output_dir}")
    entries: List[str] = []
    source_path = ROOT / source_dir
    if not source_path.exists():
        return entries

    for post in sorted(source_path.glob("*.txt"), key=lambda p: p.name, reverse=True):
        log(f"Converting file: {post.name}")
        stem = post.stem
        if not FILENAME_RE.match(stem):
            log(f"File {post.name} does not match expected format YYYY-MM-DD-HHMM.txt")
            continue

        date_str = _filename_to_date(stem)
        content = post.read_text(encoding="utf-8")
        parts = content.split("\n", 1)
        if len(parts) < 2:
            log(f"File {post.name} does not have title and content separated by newline")
            continue
        title = parts[0].strip()
        post_content = parts[1].strip()

        encoded_title = html.escape(title)
        encoded_content = html.escape(post_content)
        encoded_date = html.escape(date_str)

        html_output = template.replace("{{date}}", encoded_date)
        html_output = html_output.replace("{{title}}", encoded_title)
        html_output = html_output.replace("{{content}}", encoded_content)

        output_path = ROOT / output_dir
        output_path.mkdir(parents=True, exist_ok=True)
        output_file = output_path / f"{stem}.html"
        output_file.write_text(html_output, encoding="utf-8")
        log(f"Generating HTML file: {output_file}")

        entries.append(
            f"                    <div class=\"weblog-entry\">\n"
            f"                        <span class=\"weblog-date\">[{encoded_date}]</span>\n"
            f"                        <a href=\"./{output_dir}/{stem}.html\">{encoded_title}</a>\n"
            f"                    </div>"
        )

    return entries


def convert_vera(template: str) -> List[str]:
    log("Converting Vera's commentary")
    source_file = ROOT / "_vera" / "log.txt"
    if not source_file.exists():
        return []

    content = source_file.read_text(encoding="utf-8")
    html_output = template.replace("{{content}}", content)

    output_dir = ROOT / "vera"
    output_dir.mkdir(parents=True, exist_ok=True)
    output_file = output_dir / "log.html"
    output_file.write_text(html_output, encoding="utf-8")
    log(f"Generating HTML file: {output_file}")

    timestamp = _dt.datetime.now().strftime("[%Y-%m-%d %H:%M]")
    entry = (
        "                <div class=\"weblog-entry\">\n"
        f"                    <span class=\"weblog-date\">{timestamp}</span>\n"
        "                    <a href=\"./vera/log.html\">Vera's Commentary</a>\n"
        "                </div>"
    )
    return [entry]


def _coerce_content(value) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, (list, tuple, set)):
        return "\n".join(str(item) for item in value)
    return str(value)


def convert_sessions(template: str) -> List[str]:
    log("Converting sessions section")
    source_path = ROOT / "_sessions"
    entries: List[str] = []
    if not source_path.exists():
        return entries

    for session in sorted(source_path.glob("*.jsonl"), key=lambda p: p.name, reverse=True):
        log(f"Converting session file: {session.name}")
        stem = session.stem
        if not FILENAME_RE.match(stem):
            log(f"Session file {session.name} does not match expected format YYYY-MM-DD-HHMM.jsonl")
            continue

        date_str = _filename_to_date(stem)
        messages = []
        for raw_line in session.read_text(encoding="utf-8").splitlines():
            trimmed = raw_line.strip()
            if not trimmed:
                continue
            try:
                messages.append(json.loads(trimmed))
            except json.JSONDecodeError:
                log(f"Skipping invalid JSON line in {session.name}: {trimmed}")

        if not messages:
            log(f"No valid messages found in {session.name}")
            continue

        title: str | None = None
        for msg in messages:
            if isinstance(msg, dict):
                candidate = msg.get("title")
                if candidate and str(candidate).strip():
                    title = str(candidate).strip()
                    break
                meta = msg.get("meta")
                if isinstance(meta, dict):
                    candidate = meta.get("title")
                    if candidate and str(candidate).strip():
                        title = str(candidate).strip()
                        break
                if msg.get("type") == "meta" and msg.get("summary"):
                    candidate = msg.get("summary")
                    if candidate and str(candidate).strip():
                        title = str(candidate).strip()
                        break
        if not title:
            title = f"Session {date_str}"

        encoded_title = html.escape(title)
        encoded_date = html.escape(date_str)

        session_blocks: List[str] = []
        for msg in messages:
            if not isinstance(msg, dict):
                continue
            role = msg.get("role") or msg.get("type") or "message"
            role = str(role).strip() or "message"
            encoded_role = html.escape(role)
            role_class = re.sub(r"[^a-zA-Z0-9]", "-", role).lower() or "message"

            timestamp = msg.get("timestamp")
            timestamp_line = "            "
            if timestamp is not None and str(timestamp).strip():
                encoded_timestamp = html.escape(str(timestamp).strip())
                timestamp_line = f"            <div class=\"session-timestamp\">{encoded_timestamp}</div>"

            content_value = _coerce_content(msg.get("content"))
            if not content_value:
                content_value = _coerce_content(msg.get("text"))
            encoded_content = html.escape(content_value)

            session_blocks.append(
                "        <div class=\"session-turn session-"
                + role_class
                + "\">\n"
                + f"            <div class=\"session-role\">{encoded_role}</div>\n"
                + timestamp_line
                + "\n"
                + f"            <pre>{encoded_content}</pre>\n"
                + "        </div>"
            )

        content_html = "\n".join(session_blocks)
        output_dir = ROOT / "sessions"
        output_dir.mkdir(parents=True, exist_ok=True)
        output_file = output_dir / f"{stem}.html"
        html_output = template
        html_output = html_output.replace("{{title}}", encoded_title)
        html_output = html_output.replace("{{date}}", encoded_date)
        html_output = html_output.replace("{{content}}", content_html)
        output_file.write_text(html_output, encoding="utf-8")
        log(f"Generating session HTML file: {output_file}")

        entries.append(
            f"                    <div class=\"weblog-entry\">\n"
            f"                        <span class=\"weblog-date\">[{encoded_date}]</span>\n"
            f"                        <a href=\"./sessions/{stem}.html\">{encoded_title}</a>\n"
            f"                    </div>"
        )

    return entries


def update_index(entries_map: dict[str, List[str]]) -> None:
    index_path = ROOT / "index.html"
    if not index_path.exists():
        raise FileNotFoundError("index.html not found")

    html_text = index_path.read_text(encoding="utf-8")

    replacements = [
        (r"(<div class=\"folder\">weblogs</div>\s*<div class=\"indent\">)(.*?)(\s*</div>\s*\s*<div class=\"folder\">dialogues</div>)",
         entries_map.get("weblogs", [])),
        (r"(<div class=\"folder\">dialogues</div>\s*<div class=\"indent\">)(.*?)(\s*</div>\s*\s*<div class=\"folder\">sessions</div>)",
         entries_map.get("dialogues", [])),
        (r"(<div class=\"folder\">sessions</div>\s*<div class=\"indent\">)(.*?)(\s*</div>\s*\s*<div class=\"folder\">vera</div>)",
         entries_map.get("sessions", [])),
        (r"(<div class=\"folder\">vera</div>\s*<div class=\"indent\">)(.*?)(\s*</div>\s*\s*<div class=\"file\">projects</div>)",
         entries_map.get("vera", [])),
    ]

    for pattern, entries in replacements:
        def repl(match: re.Match[str]) -> str:
            joined = "\n".join(entries)
            return f"{match.group(1)}\n{joined}{match.group(3)}"

        html_text, count = re.subn(pattern, repl, html_text, flags=re.DOTALL)
        log(f"Updated index.html section with pattern {pattern!r} ({count} replacements)")

    index_path.write_text(html_text, encoding="utf-8")
    log("Writing updated index.html")


def main() -> None:
    ensure_repo_root()
    log("Starting build...")
    ensure_directories()

    remove_orphaned_html("_weblogs", "weblogs")
    remove_orphaned_html("_dialogues", "dialogues")
    remove_orphaned_html("_vera", "vera")
    remove_orphaned_html("_sessions", "sessions", ".jsonl")

    post_template = read_template("_templates/post.html")
    vera_template = read_template("_templates/vera.html")
    session_template = read_template("_templates/session.html")

    weblog_entries = convert_text_section("_weblogs", "weblogs", post_template)
    dialogue_entries = convert_text_section("_dialogues", "dialogues", post_template)
    session_entries = convert_sessions(session_template)
    vera_entries = convert_vera(vera_template)

    update_index({
        "weblogs": weblog_entries,
        "dialogues": dialogue_entries,
        "sessions": session_entries,
        "vera": vera_entries,
    })

    log("Build completed successfully")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        log(f"Error occurred: {exc}")
        raise
