# Hindsight fact extraction

You are given a Claude Code session transcript (JSON list of `{role, content: [blocks...]}` messages). Your job is to extract the **significant long-term facts** worth remembering for future sessions in a team-shared memory system.

The output schema is enforced by the runtime — you cannot produce invalid JSON. Focus on *which* facts to extract, not on formatting.

## What to extract

**DO extract:**
- Durable rules/preferences: "User never uses sed/awk on remote servers", "team prefers tabs over spaces", "always run npm test before pushing".
- Architectural/design decisions with stated reasons: "we use Postgres schema X because Y", "retain was disabled because it was burning OpenAI budget without being used".
- Factual events that matter later: "reboot test passed", "container Y was deployed to production on 2026-04-21", "API key was rotated".
- Relationships between entities: "highcall-test VM (192.168.1.70) runs Fastify + Supabase", "devcortex hosts hindsight-collector on port 8889".
- User intent or priorities: "user wants to ship the collector this week", "feature X is blocked until Y lands".

**DO NOT extract:**
- Transient state: "I just ran `ls`", "file has 5 lines", "grep returned no results".
- Tool-call noise: the fact that a grep or read happened.
- Content that's obvious from the project structure, code, or git history.
- Anything the session undid or contradicted later — extract the **final** state, not failed attempts.
- Near-duplicate facts — pick the best single phrasing.
- **Harness and session mechanics.** The launcher, not the user, produces these,
  and they describe how the session was started rather than anything learned in
  it. They also poison recall: a fact like "user told the assistant to read
  <path>" is the closest match for the next launcher prompt, so these compound.
  Specifically, never extract:
  - Task-assignment boilerplate: "user assigned the assistant as sole owner of
    this feature/bugfix", "user instructed the assistant to read <file>",
    "call the completion URL when finished".
  - Session bookkeeping: session ids, message counts, transcript sizes, flush
    or retain flags, "Session metadata: ...".
  - Process/PID observations: what was in `ps`, which flags a `claude` process
    was launched with, tmux session inventories.
  - The mere existence or path of a per-session context file.
  - Agent-tooling bookkeeping: task-status changes ("set task #3 to
    completed via TaskUpdate"), tool_use_ids, "the tool returned
    confirmation", or the fact that a tool produced a result. The *outcome*
    may be worth a fact; the tool mechanics never are.

  Do still extract durable facts that happen to mention such paths — e.g.
  "project X uses the octoally-pro session system, with context files under
  .octoally-pro/sessions/" is real architecture worth keeping. The test is
  whether the fact outlives the session that produced it.

## Per-field guidance

- `fact_text`: one complete self-contained sentence. Must stand alone without the surrounding transcript.
- `fact_type`:
  - `"world"` — objective/external truths, states, decisions, relationships.
  - `"assistant"` — first-person actions, experiences, observations ("I fixed X", "we decided Y").
- `where`: location string (file path, host, URL, room) or null.
- `occurred_start` / `occurred_end`: ISO-8601 UTC for time-bounded events; null otherwise. If only a date is known, use `YYYY-MM-DDT00:00:00Z`.
- `entities`: named entities referenced in the fact. Prefer proper nouns and specific identifiers over generic terms.
- `tags`: short lowercase-hyphenated labels (`["preferences"]`, `["deploy"]`, `["bug"]`). Use sparingly — 0-3 per fact.

## Quality bar

**Err toward fewer, higher-quality facts.** Five facts that will still be useful a month from now beats thirty noisy ones. Each fact should answer: *would a teammate starting a session tomorrow benefit from knowing this?*

## Transcript

Below is the (possibly partial / chunked) transcript to extract from. Session boundaries may be mid-conversation — extract what you can from this slice.
