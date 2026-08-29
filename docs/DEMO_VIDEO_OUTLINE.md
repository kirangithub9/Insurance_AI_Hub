# 5-Minute Demo Video Outline

Target: hit all four judging criteria explicitly and on camera — don't make
the judges infer it.

**0:00–0:30 — Hook + problem statement**
"Business users at an insurer need three different specialists to get an
answer: a SQL analyst for numbers, a document reviewer for policy text, and
a data engineer for 'why is this dashboard wrong.' We built one agent that
replaces all three." Show the chat UI empty, ready.

**0:30–1:15 — Agent 1: Self-Service Analytics (Innovation + Technical Excellence)**
Type: *"What's our average loss ratio by policy type, and which policy type
has the most fraud-flagged claims?"* Show the answer, then expand "Generated
SQL" to prove it's real governed SQL against `ANALYTICS_SEMANTIC_VIEW`, not
a canned response. Narrate: native Snowflake `SEMANTIC VIEW`, no BI tool.

**1:15–2:15 — Agent 2: Document Q&A / RAG (Technical Excellence + UX)**
Type: *"What are the exclusion clauses for water damage in [policy ID]?"*
Show the answer with the source document cited, expand "Sources" to show
the citation. Narrate: Cortex Search auto-embeds and indexes document
chunks — no external vector DB, no manual embedding pipeline.

**2:15–3:15 — Agent 3: Data Quality Root Cause (Innovation + Business Value)**
Type: *"Why did the data quality check on [column] fail last week?"* Show a
conversational root-cause answer pulling from `DQ_RESULTS`/`DQ_RULES`.
Narrate: this used to mean opening a DQ dashboard and cross-referencing
rule logs manually — now it's one question.

**3:15–3:45 — Prove it's unified, not three separate demos**
Ask one more question that's ambiguous on purpose, and point out the same
chat box routed it correctly without the user picking a tool. Briefly show
the architecture diagram from `docs/ARCHITECTURE.md`.

**3:45–4:30 — Business value recap**
State concretely: "This removes SQL/BI dependency for three workflows,
cutting time-to-answer from [X] to seconds, and makes every answer
auditable via generated SQL and citations — critical for insurance
compliance."

**4:30–5:00 — Close**
Recap the three agents + unified orchestration, mention GitHub repo and
architecture doc are included, thank the judges.

## Filming tips

- Screen-record Snowsight full-window at 1080p+, hide any credentials/PII.
- Keep each typed question on screen long enough to read (2-3 sec pause
  before hitting enter).
- Pre-warm the Cortex Search service and semantic views before recording
  (first query after creation can be slower while it indexes).
- Have a backup take of each segment in case an answer is inconsistent —
  LLM-generated SQL can occasionally phrase differently between runs.
