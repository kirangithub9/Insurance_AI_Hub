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
                         ┌─────────────────────────────┐
                         │   Streamlit-in-Snowflake     │
                         │        Chat UI (app.py)      │
                         └───────────────┬──────────────┘
                                         │ REST: agents/{name}:run
                                         ▼
                         ┌─────────────────────────────┐
                         │   ENTERPRISE_AI_AGENT         │
                         │   (Snowflake Cortex Agent)    │
                         │   auto-orchestration / routing│
                         └───┬─────────────┬────────────┘
              ┌──────────────┘             │             └──────────────┐
              ▼                            ▼                            ▼
   ┌────────────────────┐     ┌────────────────────────┐   ┌─────────────────────────┐
   │  AnalyticsAgent     │     │   DocumentQA             │   │  DataQualityAgent        │
   │  Cortex Analyst     │     │   Cortex Search Service  │   │  Cortex Analyst          │
   │  (text-to-SQL)      │     │   (RAG, auto-embeddings) │   │  (text-to-SQL)           │
   └─────────┬───────────┘     └───────────┬──────────────┘   └────────────┬─────────────┘
             ▼                             ▼                               ▼
   ANALYTICS_SEMANTIC_VIEW      POLICY_DOCUMENT_SEARCH_SVC        DQ_SEMANTIC_VIEW
   over ANALYTICS schema        over DOCUMENTS.DOCUMENT_CHUNKS    over DATA_QUALITY schema
   (CUSTOMERS, POLICIES,        (chunked from POLICY_DOCUMENTS    (DQ_RULES, DQ_RESULTS,
   CLAIMS, BILLING, AGENTS,     .CONTENT_TEXT via                 DQ_COLUMN_HEALTH, DQ_SCORES)
   AT_RISK_POLICIES)            SPLIT_TEXT_RECURSIVE_CHARACTER)
```

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
and `DQ_SCORES`, letting a business user ask "why did X fail" and get a
conversational, evidence-backed answer instead of opening a data-quality
dashboard.

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
exposes `ANALYTICS_SEMANTIC_VIEW` and `POLICY_DOCUMENT_SEARCH_SVC` as MCP
tools, so any MCP-compatible client can query the same data outside the
Streamlit app.

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
