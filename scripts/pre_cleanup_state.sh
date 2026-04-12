echo "Pre-cleanup: Checking for broken state entries..."

# List all detection resources
STATE_RESOURCES=$(terraform state list 2>/dev/null | grep 'splunk_saved_searches.detections' || echo "")

if [ -z "$STATE_RESOURCES" ]; then
  echo "No resources in state"
  exit 0
fi

echo "Found resources in state:"
echo "$STATE_RESOURCES"
echo ""

# Try to read each resource, remove if it fails
echo "$STATE_RESOURCES" | while read -r resource; do
  echo "Testing: $resource"

  # Capture both stdout and stderr
  if terraform state show "$resource" >/tmp/test_output.txt 2>&1; then
    # Check if output contains error messages
    if grep -qi "error\|404\|not found\|invalid" /tmp/test_output.txt; then
      echo "  ✗ Contains errors, removing..."
      terraform state rm "$resource" 2>&1 || true
    else
      echo "  ✓ OK"
    fi
  else
    echo "  ✗ Failed to read, removing..."
    terraform state rm "$resource" 2>&1 || true
  fi
done

rm -f /tmp/test_output.txt

echo ""
echo "Pre-cleanup complete. Remaining resources:"
terraform state list | grep 'splunk_saved_searches.detections' || echo "  (none)"