#!/usr/bin/env python3
"""Builds the failure report that CI posts as a commit comment.

Why a commit comment: the job log and the uploaded artifacts are served from a
blob host that some networks cannot reach at all, while the repository API
works everywhere the code does.

Usage (from the repository root, after the failing steps):

    python3 tool/ci/collect_failures.py ci-failure.md

Reads `analyze.log` and `test.json` if they exist; missing files are simply
skipped, so the report also works when the run died before the tests.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import summarize_tests  # noqa: E402  (local sibling module)

MAX_ANALYZER_LINES = 200


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return ""


def analyzer_section(text: str) -> list[str]:
    """Only errors block CI, so the report leads with them."""
    if not text.strip():
        return []
    lines = text.splitlines()
    problems = [line.strip() for line in lines if re.search(r"\s•\s", line)]
    errors = [line for line in problems if " error • " in line]
    summary = [
        line.strip()
        for line in lines
        if "issues found" in line or "No issues" in line
    ]
    body = errors if errors else problems
    out = ["#### flutter analyze"]
    out += summary or ["(no summary line)"]
    out += ["```", *(body[:MAX_ANALYZER_LINES] or ["(no analyzer findings)"]), "```"]
    if len(body) > MAX_ANALYZER_LINES:
        out.append(f"… {len(body) - MAX_ANALYZER_LINES} more findings omitted")
    return out


def build_log_section(text: str, limit: int = 120) -> list[str]:
    """The tail of a compiler/CLI log: the error is at the end, not the start."""
    if not text.strip():
        return []
    lines = [line for line in text.splitlines() if line.strip()]
    return ["#### build log (tail)", "```", *lines[-limit:], "```"]


def build_report(root: Path) -> str:
    analyze = _read(root / "analyze.log")
    test_json = root / "test.json"
    build_log = _read(Path(os.environ.get("MELLOW_BUILD_LOG", "build.log")))

    parts = [
        f"### CI failure for {os.environ.get('GITHUB_SHA', 'unknown')[:7]}",
        "",
    ]
    for section in (
        analyzer_section(analyze),
        build_log_section(build_log),
        summarize_tests.render(
            summarize_tests.parse(test_json) if test_json.exists() else {
                "tests": [], "failures": [], "success": None, "started": 0
            }
        ).splitlines() if test_json.exists() else [],
    ):
        if section:
            parts += section + [""]
    if len(parts) <= 2:
        parts.append("No logs were produced: the run failed before the first check.")
    return "\n".join(parts).strip() + "\n"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: collect_failures.py <output.md>", file=sys.stderr)
        return 2
    report = build_report(Path("."))
    Path(argv[1]).write_text(report, encoding="utf-8")
    print(f"{len(report)} characters written to {argv[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
