# hindsight-routine

**What's live here and what isn't:**

| Part | Status |
|---|---|
| [`prompts/extract_facts.md`](prompts/extract_facts.md) + [`deploy.sh`](deploy.sh) | ✅ **Active and canonical.** This repo is the only source of the Hindsight fact-extraction prompt. |
| The cloud routine ([`ROUTINE.md`](ROUTINE.md), trigger `trig_01MaReYX6ZFCdryME7qTcgVW`) | 🛑 **Retired 2026-04-22.** Kept only for history and rollback. |

## Active: the extraction prompt

Hindsight fact extraction now runs as an hourly cron on devcortex
(`/srv/hindsight-extractor/run.sh`), which calls `claude -p --json-schema`
directly. The extractor itself lives in aig-devkit — see
[`aig-devkit/hindsight/ARCHITECTURE.md`](https://github.com/ai-genius-automations/aig-devkit/blob/main/hindsight/ARCHITECTURE.md)
for how the pieces fit together and
[`aig-devkit/hindsight-extractor/`](https://github.com/ai-genius-automations/aig-devkit/tree/main/hindsight-extractor)
for the cron script, schema and installer.

The prompt that extractor uses is **this repo's**
[`prompts/extract_facts.md`](prompts/extract_facts.md), deployed to
`devcortex:/srv/hindsight-extractor/prompt.md`. aig-devkit does not carry a
copy; its `install.sh` only warns and points here if the prompt is missing on
the server.

### Update the extraction prompt

1. Edit [`prompts/extract_facts.md`](prompts/extract_facts.md) in this repo
   and commit it.
2. Run `./deploy.sh`. It copies the file to
   `devcortex:/srv/hindsight-extractor/prompt.md` and checks the sha256 of the
   deployed copy against the local file (override the host with
   `REMOTE_HOST=...`).

**Never edit `/srv/hindsight-extractor/prompt.md` on the box.** The deployed
copy has drifted from this repo before because it was edited in place. Before
uploading, `./deploy.sh` checks that the server copy matches the local file or
a committed version of the prompt. If it doesn't, the script shows the diff and
asks before overwriting (`FORCE=1` skips the question; with no terminal to ask
on, it stops). When it does overwrite, it first saves the hand-edited copy on
the server as `/srv/hindsight-extractor/prompt.md.hand-edit-<UTC timestamp>`.
Committing before you deploy keeps that check from flagging your
own earlier deploys.

## Retired: the cloud routine

> **Everything below this point documents the retired cloud routine.** It is
> kept for history, not as the current pipeline. The setup steps (creating the
> routine, its env vars, swapping accounts, the local smoke test) were removed;
> for a rollback, see this README at commit `3c15653` and
> [`ROUTINE.md`](ROUTINE.md). The routine is paused at
> https://claude.ai/code/routines/trig_01MaReYX6ZFCdryME7qTcgVW. It is also a
> reference example of how Claude Code routines are wired up with env config,
> custom cloud environments, and the bash-driven orchestration pattern.
>
> **Why we moved to the devcortex cron:**
> - Task subagents spawned by this routine cannot declare a structured-output
>   contract ([claude-code#20625](https://github.com/anthropics/claude-code/issues/20625)).
>   Extraction quality was bottlenecked on prompt-engineered JSON compliance,
>   which failed ~33% of the time in production (chunks returning prose or
>   off-schema fields got silently dropped).
> - The cloud runtime's 15-run/day cap on Max plans was a ceiling we'd bump
>   into if session volume grew; devcortex cron has no such limit.
> - Passing full 1.3 MB transcripts through a single `Task` subagent silently
>   truncated beyond Haiku's 200k window — the motivating bug was a session
>   that should have produced ~40 facts producing only 9.
>
> The new extractor solves all three: `--json-schema` gives 100% schema
> compliance, cron has no run cap, and explicit message-boundary chunking
> with `--max-turns 10` processes every chunk reliably.

---

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

## What this routine does NOT do (v1)

- **No retry logic.** If a transcript fails mid-run, it stays in `failed`
  state. Manually PATCH it back to unprocessed (or DELETE) to retry. The next
  hour's run won't pick it up automatically because its status is no longer
  `unprocessed`.
- **No Slack/email alerting on failure.** The routine's run log is the only
  surface. Check `claude.ai/code/routines` periodically.
- **No rich observability.** Fact counts and timings are in the run log only.

All three are reasonable v2 additions.
