echo "Importing existing saved searches from Splunk..."

# Get existing searches from Splunk
EXISTING=$(curl -k -s -u "${{ secrets.SPLUNK_USERNAME }}:${{ secrets.SPLUNK_PASSWORD }}" \
  "${{ secrets.SPLUNK_URL }}/services/saved/searches?output_mode=json&count=0" \
  | jq -r '.entry[].name' 2>/dev/null || echo "")

if [ -z "$EXISTING" ]; then
  echo "No existing searches found - skipping import"
  exit 0
fi

echo "Found existing searches in Splunk"
echo "$EXISTING" > /tmp/existing_searches.txt

# Parse locals.tf using Python (path relative to terraform directory)
chmod +x ../scripts/import_existing_searches.py
python3 ../scripts/import_existing_searches.py > /tmp/tf_rules.txt

if [ ! -s /tmp/tf_rules.txt ]; then
  echo "No detection rules found"
  exit 0
fi

echo "Found rules to process:"
cat /tmp/tf_rules.txt
echo ""

# Import matching searches
while IFS='|' read -r key name; do
  if [ -z "$key" ] || [ -z "$name" ]; then
    continue
  fi

  if grep -Fxq "$name" /tmp/existing_searches.txt; then
    echo "Found in Splunk: $name (key: $key)"

    if terraform state show "splunk_saved_searches.detections[\"$key\"]" >/dev/null 2>&1; then
      echo "  ✓ Already in state"
    else
      echo "  → Importing..."
      if terraform import "splunk_saved_searches.detections[\"$key\"]" "$name" 2>&1; then
        echo "  ✓ Successfully imported"
      else
        echo "  ✗ Import failed (will be created)"
      fi
    fi
  else
    echo "Not in Splunk yet: $name (key: $key) - will be created"
  fi
done < /tmp/tf_rules.txt

rm -f /tmp/existing_searches.txt /tmp/tf_rules.txt
echo ""
echo "Import process complete"