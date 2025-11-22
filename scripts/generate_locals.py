import yaml, os, json

SIGMA_DIR = "../rules/*/"  # update if your rules live elsewhere
OUTFILE = "../terraform/locals.tf"

rules = {}

for root, _, files in os.walk(SIGMA_DIR):
    for f in files:
        if f.endswith((".yml", ".yaml")):
            path = os.path.join(root, f)
            with open(path, "r") as fh:
                data = yaml.safe_load(fh)

            rule_id = data.get("id") or os.path.splitext(f)[0]

            rules[rule_id] = {
                "title": data.get("title", ""),
                "description": data.get("description", ""),
                "status": data.get("status", ""),
                "author": data.get("author", ""),
                "date": data.get("date", ""),
                "logsource": data.get("logsource", {}),
                "detection": data.get("detection", {}),
                "level": data.get("level", ""),
                "tags": data.get("tags", []),
                "falsepositives": data.get("falsepositives", []),
            }

with open(OUTFILE, "w") as out:
    out.write("locals {\n")
    out.write("  sigma_rules = {\n")
    for rid, content in rules.items():
        out.write(f'    "{rid}" = {json.dumps(content, indent=2)}\n')
    out.write("  }\n")
    out.write("}\n")

print(f"Generated locals.tf with {len(rules)} Sigma rules")