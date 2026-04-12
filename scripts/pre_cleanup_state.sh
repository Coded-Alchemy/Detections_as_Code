#!/usr/bin/env bash
# ============================================================
# Script: pre_cleanup_state.sh
# ------------------------------------------------------------
# Iterates every splunk_saved_searches.detections resource in
# Terraform state and removes any entry that:
#   1. Cannot be read by terraform state show, OR
#   2. Returns a non-200 from the Splunk API when looked up
#      by name (catches stale entries that exist locally in
#      state but have been deleted from Splunk)
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
#   cd terraform && bash ../scripts/pre_cleanup_state.sh
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
TEMP_FILE="${TMPDIR}/state_show_output.txt"

echo "Pre-cleanup: scanning state entries against Splunk..."
echo ""

STATE_RESOURCES=$(terraform state list 2>/dev/null \
  | grep 'splunk_saved_searches.detections' || echo "")

if [ -z "$STATE_RESOURCES" ]; then
  echo "No detection resources in state — nothing to clean."
  exit 0
fi

echo "Resources found in state:"
echo "$STATE_RESOURCES"
echo ""

removed=0

while read -r resource; do
  echo "Checking: $resource"

  # ── Step 1: Can Terraform read it at all? ───────────────────────────────────
  if ! terraform state show "$resource" > "$TEMP_FILE" 2>&1; then
    echo "  [REMOVE] terraform state show failed"
    terraform state rm "$resource" 2>&1 || true
    removed=$((removed + 1))
    continue
  fi

  if grep -qi "error\|404\|not found\|invalid" "$TEMP_FILE"; then
    echo "  [REMOVE] state show output contains error indicators"
    terraform state rm "$resource" 2>&1 || true
    removed=$((removed + 1))
    continue
  fi

  # ── Step 2: Does it actually exist in Splunk? ───────────────────────────────
  SEARCH_NAME=$(grep -m 1 '^[[:space:]]*name[[:space:]]*=' "$TEMP_FILE" \
    | sed 's/.*= "\(.*\)"/\1/' || echo "")

  if [ -z "$SEARCH_NAME" ]; then
    echo "  [REMOVE] Cannot determine saved search name from state"
    terraform state rm "$resource" 2>&1 || true
    removed=$((removed + 1))
    continue
  fi

  echo "  → Name: '$SEARCH_NAME'"

  # URL-encode the search name for the API call
  ENCODED_NAME=$(python3 -c \
    "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" \
    "$SEARCH_NAME")

  HTTP_CODE=$(curl $CURL_TLS_FLAGS -s -o /dev/null -w "%{http_code}" \
    -u "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}" \
    "${SPLUNK_URL}/services/saved/searches/${ENCODED_NAME}?output_mode=json")

  echo "  → Splunk API response: HTTP $HTTP_CODE"

  if [ "$HTTP_CODE" -eq 200 ]; then
    echo "  [OK] Exists in Splunk"
  else
    echo "  [REMOVE] Not found in Splunk (HTTP $HTTP_CODE) — removing stale state entry"
    terraform state rm "$resource" 2>&1 || true
    removed=$((removed + 1))
  fi

done <<< "$STATE_RESOURCES"

rm -f "$TEMP_FILE"

echo ""
echo "Pre-cleanup complete. Removed $removed stale entry/entries."
echo ""
echo "Remaining detection resources in state:"
terraform state list | grep 'splunk_saved_searches.detections' || echo "  (none)"
