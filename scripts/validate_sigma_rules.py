#!/usr/bin/env python3
# ============================================================
# Script: validate_sigma_rules.py
# ------------------------------------------------------------
# Validates every Sigma rule under sigma_rules/ against the
# required schema fields before conversion is attempted.
# Catches malformed rules early so conversion errors are not
# mistaken for logic problems.
#
# Checks enforced per rule:
#   - Required top-level keys present
#   - 'status' is a recognised value
#   - 'level' is a recognised value
#   - 'detection' block contains 'condition'
#   - 'logsource' block is present and non-empty
#
# Usage:
#   python3 scripts/validate_sigma_rules.py
#
# Exit codes:
#   0 - All rules valid
#   1 - One or more rules failed validation
# ============================================================
import sys
import os
import yaml
from pathlib import Path

RULES_DIR   = Path("sigma_rules")
VALID_STATUS = {"stable", "test", "experimental", "deprecated", "unsupported"}
VALID_LEVEL  = {"critical", "high", "medium", "low", "informational"}

REQUIRED_KEYS = [
    "title",
    "status",
    "description",
    "logsource",
    "detection",
]

def validate_rule(path: Path) -> list[str]:
    """Return a list of validation error strings for the given rule file."""
    errors = []

    try:
        with open(path, "r", encoding="utf-8") as fh:
            rule = yaml.safe_load(fh)
    except yaml.YAMLError as exc:
        return [f"YAML parse error: {exc}"]

    if not isinstance(rule, dict):
        return ["Rule did not parse to a mapping — check YAML structure"]

    # Required keys
    for key in REQUIRED_KEYS:
        if key not in rule:
            errors.append(f"Missing required key: '{key}'")

    # Status
    status = rule.get("status", "")
    if status and status not in VALID_STATUS:
        errors.append(
            f"Unknown status '{status}'. Must be one of: {sorted(VALID_STATUS)}"
        )

    # Level
    level = rule.get("level", "")
    if level and level not in VALID_LEVEL:
        errors.append(
            f"Unknown level '{level}'. Must be one of: {sorted(VALID_LEVEL)}"
        )

    # Detection block
    detection = rule.get("detection", {})
    if isinstance(detection, dict):
        if "condition" not in detection:
            errors.append("'detection' block is missing a 'condition' field")
    else:
        errors.append("'detection' must be a mapping")

    # Logsource block
    logsource = rule.get("logsource", {})
    if not isinstance(logsource, dict) or not logsource:
        errors.append("'logsource' must be a non-empty mapping")

    return errors


def main() -> int:
    rule_files = sorted(RULES_DIR.rglob("*.yml"))

    if not rule_files:
        print(f"ERROR: No Sigma rules found under '{RULES_DIR}'", file=sys.stderr)
        return 1

    total   = len(rule_files)
    passed  = 0
    failed  = 0

    print(f"Validating {total} Sigma rule(s)...\n")

    for rule_path in rule_files:
        rel = rule_path.relative_to(Path("../files"))
        errors = validate_rule(rule_path)

        if errors:
            print(f"  [FAIL] {rel}")
            for err in errors:
                print(f"         → {err}")
            failed += 1
        else:
            print(f"  [PASS] {rel}")
            passed += 1

    print(f"\nValidation summary")
    print(f"------------------")
    print(f"  Total  : {total}")
    print(f"  Passed : {passed}")
    print(f"  Failed : {failed}")

    if failed > 0:
        print(f"\nERROR: {failed} rule(s) failed validation. Fix errors before conversion.")
        return 1

    print("\nAll rules passed validation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
