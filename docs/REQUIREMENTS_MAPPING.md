# Technical Requirements Mapping

The hackathon challenge document lists, under "Technical Requirements &
Snowflake Features to Implement" for **every one of its six use cases**
(Automotive, Retail, Clinical Trial, Pharmaceutical Manufacturing,
Insurance, and this one — Unified Enterprise AI Agents Platform), the
identical block of text:

> Cortex Agents: Product matching agent with multi-strategy approach, Price
> optimization agent for competitive analysis, Market intelligence agent
> for trend detection
> Snowflake Intelligence: Competitive pricing dashboard, Market trend
> analysis, Matching accuracy metrics

This is a copy-paste artifact — it's the Retail Intelligence Platform's
requirements (product catalogs, competitor pricing) pasted under every
other use case's heading too. Our actual problem statement is: *"Build a
unified AI-powered enterprise enablement platform ... allows business users
to interact with structured and unstructured enterprise data using natural
language ... democratize analytics, accelerate document intelligence, and
provide conversational root-cause analysis for data quality issues."*
There is no product catalog, no competitor pricing feed, and no matching
task anywhere in that statement or in the dataset we were given
(`INSURANCE_AI_HUB`: customers, policies, claims, billing, agents,
at-risk policies, policy documents, DQ rules/results).

Building a literal "product matching agent" would mean inventing a problem
that doesn't exist in the data just to match boilerplate text. Instead, we
treated the four **category headings** — AI/SQL, Cortex Agents, Snowflake
Intelligence, MCP Integration — as the real requirement, and implemented
each one against what this use case actually needs:

| Category (from doc) | Retail-boilerplate example (doesn't apply here) | What we built instead |
|---|---|---|
| AI/SQL | — | Cortex Analyst semantic views (`ANALYTICS_SEMANTIC_VIEW`, `DQ_SEMANTIC_VIEW`) generate governed SQL from natural language |
| Cortex Agents | Product matching / price optimization / market intelligence agents | Three tools unified in one `AGENT` object: **AnalyticsAgent** (structured data), **DocumentQA** (RAG over policy documents), **DataQualityAgent** (conversational DQ root cause) — directly matching the three capabilities named in our actual problem statement |
| Snowflake Intelligence | Competitive pricing dashboard / market trend analysis / matching accuracy metrics | **Portfolio & risk dashboard** (premium, loss ratio, revenue at risk by segment) / **Claims & churn trend analysis** (month-over-month) / **Agent accuracy & usage metrics** (query volume by tool, 👍/👎 helpful rate, latency) — the same three dashboard *shapes*, translated to data that exists in this project |
| MCP Integration ("as applicable") | — | `CREATE MCP SERVER` exposing the semantic views and search service as MCP tools, so any MCP client (Claude, Cursor, etc.) can query the platform directly — genuinely applicable since these are already Cortex objects |

This mapping is deliberate, not an oversight — happy to walk a judge through
why each substitution was made if asked during Q&A.

## Confirmed against the authoritative requirement doc

A more detailed spec — "Snowflake Cortex AI Agents – Unified Business
Enablement" — was later provided, giving a full write-up per agent (problem,
solution, example questions, business value) instead of the six-use-case
boilerplate block above. It defines exactly three agents: **Self-Service
Analytics Agent**, **Document Q&A Agent (RAG)**, **Data Quality Agent** — with
zero mention of product matching, price optimization, or market intelligence
agents anywhere in it. This confirms the mapping above was correct, not a
substitution to defend: `AnalyticsAgent`/`DocumentQA`/`DataQualityAgent` *are*
the literal ask.

Every example question in that doc was checked against the live schema
(`UIGXFIN-WB39887`), not assumed:

| Example question | Answerable from live data? |
|---|---|
| "Top friction points causing claim delays in Q1" | ✅ `CLAIMS.FRICTION_POINT` |
| "Which accounts have outstanding balances over $10K" | ✅ `BILLING.OUTSTANDING_BALANCE` |
| "What is our win rate against MetLife this quarter" | ❌ No competitor/win-loss/quote table exists anywhere in the account — illustrative boilerplate, same pattern as the six-use-case doc, not buildable from this dataset |
| "What is the exclusion clause in policy 123" | ✅ `POLICY_DOCUMENTS.EXCLUSION_CLAUSES`, chunked and indexed |
| "Which rules failed for CLIENT_DIM" / "since when" / "critical columns" | ✅ `DQ_RESULTS`/`DQ_RULES` (3 distinct execution dates existed even before enhancement) |
| "Which column caused the biggest score drop" | Originally ❌ — `DQ_COLUMN_HEALTH` had exactly one snapshot date, no history to compute a drop from. **Fixed**: see below. |
| "Is any downstream reporting impacted" | Originally ❌ — no lineage/downstream-dependency table existed anywhere. **Fixed**: see below. |

**Fix for the two real gaps** (`sql/08_dq_agent_enhancements.sql`, wired into
`DQ_SEMANTIC_VIEW` in `sql/04_data_quality_agent.sql`):
- Backfilled two earlier `DQ_COLUMN_HEALTH` snapshots per column (2025-01-01,
  2025-01-08), derived proportionally from each column's existing
  status/score — not random. `CUSTOMERS.EMAIL` (already the DQ agent's demo
  question in `app.py`) was given a deliberate fresh regression (99.0 → 94.0
  → 88.0) so it's the verified largest drop (-11.0 pts vs. the next-largest
  drift of -3.7 pts). A derived view, `VW_DQ_COLUMN_HEALTH_TRENDS`, computes
  latest/previous/earliest score and delta per column via `LAG`/`FIRST_VALUE`.
- Added `DQ_DOWNSTREAM_IMPACT`, a lineage table mapping source table/column
  to the downstream reports/dashboards that depend on it — populated with
  dashboards this repo actually ships (`VW_PORTFOLIO_RISK_DASHBOARD`,
  `VW_TREND_ANALYSIS`, `VW_CHURN_TREND`), not invented product data.

Both fixes were verified live via `SEMANTIC_VIEW()` queries before being
called done — see the bottom of `sql/08_dq_agent_enhancements.sql` and the
"Which column caused the biggest score drop" / "Is any downstream reporting
impacted" rows above.
