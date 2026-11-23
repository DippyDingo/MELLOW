#!/usr/bin/env python3
"""Posts a Markdown report as a commit comment.

The job log and the uploaded artifacts are served from a blob host that some
networks cannot reach; a commit comment is readable wherever the repository is,
including from a phone.

Usage:
    python3 tool/ci/post_comment.py report.md

Environment: `GH_TOKEN` (or `GITHUB_TOKEN`), `GITHUB_REPOSITORY`, `GITHUB_SHA`.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

MAX_BODY = 60000


def post(body: str) -> int:
    repository = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    token = os.environ.get("GH_TOKEN") or os.environ["GITHUB_TOKEN"]

    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/commits/{sha}/comments",
        data=json.dumps({"body": body[:MAX_BODY]}).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            # GitHub rejects requests without a User-Agent.
            "User-Agent": "mellow-ci",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            print("commit comment posted:", response.status)
            return 0
    except urllib.error.HTTPError as error:
        print(f"could not post the comment: {error.code} {error.reason}", file=sys.stderr)
        print(error.read().decode("utf-8", "replace")[:500], file=sys.stderr)
        return 1


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: post_comment.py <report.md>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    if not path.exists():
        print(f"{path} does not exist", file=sys.stderr)
        return 1
    body = path.read_text(encoding="utf-8").strip()
    if not body:
        print("nothing to post")
        return 0
    return post(body)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
