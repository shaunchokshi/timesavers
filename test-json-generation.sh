#!/usr/bin/env bash

# Test script to verify JSON generation doesn't include ANSI color codes

echo "Testing email CSV to JSON array conversion..."
test_emails="shaun@chokshi.net,shaun@ckservicesllc.com"

# Call the Python function directly (same as in the script)
result=$(python3 -c '
import json,sys
csv=sys.argv[1].strip()
arr=[x.strip() for x in csv.split(",") if x.strip()]
print(json.dumps(arr))
' "$test_emails")

echo "Input: $test_emails"
echo "Output: $result"
echo ""

# Check if output contains ANSI escape codes
if echo "$result" | grep -q $'\033'; then
  echo "ERROR: Output contains ANSI escape codes!"
  echo "$result" | od -c | head -20
else
  echo "SUCCESS: No ANSI escape codes found in email array"
fi
echo ""

# Test JSON validity
if echo "$result" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
  echo "SUCCESS: Email array is valid JSON"
  # Pretty print it
  echo "$result" | python3 -m json.tool
else
  echo "ERROR: Email array is NOT valid JSON"
fi
echo ""

# Test that the array has the correct number of elements
element_count=$(echo "$result" | python3 -c 'import json,sys; print(len(json.loads(sys.stdin.read())))')
echo "Number of email addresses in array: $element_count"
if [ "$element_count" = "2" ]; then
  echo "SUCCESS: Correct number of elements"
else
  echo "ERROR: Expected 2 elements, got $element_count"
fi
echo ""

# Now test a simulated document SID return (like from upload_document_utility_bill)
echo "Testing document SID extraction (simulating fixed function)..."
# This simulates what the function should return - just the SID, nothing else
test_doc_sid="RD6595ddc1792838fe649dd25f56207fd4"
echo "Document SID: $test_doc_sid"

# Create a test JSON payload with this SID
test_payload=$(python3 -c "
import json
payload = {
    'documents': ['$test_doc_sid'],
    'notification_emails': ['shaun@chokshi.net', 'shaun@ckservicesllc.com']
}
print(json.dumps(payload, indent=2))
")

echo "Test payload:"
echo "$test_payload"
echo ""

# Verify the payload is valid JSON
if echo "$test_payload" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
  echo "SUCCESS: Payload is valid JSON"
else
  echo "ERROR: Payload is NOT valid JSON"
fi
