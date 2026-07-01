#!/usr/bin/env bash
set -uo pipefail

INPUT_DIR="sigma_rules"
OUT_DIR="generated/splunk"
ERR_DIR="generated/convert_errors"

mkdir -p "$OUT_DIR" "$ERR_DIR"

echo "Converting Sigma rules to SPL..."
rule_count=0
failures=()

# Find YAML files (both .yml and .yaml)
while IFS= read -r -d '' rule_file; do
  base="$(basename "$rule_file")"
  file_name="${base%.*}"
  out_file="${OUT_DIR}/${file_name}.spl"
  err_file="${ERR_DIR}/${file_name}.err"

  echo "-> Converting: $rule_file"
  # Run converter, capturing stdout and stderr separately
  if sigma convert --target splunk \
       --pipeline splunk_windows \
       --pipeline .github/pipelines/lab_index_mapping.yml \
       "$rule_file" >"$out_file" 2>"$err_file"; then

    if [ -s "$out_file" ]; then
      echo "   OK: ${file_name}.spl"
      rule_count=$((rule_count + 1))
    else
      echo "   WARN: ${file_name}.spl is empty; see ${err_file}"
      failures+=("${rule_file} (empty output)")
    fi

  else
    echo "   ERROR: conversion failed for $rule_file; see ${err_file}"
    failures+=("$rule_file")
  fi

done < <(find "$INPUT_DIR" -type f \( -iname '*.yml' -o -iname '*.yaml' \) -print0)

echo
echo "Converted: $rule_count successful"
if [ "${#failures[@]}" -ne 0 ]; then
  echo "Failures: ${#failures[@]}"
  printf '%s\n' "${failures[@]}" >&2

  # Bundle error logs into a single file for CI artifact upload/inspection
  echo "==== Conversion failures ====" > generated/convert-failures-summary.txt
  for f in "${failures[@]}"; do
    echo "$f" >> generated/convert-failures-summary.txt
  done
  echo "" >> generated/convert-failures-summary.txt
  echo "Per-file error dumps (first 300 lines):" >> generated/convert-failures-summary.txt
  for ef in "$ERR_DIR"/*.err; do
    [ -s "$ef" ] || continue
    echo "---- $ef ----" >> generated/convert-failures-summary.txt
    head -n 300 "$ef" >> generated/convert-failures-summary.txt
    echo "" >> generated/convert-failures-summary.txt
  done

  # Exit non-zero so the job fails and is visible
  exit 1
fi

if [ "$rule_count" -eq 0 ]; then
  echo "ERROR: No rules converted" >&2
  exit 1
fi

echo "All conversions succeeded."
ls -lh "$OUT_DIR"
exit 0