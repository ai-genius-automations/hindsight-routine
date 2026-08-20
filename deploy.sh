#!/usr/bin/env bash
# Deploy the extraction prompt to the hindsight-extractor host.
#
# The deployed copy previously drifted from this repo because it was edited in
# place on the box. Always edit here and run this, so production and source
# stay the same file.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REMOTE_HOST="${REMOTE_HOST:-devcortex}"
readonly REMOTE_PATH="/srv/hindsight-extractor/prompt.md"
readonly SRC="$SCRIPT_DIR/prompts/extract_facts.md"

[ -f "$SRC" ] || { echo "Missing $SRC"; exit 1; }

echo "→ Uploading $SRC → ${REMOTE_HOST}:${REMOTE_PATH}"
scp -q "$SRC" "${REMOTE_HOST}:/tmp/extract_facts.md"
ssh "$REMOTE_HOST" "sudo cp /tmp/extract_facts.md ${REMOTE_PATH} && sudo chmod 644 ${REMOTE_PATH} && rm -f /tmp/extract_facts.md"

echo "→ Verifying"
local_sum=$(sha256sum "$SRC" | cut -d' ' -f1)
remote_sum=$(ssh "$REMOTE_HOST" "sudo sha256sum ${REMOTE_PATH}" | cut -d' ' -f1)
if [ "$local_sum" = "$remote_sum" ]; then
  echo "✓ Deployed and verified (${local_sum:0:16})"
else
  echo "✗ Checksum mismatch: local=${local_sum:0:16} remote=${remote_sum:0:16}"; exit 1
fi
