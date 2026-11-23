#!/usr/bin/env python3
"""Reads `flutter test --reporter json` output and prints a Markdown report.

Used twice in CI:

* appended to the job summary (`summarize_tests.py test.json`);
* as the body of the failure commit comment (`--comment`).

The JSON reporter is used instead of the expanded one because its events carry
the exact file, test name, error message and stack of every failure. The
expanded reporter interleaves printers with test output, so a failure message
can appear hundreds of lines away from the test it belongs to.

Usage:
    python3 tool/ci/summarize_tests.py test.json > report.md
    python3 tool/ci/summarize_tests.py test.json --comment ci-failure.md
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

LAYERS = ("lib", "test", "tool", "integration_test")
MAX_FAILURES = 12
MAX_STACK_LINES = 18
MAX_CHARS = 60000


def _short(path: str) -> str:
    for layer in LAYERS:
        marker = f"/{layer}/"
        if marker in path:
            return path[path.index(marker) + 1 :]
    return path


def parse(path: Path) -> dict:
    """Returns {"tests": [...], "failures": [...], "success": bool|None}."""
    tests: list[dict] = []
    by_id: dict[int, dict] = {}
    suites: dict[int, str] = {}
    failures: list[dict] = []
    success: bool | None = None
    started = 0

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = event.get("type")
        if kind == "suite":
            suite = event.get("suite") or {}
            suites[suite.get("id", -1)] = suite.get("path") or ""
        elif kind == "testStart":
            test = event.get("test") or {}
            if str(test.get("name", "")).startswith("loading "):
                # Synthetic "loading test/foo_test.dart" pseudo-tests.
                continue
            entry = {
                "name": test.get("name", "?"),
                "url": test.get("url") or suites.get(test.get("suiteID", -1), ""),
                "line": test.get("line") or 0,
                "errors": [],
            }
            by_id[test.get("id", -1)] = entry
            started += 1
        elif kind == "error":
            entry = by_id.get(event.get("testID", -1))
            if entry is None:
                continue
            entry["errors"].append(
                {
                    "error": (event.get("error") or "").strip(),
                    "stack": (event.get("stackTrace") or "").strip(),
                    "isFailure": bool(event.get("isFailure")),
                }
            )
        elif kind == "testDone":
            entry = by_id.get(event.get("testID", -1))
            if entry is None:
                continue
            entry["result"] = event.get("result")
            entry["hidden"] = bool(event.get("hidden"))
            if event.get("result") == "success":
                tests.append(entry)
            elif event.get("result") in {"failure", "error"} and not event.get("hidden"):
                failures.append(entry)
        elif kind == "done":
            success = event.get("success")

    return {"tests": tests, "failures": failures, "success": success, "started": started}


def _summary(parsed: dict) -> list[str]:
    total = len(parsed["tests"]) + len(parsed["failures"])
    failed = len(parsed["failures"])
    verdict = "passed" if failed == 0 else "FAILED"
    return [
        f"### flutter test: {verdict}",
        "",
        f"{total - failed} passed, {failed} failed (of {total} tests).",
        "",
    ]


def _failure_block(entry: dict, limit: int = MAX_STACK_LINES) -> list[str]:
    where = _short(entry.get("url") or "")
    if entry.get("line"):
        where = f"{where}:{entry['line']}"
    name = entry.get("name", "?").strip()
    out = [f"#### ✗ {name}", f"`{where}`", ""]
    for error in entry.get("errors", [])[:2]:
        message = error["error"].replace("```", "'''")
        out += ["```", *message.splitlines()[:limit], "```"]
        stack = [
            line
            for line in error["stack"].splitlines()
            if _short(line).find("/test/") >= 0 or "package:mellow/" in line
        ]
        if stack:
            out += ["", "first frames:", "```", *stack[:6], "```"]
    return out


def render(parsed: dict, comment: bool = False) -> str:
    parts: list[str] = []
    if comment:
        parts += [
            f"### CI failure for {os.environ.get('GITHUB_SHA', 'unknown')[:7]}",
            "",
        ]
    parts += _summary(parsed)
    failures = parsed["failures"]
    if failures:
        parts.append(f"#### failing tests ({len(failures)})")
        parts.append("")
        for entry in failures:
            parts.append(
                f"- {_short(entry.get('url') or '')}: {entry.get('name', '?').strip()}"
            )
        parts.append("")
        for entry in failures[:MAX_FAILURES]:
            parts += _failure_block(entry) + [""]
        if len(failures) > MAX_FAILURES:
            parts.append(f"… {len(failures) - MAX_FAILURES} more failures omitted.")
    return "\n".join(parts).strip() + "\n"


def main(argv: list[str]) -> int:
    args = [arg for arg in argv[1:] if not arg.startswith("--")]
    flags = {arg for arg in argv[1:] if arg.startswith("--")}
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    source = Path(args[0])
    if not source.exists():
        print("No test report was produced (the step failed before running tests).")
        return 0
    parsed = parse(source)
    report = render(parsed, comment="--comment" in flags)
    if "--comment" in flags:
        print(report[:MAX_CHARS])
    else:
        print(report[:MAX_CHARS])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
