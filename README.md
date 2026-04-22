# hindsight-routine

Nightly/hourly Claude Code routine that extracts facts from Claude Code
session transcripts (collected by [`hindsight-collector`](https://github.com/ai-genius-automations/hindsight-collector))
and writes them to hindsight via the team's [direct-insert endpoint](https://github.com/ai-genius-automations/hindsight/tree/aig/direct-insert).

Replaces hindsight's built-in retain flow (which is expensive per-token) with
a flat-rate flow running under a Claude Max subscription.

## Architecture

```
SessionEnd hook                        hindsight-collector
(on each dev machine)    ─ POST ──▶    (devcortex :8889)
                                              │
                                              │ polls
                                              ▼
                          ┌─────────────────────────────────────────┐
                          │  hindsight-routine (this repo)          │
                          │  Runs hourly under a Claude Max acct    │
                          │  on Anthropic's cloud.                  │
                          │                                         │
                          │  1. GET /transcripts?status=unprocessed │
                          │  2. Per transcript: Task subagent       │
                          │     extracts facts (Haiku by default)   │
                          │  3. POST hindsight /memories/direct     │
                          │  4. PATCH collector mark processed      │
                          └─────────────────────────────────────────┘
```

## Deployment

Routines live outside this repo — they're created per-account via Claude
Code's `/schedule` or `claude.ai/code/routines`. This repo is the
**portable artifact**: same repo works for any account. Account-specific
config lives in env vars on the routine's cloud environment.

### Step 1 — Create the routine

In Claude Code CLI:

```
/schedule create \
  --repo ai-genius-automations/hindsight-routine \
  --prompt "Run the flow defined in ROUTINE.md. Report progress." \
  --model claude-haiku-4-5 \
  --interval 1h \
  --name hindsight-extraction
```

Or via `claude.ai/code/routines` web UI — same fields.

### Step 2 — Set environment variables on the routine

Required:

| Var | Value |
|---|---|
| `COLLECTOR_URL` | `https://hindsight.coolip.me/collector` |
| `COLLECTOR_AUTH_TOKEN` | (copy from `/srv/hindsight/.env` → `COLLECTOR_AUTH_TOKEN`) |
| `HINDSIGHT_URL` | `https://hindsight.coolip.me` |
| `HINDSIGHT_AUTH_TOKEN` | (copy from `/srv/hindsight/.env` → `HINDSIGHT_API_AUTH_TOKEN`) |

Optional:

| Var | Default | Notes |
|---|---|---|
| `EXTRACTION_MODEL` | `claude-haiku-4-5` | Subagent model. Change to `claude-sonnet-4-6` for better quality at higher token cost. |
| `MAX_TRANSCRIPTS_PER_RUN` | `20` | Per-run cap so one bad run doesn't drain quota. |
| `USER_AGENT` | `aig-hindsight-routine/0.1.0` | Set on all outbound calls (Cloudflare-friendly). |

### Step 3 — Smoke-test before the first scheduled run

Trigger a manual run from the routine UI. Expected output from the routine:

```
hindsight-routine: processed=N failed=0 total_facts=M duration_s=T
```

Check the collector and hindsight to confirm:

```bash
# Any failed transcripts?
curl -sS "$COLLECTOR_URL/transcripts?status=failed&limit=10" \
  -H "Authorization: Bearer $COLLECTOR_AUTH_TOKEN"

# Did the facts land in hindsight?
curl -sS "$HINDSIGHT_URL/v1/default/banks/aig-projects/memories/list?limit=5" \
  -H "Authorization: Bearer $HINDSIGHT_AUTH_TOKEN"
```

## Swapping accounts (personal → shared Max)

Zero code changes. Steps:

1. On the new shared Max account, repeat Step 1 (create routine) pointing at
   the same repo.
2. Repeat Step 2 (set env vars) with the same values.
3. On the old personal account, **delete** the old routine so it stops
   running (otherwise you'll double-process transcripts and waste quota).

Because hindsight direct-insert is idempotent (`document_id` upserts), running
both routines briefly during cutover is safe — you just burn quota twice.

## Local testing without Claude Code

`test/local-smoke.sh` lets you exercise the collector↔hindsight round trip
without needing a routine. Set the four required env vars and run it — it'll
pull one unprocessed transcript, POST a hand-crafted fact to hindsight, and
mark the transcript processed. Useful for validating the plumbing before
wiring up extraction.

## What this routine does NOT do (v1)

- **No retry logic.** If a transcript fails mid-run, it stays in `failed`
  state. Manually PATCH it back to unprocessed (or DELETE) to retry. The next
  hour's run won't pick it up automatically because its status is no longer
  `unprocessed`.
- **No Slack/email alerting on failure.** The routine's run log is the only
  surface. Check `claude.ai/code/routines` periodically.
- **No rich observability.** Fact counts and timings are in the run log only.

All three are reasonable v2 additions.
