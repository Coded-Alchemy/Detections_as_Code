#!/bin/bash

set -e
mkdir -p generated/splunk generated/convert_errors

echo "Converting Sigma rules to SPL..."
rule_count=0
failed_count=0
failed_rules=()

while IFS= read -r rule_file; do
  file_name=$(basename "$rule_file" .yml)
  
  # Run conversion and capture both stdout and stderr
  if output=$(sigma convert --target splunk --pipeline splunk_windows "$rule_file" 2>&1); then
    # Write to file
    echo "$output" > "generated/splunk/${file_name}.spl"
    
    if [ -s "generated/splunk/${file_name}.spl" ]; then
      echo "   ✓ $file_name"
      ((rule_count++))
    else
      echo "   ✗ $file_name - OUTPUT EMPTY"
      echo "$output" > "generated/convert_errors/${file_name}.err"
      ((failed_count++))
      failed_rules+=("$rule_file")
    fi
  else
    exit_code=$?
    echo "   ✗ $file_name - CONVERSION FAILED (exit code: $exit_code)"
    echo "$output" > "generated/convert_errors/${file_name}.err"
    ((failed_count++))
    failed_rules+=("$rule_file")
  fi
done < <(find sigma_rules -type f -name "*.yml" | sort)

echo ""
echo "=========================================="
echo "Conversion Summary"
echo "=========================================="
echo "Successful: $rule_count"
echo "Failed: $failed_count"

if [ $failed_count -gt 0 ]; then
  echo ""
  echo "Failed Rules:"
  for rule in "${failed_rules[@]}"; do
    file_name=$(basename "$rule" .yml)
    echo ""
    echo "▼▼▼ $rule ▼▼▼"
    cat "generated/convert_errors/${file_name}.err"
    echo "▲▲▲ END $file_name ▲▲▲"
  done
  echo ""
  exit 1
fi

echo ""
ls -lh generated/splunk/