
set -e
mkdir -p generated/splunk

echo "Converting Sigma rules to SPL..."
rule_count=0

while IFS= read -r rule_file; do
  file_name=$(basename "$rule_file" .yml)

  if sigma convert --target splunk --pipeline splunk_windows "$rule_file" > "generated/splunk/${file_name}.spl" 2>&1; then
    if [ -s "generated/splunk/${file_name}.spl" ]; then
      echo "${file_name}.spl"
      rule_count=$((rule_count + 1))
    else
      echo "${file_name}.spl is empty"
      exit 1
    fi
  else
    echo "Failed to convert $rule_file"
    exit 1
  fi
done < <(find sigma_rules -type f -name "*.yml")

if [ "$rule_count" -eq 0 ]; then
  echo "ERROR: No rules converted"
  exit 1
fi

echo "Converted $rule_count rule(s)"
ls -lh generated/splunk/