# Architecture Documentation — Unified Enterprise AI Agents Platform

## 1. Problem

Business users at insurers need answers from structured operational data
(policies, claims, billing), unstructured documents (policy contracts,
exclusion clauses), and data-quality pipelines — but today each requires a
different specialist (a SQL/BI analyst, a document reviewer, a data
engineer). This platform collapses all three into one natural-language
conversation.

## 2. High-level architecture

```
                                        ┌────────────────────────────────┐
                                        │     Streamlit-in-Snowflake     │
                                        │        Chat UI (app.py)        │
                                        └────────────────────────────────┘
                                                         │ REST: agents/{name}:run
                                                         ▼
                                        ┌────────────────────────────────┐
                                        │      ENTERPRISE_AI_AGENT       │
                                        │    (Snowflake Cortex Agent)    │
                                        │  auto-orchestration / routing  │
                                        └────────────────────────────────┘
                                                         │
                  ┌──────────────────────────────────────┬──────────────────────────────────────┐
                  ▼                                      ▼                                      ▼
┌──────────────────────────────────┐   ┌──────────────────────────────────┐   ┌──────────────────────────────────┐
│   Self-Service Analytics Agent   │   │        Document Q&A Agent        │   │        Data Quality Agent        │
│          Cortex Analyst          │   │      Cortex Search Service       │   │          Cortex Analyst          │
│          (text-to-SQL)           │   │      (RAG, auto-embeddings)      │   │          (text-to-SQL)           │
└──────────────────────────────────┘   └──────────────────────────────────┘   └──────────────────────────────────┘
                  ▼                                      ▼                                      ▼
ANALYTICS_SEMANTIC_VIEW                POLICY_DOCUMENT_SEARCH_SVC             DQ_SEMANTIC_VIEW
over ANALYTICS schema                  over DOCUMENTS.DOCUMENT_CHUNKS         over DATA_QUALITY schema
(CUSTOMERS, POLICIES,                  (chunked from POLICY_DOCUMENTS         (DQ_RULES, DQ_RESULTS,
CLAIMS, BILLING, AGENTS,               .CONTENT_TEXT via                      DQ_COLUMN_HEALTH, DQ_SCORES,
AT_RISK_POLICIES)                      SPLIT_TEXT_RECURSIVE_CHARACTER)        VW_DQ_COLUMN_HEALTH_TRENDS,
                                                                              DQ_DOWNSTREAM_IMPACT)
```

Tool names above are the exact wording from the requirement doc
(`tool_spec.name` in `sql/03_create_unified_agent.sql`). The agent runtime
sanitizes spaces/`&` to underscores in anything it actually returns
(`tool_use.name`, logs, traces): `Self-Service_Analytics_Agent`,
`Document_Q_A_Agent`, `Data_Quality_Agent` — confirmed live, see the
"Resolved during build" note below.

Everything runs natively inside Snowflake — one platform, one governance
boundary, no data leaves the account and no external vector database or
orchestration service is required.

## 3. Component design

**Agent 1 — Self-Service Analytics.** A native `SEMANTIC VIEW`
(`ANALYTICS_SEMANTIC_VIEW`) declares business-friendly dimensions, facts, and
metrics (loss ratio, total premium, fraud claim count, revenue at risk,
churn probability, etc.) over six operational tables, with relationships
declared explicitly so Cortex Analyst always joins correctly. Cortex Analyst
translates a natural-language question into governed SQL against this view.

**Agent 2 — Document Q&A (RAG).** `POLICY_DOCUMENTS.CONTENT_TEXT` (already
extracted document text) is chunked with
`SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER` into `DOCUMENT_CHUNKS`. A
`CORTEX SEARCH SERVICE` indexes `CHUNK_TEXT`, with `POLICY_ID`,
`DOCUMENT_TYPE`, and `DOCUMENT_TITLE` as filterable attributes. Cortex
Search generates and manages embeddings internally — no separate embedding
pipeline to maintain.

**Agent 3 — Data Quality Root Cause.** A second semantic view
(`DQ_SEMANTIC_VIEW`) sits over `DQ_RULES`, `DQ_RESULTS`, `DQ_COLUMN_HEALTH`,
`DQ_SCORES`, `VW_DQ_COLUMN_HEALTH_TRENDS` (per-column score trend/delta), and
`DQ_DOWNSTREAM_IMPACT` (lineage to affected dashboards/reports), letting a
business user ask "why did X fail", "which column dropped the most", or "is
any downstream reporting impacted" and get a conversational, evidence-backed
answer instead of opening a data-quality dashboard.

**Orchestration.** All three are registered as `tool_resources` on one
`AGENT` object (`ENTERPRISE_AI_AGENT`). Cortex Agents' orchestration model
decides per-question which tool(s) to invoke — the "unified" requirement is
satisfied at the platform level, not by the user having to pick an agent.

**Front end.** A Streamlit-in-Snowflake app calls
`/api/v2/databases/.../agents/ENTERPRISE_AI_AGENT:run` via
`_snowflake.send_snow_api_request`, renders the answer, shows which tool
answered, and — for transparency/trust — expands the generated SQL or
document citations inline. Every question/answer is logged to
`AGENT_INTERACTION_LOG` (including 👍/👎 feedback), which feeds the
dashboard below.

**Snowflake Intelligence dashboards.** A second Streamlit page reads three
views: `VW_PORTFOLIO_RISK_DASHBOARD` (premium/loss-ratio/revenue-at-risk by
policy type and region), `VW_TREND_ANALYSIS` / `VW_CHURN_TREND`
(month-over-month claims, fraud, and churn), and
`VW_AGENT_ACCURACY_METRICS` (query volume and helpful-rate per tool, from
the interaction log above).

**MCP Integration.** `ENTERPRISE_AI_MCP_SERVER` (`CREATE MCP SERVER`)
exposes `ENTERPRISE_AI_AGENT` itself as a single `CORTEX_AGENT_RUN` MCP
tool, so any MCP-compatible client (tested live with Claude's Connectors
UI) gets the same fully-executed, orchestrated answers as the Streamlit
app — not just generated SQL — across all three capabilities.

## 4. Why this satisfies the judging criteria

- **Innovation** — a single governed agent spanning structured, unstructured,
  and meta (data-quality) data, rather than three disconnected demos.
- **Technical excellence** — uses Snowflake's newest native primitives
  (`SEMANTIC VIEW`, `CORTEX SEARCH SERVICE`, `AGENT`) instead of hand-rolled
  RAG/orchestration code; declarative, auditable, and cheap to maintain.
- **Business value** — collapses three specialist workflows (SQL analyst,
  document reviewer, DQ engineer) into one self-service chat experience.
- **UX** — one chat box; every answer is explainable (SQL shown, sources
  cited) so business users can trust and verify it.

## 5. Assumptions / open items

- `POLICY_DOCUMENTS.CONTENT_TEXT` already holds extracted text (not raw
  PDF/DOCX binaries) — if source documents are still binary, add a
  `SNOWFLAKE.CORTEX.PARSE_DOCUMENT` extraction step upstream of chunking.
- Warehouse referenced in the Cortex Search service (`COMPUTE_WH`) is
  confirmed against the live account (X-Small, `STARTED`).
- All `tool_resources` are currently `GRANT`ed to `ROLE PUBLIC` for demo
  simplicity — a production deployment would scope these to specific roles.

## 6. Resolved during build (previously open items)

- **Data-quality table columns**: `sql/04_data_quality_agent.sql` was
  originally a draft with guessed column names. All four `DATA_QUALITY`
  tables (`DQ_RULES`, `DQ_RESULTS`, `DQ_COLUMN_HEALTH`, `DQ_SCORES`) were
  confirmed directly against the live schema and sample data, and
  `DQ_SEMANTIC_VIEW` was corrected to match (e.g. `TARGET_TABLE`/
  `TARGET_COLUMN` instead of `TABLE_NAME`/`COLUMN_NAME` on `DQ_RESULTS`,
  `STATUS` instead of a boolean `PASS_FLAG`). Verified end-to-end with a
  live `SEMANTIC_VIEW()` query and through the deployed agent.
- **Document chunking gap**: the original chunking step only indexed
  `POLICY_DOCUMENTS.CONTENT_TEXT`, a one-line policy description —
  the actual exclusion-clause and coverage-limit text lived in separate
  `EXCLUSION_CLAUSES` / `COVERAGE_SUMMARY` columns that were never
  chunked, so DocumentQA could not have answered the README's own example
  question ("what are the exclusion clauses for water damage..."). Fixed
  by concatenating all three fields before chunking; verified the search
  service now returns real exclusion-clause text.
- **Agent warehouse configuration**: `cortex_analyst_text_to_sql` tools
  (`AnalyticsAgent`, `DataQualityAgent`) require an explicit execution
  warehouse, nested as `tool_resources.<name>.execution_environment: {
  type: warehouse, warehouse: <name>, query_timeout: <secs> }` — a flat
  `warehouse:` key is silently ignored by the agent runtime and produces a
  generic "missing an execution environment" error regardless of which
  tool is invoked. Fixed and confirmed live via `DESCRIBE AGENT` and a
  working end-to-end chat response.
- **MCP server access grants**: role `PUBLIC` initially had `USAGE` on the
  MCP server object, semantic views, search service, and warehouse, but not
  on the containing `DATABASE`/`SCHEMA`s — the MCP endpoint returned a
  generic "does not exist or not authorized" error that looked like a
  missing object rather than a missing grant. Fixed by adding the
  database/schema `USAGE` grants (see `sql/06_create_mcp_server.sql`).
- **External MCP client (OAuth) connectivity**: connecting a real external
  client (tested with Claude's Connectors UI) to `ENTERPRISE_AI_MCP_SERVER`
  surfaced two more issues, both now resolved and confirmed working
  end-to-end:
  1. Claude's connector requests `session:role:ALL` (every role the
     signing-in user holds, bundled together) rather than a single scoped
     role. Snowflake hard-blocks `ACCOUNTADMIN`/`SECURITYADMIN`/`ORGADMIN`/
     `GLOBALORGADMIN` from any custom OAuth integration with no override —
     so signing in as an admin user fails with "The role ALL requested has
     been explicitly blocked", even when `ALLOWED_ROLES_LIST` only names a
     safe role. Fix: create a dedicated Snowflake user holding *only* the
     scoped `MCP_CLAUDE_ROLE` (no admin roles at all) and sign in as that
     user instead.
  2. `ALLOWED_ROLES_LIST` cannot be combined with
     `OAUTH_USE_SECONDARY_ROLES = IMPLICIT` — use `NONE` with an explicit
     `ALLOWED_ROLES_LIST` instead.
  Verified live: the connector shows "Connected" with all three tools
  (Enterprise Analytics, Data Quality Root Cause, Policy Document Search)
  listed and callable from a real Claude chat. See the OAuth section of
  `sql/06_create_mcp_server.sql` for the exact working configuration.
- **Semantic view base-table access**: `GRANT SELECT ON SEMANTIC VIEW` does
  *not* implicitly grant access to the view's underlying base tables —
  Cortex Analyst's generated SQL runs with the calling role's own
  table-level privileges (invoker's rights), not the semantic view owner's.
  `MCP_CLAUDE_ROLE` had `SELECT` on `ANALYTICS_SEMANTIC_VIEW` but not on
  `CUSTOMERS`/`POLICIES`/`CLAIMS`/etc. directly, so a real question through
  the external Claude connector failed with a generic authorization error
  even though the semantic view grant looked sufficient. This only surfaces
  when testing as a non-admin role (every earlier test ran as
  `ACCOUNTADMIN`, which has implicit access to everything). Fixed by
  granting `SELECT` on all `ANALYTICS`/`DATA_QUALITY`/`DOCUMENTS` base
  tables directly to `MCP_CLAUDE_ROLE`.
- **MCP tool type doesn't execute SQL**: exposing `AnalyticsAgent`/
  `DataQualityAgent` as raw `CORTEX_ANALYST_MESSAGE` MCP tools only returns
  the interpreted question and generated SQL text — it does not execute
  that SQL or return row data. Confirmed live: a real question through
  Claude's Connectors UI got a SQL statement back and nothing else. Fixed
  by replacing all three granular tools with a single `CORTEX_AGENT_RUN`
  tool that proxies the already-working `ENTERPRISE_AI_AGENT` (the same
  object the Streamlit app calls), which does execute its SQL and returns
  full natural-language answers — one MCP tool now covers all three
  capabilities via the agent's own orchestration, matching the "Unified"
  framing even more directly. Verified end-to-end: a real loss-ratio
  question returned actual computed numbers, a chart spec, and analysis
  text, not just a query plan.
- **DQ Agent couldn't answer two of its own spec's example questions**: the
  authoritative requirement doc's Agent 3 example follow-ups include "which
  column caused the biggest score drop" and "is any downstream reporting
  impacted" — checked live against `DQ_COLUMN_HEALTH` and found it held
  exactly one snapshot date (28 rows, 2025-01-15), so there was no history to
  compute a "drop" from, and no lineage/downstream-dependency table existed
  anywhere in the account. Fixed in `sql/08_dq_agent_enhancements.sql`:
  backfilled two earlier `DQ_COLUMN_HEALTH` snapshots per column (derived
  proportionally from each column's existing status, not random — critical
  columns stay flat as long-standing issues, `CUSTOMERS.EMAIL` gets a
  deliberate fresh regression matching the agent's existing demo question),
  added a `VW_DQ_COLUMN_HEALTH_TRENDS` view (`LAG`/`FIRST_VALUE` per column)
  exposed to `DQ_SEMANTIC_VIEW` as `column_trends`, and added
  `DQ_DOWNSTREAM_IMPACT`, a lineage table mapping source table/column to the
  dashboards this repo actually ships, exposed as `downstream_impact`.
  Verified live via `SEMANTIC_VIEW()`: `CUSTOMERS.EMAIL` returns as the
  single biggest score drop (-11.0), and `CUSTOMERS` correctly returns
  "Portfolio & Risk Dashboard" and "Customer Outreach & Marketing Campaigns"
  as impacted downstream reports.
- **Tool names renamed to match the requirement doc exactly, but the runtime
  sanitizes them**: the tools were originally named `AnalyticsAgent`/
  `DocumentQA`/`DataQualityAgent` (compact identifiers). To match the
  authoritative requirement doc word-for-word, first confirmed live (via a
  disposable throwaway agent, dropped immediately after) that Cortex Agent's
  `tool_spec.name` field accepts spaces and punctuation, then renamed to
  `"Self-Service Analytics Agent"` / `"Document Q&A Agent"` / `"Data Quality
  Agent"` in `sql/03_create_unified_agent.sql` and redeployed. However, the
  agent runtime sanitizes the name in everything it actually returns
  (`tool_use.name`, `AGENT_INTERACTION_LOG.TOOL_NAME`, observability span
  names): spaces become `_` and `&` is dropped, so the values seen at runtime
  are `Self-Service_Analytics_Agent` / `Document_Q_A_Agent` /
  `Data_Quality_Agent` — confirmed by calling the live agent post-rename and
  inspecting both the direct API response and real
  `GET_AI_OBSERVABILITY_EVENTS` rows. Updated `streamlit/app.py`'s
  `TOOL_LABELS` and `sql/07_unified_agent_observability.sql`'s
  `REGEXP_SUBSTR` pattern to the sanitized identifiers, and backfilled the
  11 pre-existing `AGENT_INTERACTION_LOG` rows from the old names to the new
  ones so the usage/accuracy dashboard doesn't split history across a rename
  (see `sql/09_rename_agent_tools.sql`).
- **Grants don't survive `CREATE OR REPLACE MCP SERVER`**: unlike
  `CREATE OR REPLACE TABLE`, replacing an MCP server object drops and
  recreates it, silently clearing every existing `GRANT ... ON MCP SERVER`.
  Redeploying the server spec without re-running the grants produces the
  same "does not exist or not authorized" error as a missing grant, even
  though nothing about the calling role changed. All grants must be
  re-applied after any redeploy (see `sql/06_create_mcp_server.sql`).
