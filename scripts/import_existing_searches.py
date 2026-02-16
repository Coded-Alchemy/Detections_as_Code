#!/usr/bin/env python3
import re
import sys


def parse_locals_tf():
    """Parse locals.tf to extract detection rule keys and names"""
    rules = {}

    with open('locals.tf', 'r') as f:
        content = f.read()

    # Extract the detection_rules block
    match = re.search(r'detection_rules\s*=\s*\{(.*?)\n\s*}', content, re.DOTALL)
    if not match:
        return rules

    rules_block = match.group(1)

    # Find each rule definition
    rule_pattern = r'(\w+)\s*=\s*\{[^}]*name\s*=\s*"([^"]+)"'

    for match in re.finditer(rule_pattern, rules_block):
        key = match.group(1)
        name = match.group(2)
        rules[key] = name

    return rules


def main():
    rules = parse_locals_tf()

    if not rules:
        print("No detection rules found in locals.tf")
        sys.exit(0)

    print(f"Found {len(rules)} detection rules")

    for key, name in rules.items():
        print(f"{key}|{name}")


if __name__ == '__main__':
    main()