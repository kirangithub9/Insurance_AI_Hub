# Unified Enterprise AI Agents Platform

**Snowflake x Capgemini Hackathon — Challenge 6: Unified Enterprise AI Agents Platform**
*AI-Powered Self-Service Analytics, Document Intelligence & Data Trust*

A single conversational agent — built entirely on Snowflake Cortex — that lets
business users ask natural-language questions across three domains without
writing SQL, using a BI tool, or filing a ticket with a data team:

Tool names match the authoritative requirement doc ("Snowflake Cortex AI
Agents – Unified Business Enablement") word-for-word:

| Tool | Powered by | Answers questions like |
|---|---|---|
| **Self-Service Analytics Agent** | Cortex Analyst (semantic view) | "What's our average loss ratio by policy type?" |
| **Document Q&A Agent** | Cortex Search (RAG) | "What are the exclusion clauses for water damage in policy POL-1023?" |
| **Data Quality Agent** | Cortex Analyst (semantic view) | "Why did the DQ check on CUSTOMERS.EMAIL fail last week?" |

All three are exposed as **tools of one Cortex Agent** (`ENTERPRISE_AI_AGENT`),
which is the point of the "Unified" framing — one chat box, automatic routing
to whichever capability the question actually needs.

## Repo structure

```
semantic_model/
  01_create_semantic_view_analytics.sql   Agent 1 — structured data semantic view
sql/
  02_document_search_agent2.sql           Agent 2 — chunking + Cortex Search service
  03_create_unified_agent.sql             Wires Agent 1 + 2 (+ 3) into ENTERPRISE_AI_AGENT
  04_data_quality_agent.sql               Agent 3 — DQ semantic view + agent tool update
  05_dashboards_and_agent_logging.sql     Snowflake Intelligence dashboards + interaction log
  06_create_mcp_server.sql                MCP Integration — exposes tools as an MCP server
  07_unified_agent_observability.sql      Unified usage view (Streamlit + MCP) via native AI Observability
  08_dq_agent_enhancements.sql            DQ_COLUMN_HEALTH history backfill + DQ_DOWNSTREAM_IMPACT lineage table, closing two Agent 3 example-question gaps found against the authoritative requirement doc
  09_rename_agent_tools.sql               Renames tool_spec.name to the requirement doc's exact wording and backfills historical AGENT_INTERACTION_LOG rows to match
  10_reset_observability_baseline.sql     Resets the "Usage — all channels" dashboard counters by adding a cutoff to VW_AGENT_OBSERVABILITY_CALLS (re-run with a fresh MAX(TIMESTAMP) baseline any time, e.g. before a demo)
streamlit/
  app.py                                  Chat UI (Streamlit-in-Snowflake), logs every interaction
  pages/1_Dashboard.py                    Portfolio/risk, trend, and agent-accuracy dashboard
  environment.yml                         SiS package spec
  secrets.toml.example                    Local-dev-only connection template
docs/
  ARCHITECTURE.md                         1-2 page architecture doc (submission requirement)
  DEMO_VIDEO_OUTLINE.md                   5-minute demo script
  REQUIREMENTS_MAPPING.md                 Maps the challenge doc's technical requirements to what's built, and calls out the copy-paste retail-boilerplate line items
```

## Setup (run in order)

1. Confirm `INSURANCE_AI_HUB.ANALYTICS`, `.DOCUMENTS`, and `.DATA_QUALITY` tables
   are created and loaded (already done for this project).
2. Run `semantic_model/01_create_semantic_view_analytics.sql` in a Snowflake
   worksheet — creates `ANALYTICS_SEMANTIC_VIEW`.
3. Run `sql/02_document_search_agent2.sql` — chunks `POLICY_DOCUMENTS.CONTENT_TEXT`
   into `DOCUMENT_CHUNKS` and creates the `POLICY_DOCUMENT_SEARCH_SVC` Cortex
   Search service.
4. Run `sql/08_dq_agent_enhancements.sql`, then `sql/04_data_quality_agent.sql`
   — 08 backfills DQ_COLUMN_HEALTH history and creates DQ_DOWNSTREAM_IMPACT
   (needed for the "biggest score drop" / "downstream reporting impacted"
   questions), then 04 creates the DQ semantic view referencing both.
5. Run `sql/03_create_unified_agent.sql` — creates `ENTERPRISE_AI_AGENT` with
   all three tools wired up, then `sql/09_rename_agent_tools.sql` if you have
   pre-existing `AGENT_INTERACTION_LOG` rows from an older tool-naming scheme.
6. Run `sql/05_dashboards_and_agent_logging.sql` — creates the portfolio/risk,
   trend, and agent-accuracy views plus the `AGENT_INTERACTION_LOG` table the
   dashboard reads from.
7. Run `sql/06_create_mcp_server.sql` — creates `ENTERPRISE_AI_MCP_SERVER`
   (MCP Integration requirement).
8. Run `sql/07_unified_agent_observability.sql` — creates `VW_AGENT_OBSERVABILITY_CALLS`,
   `VW_AGENT_USAGE_ALL_CHANNELS`, and `VW_AGENT_CHANNEL_SPLIT`, which read Snowflake's
   native `SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS` so the dashboard can show usage
   from MCP callers too, not just Streamlit. The role running the Streamlit app needs
   `GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER` and `GRANT MONITOR ON AGENT
   ENTERPRISE_AI_AGENT` first (see comment at the top of that file).
9. In Snowsight: **Streamlit > + Streamlit App**, point it at `streamlit/app.py`
   (with `streamlit/pages/1_Dashboard.py` alongside it for the multipage
   dashboard) inside `INSURANCE_AI_HUB.PUBLIC`, attach `environment.yml`, and run.
   Ask it a few questions first so the dashboard's "Agent Accuracy & Usage"
   tab has data to show.

## Judging criteria mapping

- **Innovation (30%)** — one unified agent auto-routing across structured SQL,
  unstructured RAG, and conversational data-quality root-cause analysis,
  rather than three separate bolt-on tools.
- **Technical Excellence (25%)** — native Snowflake `SEMANTIC VIEW` and
  `CORTEX SEARCH SERVICE` objects (no external vector DB or orchestration
  layer), automatic embedding generation, agent-level tool orchestration.
- **Business Value (25%)** — removes SQL/BI-tool dependency for business
  users; reduces time-to-answer for document lookups and DQ root-cause
  investigations from hours to seconds.
- **User Experience (20%)** — single chat interface, transparent generated
  SQL and document citations shown inline for trust/auditability, plus
  👍/👎 feedback that feeds the accuracy dashboard.

**Note on the challenge doc's technical requirements list**: the "Product
matching agent / Price optimization agent / Market intelligence agent /
Competitive pricing dashboard / Matching accuracy metrics" bullet points are
identical, word-for-word, across all six use cases in the hackathon doc —
they're retail-specific boilerplate that doesn't apply here (no product
catalog or competitor pricing exists in this schema). We implemented the
*category headings* (Cortex Agents, Snowflake Intelligence, MCP Integration)
against what this use case actually needs instead. See
`docs/REQUIREMENTS_MAPPING.md` for the full item-by-item mapping — worth
having ready if a judge asks about it.

See `docs/ARCHITECTURE.md` for the full write-up and `docs/DEMO_VIDEO_OUTLINE.md`
for the demo script.
