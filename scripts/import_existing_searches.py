#!/usr/bin/env python3
# ============================================================
# Script: import_existing_searches.py
# ------------------------------------------------------------
# Parses locals.tf to extract detection rule keys and names.
# Outputs one "key|name" pair per line for consumption by
# import_splunk_searches.sh.
#
# The previous regex approach broke on nested braces (heredocs,
# severity_map, etc). This version tracks brace depth to find
# the true boundary of each rule block.
# ============================================================
import sys
from pathlib import Path


def extract_detection_rules(content: str) -> dict[str, str]:
    """
    Extract rule key -> name pairs from locals.tf by tracking
    brace depth rather than relying on regex character classes
    that cannot handle nested braces.
    """
    rules = {}

    # Find the start of the detection_rules block
    marker = "detection_rules"
    marker_pos = content.find(marker)
    if marker_pos == -1:
        return rules

    # Advance to the opening brace of detection_rules = {
    brace_start = content.find("{", marker_pos)
    if brace_start == -1:
        return rules

    # Walk the detection_rules block tracking depth
    depth       = 0
    pos         = brace_start
    block_start = None
    current_key = None

    while pos < len(content):
        ch = content[pos]

        if ch == "{":
            depth += 1
            if depth == 2:
                # Entering a rule block — capture start position
                block_start = pos

        elif ch == "}":
            if depth == 2 and block_start is not None and current_key is not None:
                # Closing a rule block — extract the name field
                rule_block = content[block_start:pos + 1]
                name = extract_name(rule_block)
                if name:
                    rules[current_key] = name
                block_start  = None
                current_key  = None

            depth -= 1
            if depth == 0:
                # Closed the detection_rules block entirely
                break

        elif depth == 1:
            # Between rule blocks at depth 1 — look for the next key
            # Keys look like:  some_rule_key = {
            if ch not in (" ", "\n", "\r", "\t", "#"):
                # Scan for a key = { pattern from this position
                key, advance = try_read_key(content, pos)
                if key:
                    current_key = key
                    pos         = advance
                    continue

                # Skip comment lines
                if ch == "#":
                    eol = content.find("\n", pos)
                    pos = eol if eol != -1 else len(content)
                    continue

        pos += 1

    return rules


def try_read_key(content: str, pos: int):
    """
    Try to read an identifier followed by whitespace and '=' and '{'.
    Returns (key, new_pos) on success, (None, pos) on failure.
    """
    end = pos
    while end < len(content) and (content[end].isalnum() or content[end] == "_"):
        end += 1

    if end == pos:
        return None, pos

    key       = content[pos:end]
    remainder = content[end:].lstrip()

    if remainder.startswith("="):
        after_eq = remainder[1:].lstrip()
        if after_eq.startswith("{"):
            return key, end
    return None, pos


def extract_name(block: str) -> str:
    """
    Extract the value of the 'name' field from a rule block string.
    Looks for:   name = "some value"
    Ignores alert_email_subject and other keys containing 'name'.
    """
    lines = block.splitlines()
    for line in lines:
        stripped = line.strip()
        # Match lines like:  name = "..."  but not  alert_email_...
        if stripped.startswith("name") and "=" in stripped:
            parts = stripped.split("=", 1)
            if len(parts) == 2:
                value = parts[1].strip().strip('"')
                # Reject if it looks like a variable reference or is empty
                if value and not value.startswith("$") and not value.startswith("local."):
                    return value
    return ""


def main() -> int:
    locals_tf = Path("locals.tf")

    if not locals_tf.exists():
        print("ERROR: locals.tf not found in current directory", file=sys.stderr)
        return 1

    content = locals_tf.read_text(encoding="utf-8")
    rules   = extract_detection_rules(content)

    if not rules:
        print("No detection rules found in locals.tf", file=sys.stderr)
        return 0

    for key, name in rules.items():
        print(f"{key}|{name}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
