#!/usr/bin/env bash
# ============================================================
# Script: import_splunk_searches.sh
# ------------------------------------------------------------
# Compares saved searches currently in Splunk against the
# detection rules defined in locals.tf. Any rule that exists
# in Splunk but is absent from Terraform state is imported so
# subsequent plans do not attempt to recreate it.
#
# Must be run from the terraform/ working directory with
# TF_VAR_* environment variables already exported, and with
# SPLUNK_USERNAME / SPLUNK_PASSWORD / SPLUNK_URL available.
#
# Environment:
#   SECURE_TMPDIR   Job-scoped temp dir (set by secure-tmpdir action)
#   SPLUNK_TLS_SKIP Set to "true" ONLY in non-production lab environments
#
# Usage:
#   cd terraform && bash ../scripts/import_splunk_searches.sh
# ============================================================
set -uo pipefail

# ── TLS configuration ─────────────────────────────────────────────────────────
CURL_TLS_FLAGS=""
if [ "${SPLUNK_TLS_SKIP:-false}" = "true" ]; then
  echo "WARNING: TLS verification disabled (SPLUNK_TLS_SKIP=true). Lab use only."
  CURL_TLS_FLAGS="-k"
fi

# ── Scoped temp files ─────────────────────────────────────────────────────────
TMPDIR="${SECURE_TMPDIR:-/tmp/dac-fallback-$$}"
mkdir -p "$TMPDIR"
EXISTING_FILE="${TMPDIR}/existing_splunk_searches.txt"
TF_RULES_FILE="${TMPDIR}/tf_detection_rules.txt"

# ── 1. Fetch saved searches from Splunk ───────────────────────────────────────
echo "Fetching saved searches from Splunk..."

HTTP_RESPONSE=$(curl $CURL_TLS_FLAGS -s -w "\n%{http_code}" \
  -u "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}" \
  "${SPLUNK_URL}/services/saved/searches?output_mode=json&count=0")

HTTP_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

if [ "$HTTP_CODE" -ne 200 ]; then
  echo "ERROR: Splunk API returned HTTP $HTTP_CODE — cannot fetch saved searches"
  exit 1
fi

EXISTING=$(echo "$HTTP_BODY" | jq -r '.entry[].name' 2>/dev/null || echo "")

if [ -z "$EXISTING" ]; then
  echo "No existing saved searches found in Splunk — skipping import."
  exit 0
fi

echo "$EXISTING" > "$EXISTING_FILE"
echo "Found $(wc -l < "$EXISTING_FILE") saved search(es) in Splunk."
echo ""

# ── 2. Parse locals.tf for detection rule keys and names ─────────────────────
echo "Parsing locals.tf for detection rule definitions..."

python3 ../scripts/import_existing_searches.py > "$TF_RULES_FILE"

if [ ! -s "$TF_RULES_FILE" ]; then
  echo "No detection rules found in locals.tf — nothing to import."
  exit 0
fi

echo "Rules to evaluate:"
cat "$TF_RULES_FILE"
echo ""

# ── 3. Import rules that exist in Splunk but not in Terraform state ──────────
imported=0
skipped=0
failed=0

while IFS='|' read -r key name; do
  [ -z "$key" ] || [ -z "$name" ] && continue

  if grep -Fxq "$name" "$EXISTING_FILE"; then
    echo "Exists in Splunk: $name (key: $key)"

    if terraform state show "splunk_saved_searches.detections[\"$key\"]" \
        > /dev/null 2>&1; then
      echo "  [SKIP] Already in Terraform state"
      skipped=$((skipped + 1))
    else
      echo "  [IMPORT] Importing into state..."
      if terraform import \
          "splunk_saved_searches.detections[\"$key\"]" "$name" 2>&1; then
        echo "  [OK] Imported successfully"
        imported=$((imported + 1))
      else
        echo "  [WARN] Import failed — will be created on next apply"
        failed=$((failed + 1))
      fi
    fi
  else
    echo "Not in Splunk: $name (key: $key) — will be created on apply"
  fi
done < "$TF_RULES_FILE"

echo ""
echo "Import summary"
echo "--------------"
echo "  Imported : $imported"
echo "  Skipped  : $skipped"
echo "  Failed   : $failed"
