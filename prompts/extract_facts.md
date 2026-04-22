# Extraction subagent prompt

The routine passes you a single Claude Code session transcript (formatted as
JSON: a list of `{role, content: [blocks…]}`). Your job is to extract the
**significant long-term facts** worth remembering for future sessions. The
facts will be stored in a team-shared memory (hindsight) and recalled by
other agents in future conversations.

## Output — return ONLY this JSON, nothing else

```json
{
  "facts": [
    {
      "fact_text": "One complete sentence (1-2 sentences max). Self-contained.",
      "fact_type": "world" | "assistant",
      "where": "location string, or null",
      "occurred_start": "2026-04-22T02:00:00Z" or null,
      "occurred_end": null,
      "entities": [
        {"name": "specific proper noun or identifier", "type": "PERSON"}
      ],
      "tags": ["optional tag", ...]
    }
  ]
}
```

**Schema rules:**
- `fact_text` — required, non-empty. A single short statement. Must stand alone
  without the surrounding context.
- `fact_type` — required. `"world"` for objective/external facts ("X is
  located at Y", "the deadline is Friday"). `"assistant"` for first-person
  actions, experiences, or observations by the speaker ("I fixed X",
  "we decided Y").
- `where` — optional. Physical or logical location.
- `occurred_start` / `occurred_end` — ISO 8601 UTC timestamps for time-bounded
  events. Null if not applicable.
- `entities` — list of named entities mentioned in the fact. Use `type`:
  `PERSON`, `PROJECT`, `COMPANY`, `CONCEPT`, `LOCATION`, `TECHNOLOGY`,
  `SERVICE`, `FILE`, `URL`. Default `CONCEPT`.
- `tags` — optional short labels (lowercase, hyphenated). E.g. `["preferences"]`,
  `["deploy"]`, `["bug"]`. Use sparingly.

**Return the JSON object ONLY.** No prose before or after. No markdown fence.
Just `{ "facts": [ ... ] }`.

## What to extract

**DO extract:**
- Durable rules/preferences: "User never uses sed/awk on remote servers", "the
  team prefers tabs", "always run npm test before pushing".
- Architectural/design decisions with stated reasons: "we use Postgres schema
  X because Y", "retain was disabled because Z".
- Factual events that matter later: "reboot test passed", "container Y was
  deployed", "API key was rotated".
- Relationships: "highcall-test VM (192.168.1.70) runs Fastify + Supabase".
- User intent or priorities: "user wants to ship the collector this week",
  "feature X is blocked until Y".

**DO NOT extract:**
- Transient state: "I just ran `ls`", "file has 5 lines".
- Tool-call noise: the fact that a grep happened, or a command was typed.
- Content that's obvious from the project structure or code itself.
- Anything the session undid or contradicted later — extract the final state,
  not the failed attempt.
- Duplicate facts — pick the best single phrasing.

## Quality bar

Err toward fewer, higher-quality facts. It is better to extract 5 facts that
will still be useful a month from now than 30 noisy facts. Each fact should
answer the question: "would a teammate starting a session tomorrow benefit
from knowing this?"

## Transcript

{TRANSCRIPT_BLOB}
