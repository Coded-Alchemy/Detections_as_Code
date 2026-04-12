#!/usr/bin/env python3
# ============================================================
# Script: diff_detections.py
# ------------------------------------------------------------
# Compares the Sigma rules changed in this PR/push against
# the base branch and emits a human-readable summary to
# GITHUB_STEP_SUMMARY. This gives SOC leads a clear picture
# of which detections were added, modified, or removed
# without having to read raw Terraform plan output.
#
# Requires:
#   - git available on PATH
#   - GITHUB_STEP_SUMMARY env var set (automatic in GHA)
#   - BASE_SHA env var set to the base commit to diff against
#
# Usage:
#   BASE_SHA=origin/main python3 scripts/diff_detections.py
# ============================================================
import subprocess
import sys
import os
import yaml
from pathlib import Path

RULES_DIR   = "sigma_rules"
SUMMARY_FILE = os.environ.get("GITHUB_STEP_SUMMARY", "/dev/stdout")
BASE_SHA     = os.environ.get("BASE_SHA", "HEAD~1")


def git_diff_names() -> dict[str, str]:
    """Return {filepath: status} for changed files in sigma_rules/."""
    result = subprocess.run(
        ["git", "diff", "--name-status", BASE_SHA, "HEAD", "--", RULES_DIR],
        capture_output=True, text=True, check=True
    )
    changed = {}
    for line in result.stdout.strip().splitlines():
        if not line:
            continue
        parts = line.split("\t", 1)
        if len(parts) == 2:
            status, path = parts
            changed[path] = status[0]  # A/M/D/R
    return changed


def extract_metadata(path: str) -> dict:
    """Pull key fields from a Sigma rule for the diff table."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            rule = yaml.safe_load(fh)
        return {
            "title":       rule.get("title", "—"),
            "level":       rule.get("level", "—"),
            "status":      rule.get("status", "—"),
            "description": rule.get("description", "—")[:120],
        }
    except Exception:
        return {"title": path, "level": "—", "status": "—", "description": "—"}


def git_show_old(path: str) -> dict:
    """Get metadata from the base branch version of a file."""
    try:
        result = subprocess.run(
            ["git", "show", f"{BASE_SHA}:{path}"],
            capture_output=True, text=True, check=True
        )
        rule = yaml.safe_load(result.stdout)
        return {
            "title":   rule.get("title", "—"),
            "level":   rule.get("level", "—"),
            "status":  rule.get("status", "—"),
        }
    except Exception:
        return {"title": "—", "level": "—", "status": "—"}


LEVEL_EMOJI = {
    "critical":      "🔴",
    "high":          "🟠",
    "medium":        "🟡",
    "low":           "🔵",
    "informational": "⚪",
}

STATUS_ICON = {
    "A": "✅ Added",
    "M": "✏️ Modified",
    "D": "🗑️ Removed",
    "R": "🔁 Renamed",
}


def main() -> int:
    try:
        changed = git_diff_names()
    except subprocess.CalledProcessError as exc:
        print(f"ERROR: git diff failed: {exc.stderr}", file=sys.stderr)
        return 1

    if not changed:
        print("No Sigma rule changes detected.")
        write_summary("## Detection Rule Changes\n\nNo Sigma rule changes in this run.\n")
        return 0

    added    = {p: m for p, m in changed.items() if m == "A"}
    modified = {p: m for p, m in changed.items() if m == "M"}
    removed  = {p: m for p, m in changed.items() if m == "D"}
    other    = {p: m for p, m in changed.items() if m not in ("A", "M", "D")}

    lines = ["## Detection Rule Changes\n"]
    lines.append(f"> **{len(added)} added · {len(modified)} modified · {len(removed)} removed**\n")

    if added:
        lines.append("\n### ✅ Added\n")
        lines.append("| Title | Level | Status | File |")
        lines.append("|-------|-------|--------|------|")
        for path in sorted(added):
            m = extract_metadata(path)
            emoji = LEVEL_EMOJI.get(m["level"], "")
            lines.append(f"| {m['title']} | {emoji} {m['level']} | {m['status']} | `{path}` |")

    if modified:
        lines.append("\n### ✏️ Modified\n")
        lines.append("| Title | Level | Status | Change | File |")
        lines.append("|-------|-------|--------|--------|------|")
        for path in sorted(modified):
            new = extract_metadata(path)
            old = git_show_old(path)
            level_change = (
                f"{LEVEL_EMOJI.get(old['level'],'')} {old['level']} → "
                f"{LEVEL_EMOJI.get(new['level'],'')} {new['level']}"
                if old["level"] != new["level"] else
                f"{LEVEL_EMOJI.get(new['level'],'')} {new['level']}"
            )
            status_change = (
                f"{old['status']} → {new['status']}"
                if old["status"] != new["status"] else new["status"]
            )
            lines.append(
                f"| {new['title']} | {level_change} | {status_change} | `{path}` |"
            )

    if removed:
        lines.append("\n### 🗑️ Removed\n")
        lines.append("| Title | Level | File |")
        lines.append("|-------|-------|------|")
        for path in sorted(removed):
            old = git_show_old(path)
            emoji = LEVEL_EMOJI.get(old["level"], "")
            lines.append(f"| {old['title']} | {emoji} {old['level']} | `{path}` |")

    if other:
        lines.append("\n### 🔁 Other changes\n")
        for path, status in sorted(other.items()):
            lines.append(f"- `{STATUS_ICON.get(status, status)}` `{path}`")

    summary = "\n".join(lines) + "\n"
    write_summary(summary)
    print(summary)
    return 0


def write_summary(content: str):
    with open(SUMMARY_FILE, "a", encoding="utf-8") as fh:
        fh.write(content)


if __name__ == "__main__":
    sys.exit(main())
