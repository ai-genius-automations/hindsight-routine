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

# Refuse to silently clobber a hand-edited server copy: the remote file must
# match the local file or some committed version of the prompt.
echo "→ Checking ${REMOTE_HOST}:${REMOTE_PATH} for hand edits"
if ssh "$REMOTE_HOST" "sudo test -f ${REMOTE_PATH}"; then
  remote_copy=$(mktemp)
  trap 'rm -f "$remote_copy"' EXIT
  ssh "$REMOTE_HOST" "sudo cat ${REMOTE_PATH}" > "$remote_copy"
  remote_sum=$(sha256sum "$remote_copy" | cut -d' ' -f1)
  known=0
  [ "$remote_sum" = "$(sha256sum "$SRC" | cut -d' ' -f1)" ] && known=1
  if [ "$known" = 0 ]; then
    while read -r rev; do
      [ -n "$rev" ] || continue
      rev_sum=$(git -C "$SCRIPT_DIR" show "$rev:prompts/extract_facts.md" | sha256sum | cut -d' ' -f1)
      if [ "$rev_sum" = "$remote_sum" ]; then known=1; break; fi
    done < <(git -C "$SCRIPT_DIR" log --format=%H -- prompts/extract_facts.md)
  fi
  if [ "$known" = 0 ]; then
    echo "⚠ The server copy matches no committed version of prompts/extract_facts.md."
    echo "  It was probably edited by hand on ${REMOTE_HOST}. Diff (server → local):"
    diff -u --label "server:${REMOTE_PATH}" --label "local:prompts/extract_facts.md" "$remote_copy" "$SRC" || true
    if [ "${FORCE:-0}" != 1 ]; then
      read -r -p "Overwrite the server copy (a backup is kept on the server)? [y/N] " answer < /dev/tty \
        || { echo "No terminal to confirm; re-run with FORCE=1 to overwrite."; exit 1; }
      [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted; server copy left unchanged."; exit 1; }
    fi
    backup="${REMOTE_PATH}.hand-edit-$(date -u +%Y%m%dT%H%M%SZ)"
    ssh "$REMOTE_HOST" "sudo cp -p ${REMOTE_PATH} ${backup}"
    echo "→ Backed up the hand-edited copy to ${REMOTE_HOST}:${backup}"
  fi
fi

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
