#!/usr/bin/env bash
# End-to-end plumbing smoke test for hindsight-routine.
#
# Does NOT run real extraction — the fact is hardcoded. What this verifies:
#   1. Both services are reachable (collector, hindsight).
#   2. Auth tokens work for both.
#   3. The list → fetch → direct-insert → patch flow connects end to end.
#
# Run with the same env vars you'd set on a real routine:
#   COLLECTOR_URL=... COLLECTOR_AUTH_TOKEN=... \
#   HINDSIGHT_URL=... HINDSIGHT_AUTH_TOKEN=... \
#   bash test/local-smoke.sh
#
# If no unprocessed transcripts exist, the test posts a dummy one first.

set -euo pipefail

UA="${USER_AGENT:-aig-hindsight-routine-smoke/0.1.0}"
for var in COLLECTOR_URL COLLECTOR_AUTH_TOKEN HINDSIGHT_URL HINDSIGHT_AUTH_TOKEN; do
  if [ -z "${!var:-}" ]; then
    echo "FATAL: $var not set" >&2
    exit 1
  fi
done

die() { echo "FAIL: $*" >&2; exit 1; }

curl_c() { curl -sS -H "User-Agent: $UA" -H "Authorization: Bearer $COLLECTOR_AUTH_TOKEN" "$@"; }
curl_h() { curl -sS -H "User-Agent: $UA" -H "Authorization: Bearer $HINDSIGHT_AUTH_TOKEN" "$@"; }

echo "--- 1. reachability ---"
code=$(curl -sS -o /dev/null -w "%{http_code}" -H "User-Agent: $UA" "$COLLECTOR_URL/health")
[ "$code" = "200" ] || die "collector /health returned $code"
code=$(curl -sS -o /dev/null -w "%{http_code}" -H "User-Agent: $UA" "$HINDSIGHT_URL/health")
[ "$code" = "200" ] || die "hindsight /health returned $code"
echo "OK both services healthy"

echo ""
echo "--- 2. list unprocessed ---"
LIST=$(curl_c "$COLLECTOR_URL/transcripts?status=unprocessed&limit=1")
COUNT=$(echo "$LIST" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['items']))")
echo "found $COUNT unprocessed transcript(s)"

if [ "$COUNT" = "0" ]; then
  echo ""
  echo "--- 2b. no transcripts — posting a dummy one ---"
  DUMMY=$(curl_c -X POST "$COLLECTOR_URL/transcripts" \
    -H "Content-Type: application/json" \
    -d "{\"session_id\":\"smoke-$(date +%s)\",\"bank_id\":\"aig-smoke-test\",\"transcript_blob\":\"smoke test only\",\"message_count\":1}")
  TID=$(echo "$DUMMY" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
  BANK="aig-smoke-test"
else
  TID=$(echo "$LIST" | python3 -c "import sys, json; print(json.load(sys.stdin)['items'][0]['id'])")
  BANK=$(echo "$LIST" | python3 -c "import sys, json; print(json.load(sys.stdin)['items'][0]['bank_id'])")
fi
echo "using transcript id=$TID bank=$BANK"

echo ""
echo "--- 3. direct-insert a dummy fact to hindsight ---"
INSERT=$(curl_h -X POST "$HINDSIGHT_URL/v1/default/banks/$BANK/memories/direct" \
  -H "Content-Type: application/json" \
  -d "{\"facts\":[{\"fact_text\":\"local-smoke.sh end-to-end plumbing test succeeded for transcript $TID.\",\"fact_type\":\"assistant\",\"tags\":[\"smoke-test\"]}],\"document_id\":\"$TID\",\"context\":\"Plumbing smoke test\"}")
UNIT_COUNT=$(echo "$INSERT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('count', 0))")
[ "$UNIT_COUNT" = "1" ] || die "expected 1 unit inserted, got: $INSERT"
echo "OK inserted $UNIT_COUNT unit into hindsight bank $BANK"

echo ""
echo "--- 4. patch transcript processed ---"
PATCHED=$(curl_c -X PATCH "$COLLECTOR_URL/transcripts/$TID" \
  -H "Content-Type: application/json" \
  -d "{\"status\":\"processed\",\"processed_by\":\"local-smoke.sh\",\"fact_count\":1}")
PROC_AT=$(echo "$PATCHED" | python3 -c "import sys, json; print(json.load(sys.stdin).get('processed_at'))")
[ -n "$PROC_AT" ] && [ "$PROC_AT" != "None" ] || die "patch did not set processed_at: $PATCHED"
echo "OK transcript marked processed at $PROC_AT"

echo ""
echo "=== SMOKE TEST PASSED ==="
echo "(The smoke-test fact + transcript is still in hindsight/collector. Clean up via:"
echo "  curl -X DELETE -H \"Authorization: Bearer \$COLLECTOR_AUTH_TOKEN\" \$COLLECTOR_URL/transcripts/$TID )"
