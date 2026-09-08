-- ============================================================================
-- UNIFIED AGENT USAGE — ALL CHANNELS (Streamlit + MCP)
-- AGENT_INTERACTION_LOG (06_dashboards_and_agent_logging.sql) only captures
-- Streamlit traffic, since it's written by streamlit/app.py's own code path.
-- MCP calls (claude.ai connector, Cursor, etc.) never touch app.py, so they
-- were invisible to the "Agent Accuracy & Usage" dashboard tab.
--
-- Snowflake's native SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS captures
-- every call to the agent regardless of caller. Confirmed live against this
-- project's real traces:
--   - The tool_spec.name in 05_create_unified_agent.sql is the exact wording
--     from the requirement doc ("Self-Service Analytics Agent" / "Document
--     Q&A Agent" / "Data Quality Agent"), but the agent runtime SANITIZES it
--     for anything it actually returns (tool_use.name, span names, this
--     table): spaces become underscores and "&" is dropped, so the values
--     that actually appear are Self-Service_Analytics_Agent /
--     Document_Q_A_Agent / Data_Quality_Agent. Confirmed by calling the live
--     agent post-rename and inspecting real GET_AI_OBSERVABILITY_EVENTS rows
--     (e.g. "SemanticContextTool_Self-Service_Analytics_Agent",
--     "CortexSearchService_Document_Q_A_Agent") -- the sanitized name always
--     appears as a suffix on a child span's name regardless of prefix, so
--     REGEXP_SUBSTR pulls it out generically. streamlit/app.py's TOOL_LABELS
--     maps these sanitized identifiers back to the doc's exact display text.
--   - RESOURCE_ATTRIBUTES:"snow.user.name" distinguishes CLAUDE_MCP_USER
--     (the dedicated MCP connector user, see 07_create_mcp_server.sql) from
--     every other caller, which for this project means Streamlit/Snowsight.
--   - A single question can legitimately invoke more than one tool
--     (confirmed live: "What are the top friction points causing claim
--     delays in Q1?" used both Document_Q_A_Agent AND
--     Self-Service_Analytics_Agent) -- tool_spans below keeps one row per
--     (trace, tool) pair rather than collapsing to a single tool per trace,
--     so a multi-tool question correctly contributes to every tool it used.
--     VW_AGENT_CALLS_SUMMARY exists separately for metrics that must NOT be
--     inflated by that (e.g. "Total Queries" -- a 2-tool question is still
--     1 call, not 2).
-- ============================================================================

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA PUBLIC;

-- NOTE: querying this table function requires, on whichever role runs the
-- Streamlit app / worksheet:
--   GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE <that_role>;
--   GRANT MONITOR ON AGENT INSURANCE_AI_HUB.PUBLIC.ENTERPRISE_AI_AGENT TO ROLE <that_role>;

CREATE OR REPLACE VIEW VW_AGENT_OBSERVABILITY_CALLS AS
WITH events AS (
  SELECT *
  FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'INSURANCE_AI_HUB', 'PUBLIC', 'ENTERPRISE_AI_AGENT', 'CORTEX AGENT'
  ))
  WHERE TIMESTAMP >= DATEADD('day', -90, CURRENT_TIMESTAMP())
),
tool_spans AS (
  -- DISTINCT (trace_id, tool_name) pairs -- no QUALIFY/ROW_NUMBER collapse,
  -- so a trace that used N tools contributes N rows here.
  SELECT DISTINCT
    TRACE:trace_id::STRING AS trace_id,
    REGEXP_SUBSTR(RECORD:name::STRING, 'Self-Service_Analytics_Agent|Document_Q_A_Agent|Data_Quality_Agent') AS tool_name
  FROM events
  WHERE REGEXP_SUBSTR(RECORD:name::STRING, 'Self-Service_Analytics_Agent|Document_Q_A_Agent|Data_Quality_Agent') IS NOT NULL
),
trace_bounds AS (
  SELECT
    TRACE:trace_id::STRING                                     AS trace_id,
    MIN(START_TIMESTAMP)                                       AS started_at,
    MAX(TIMESTAMP)                                              AS ended_at,
    ANY_VALUE(RESOURCE_ATTRIBUTES:"snow.user.name"::STRING)     AS user_name,
    ANY_VALUE(RECORD_ATTRIBUTES:"request_id"::STRING)           AS request_id
  FROM events
  GROUP BY 1
)
SELECT
  b.trace_id,
  b.request_id,
  b.started_at,
  DATEDIFF('millisecond', b.started_at, b.ended_at)  AS latency_ms,
  b.user_name,
  IFF(b.user_name = 'CLAUDE_MCP_USER', 'MCP', 'Streamlit/Direct') AS channel,
  t.tool_name
FROM trace_bounds b
JOIN tool_spans t ON t.trace_id = b.trace_id;

-- Tool-participation counts: correct for "Queries by tool" breakdowns, but
-- will over-count relative to true call totals when a question used more
-- than one tool (by design -- see VW_AGENT_CALLS_SUMMARY below for totals).
CREATE OR REPLACE VIEW VW_AGENT_USAGE_ALL_CHANNELS AS
SELECT
  DATE_TRUNC('DAY', started_at)::DATE AS day,
  tool_name,
  channel,
  COUNT(*) AS query_count
FROM VW_AGENT_OBSERVABILITY_CALLS
GROUP BY 1, 2, 3
ORDER BY 1;

CREATE OR REPLACE VIEW VW_AGENT_CHANNEL_SPLIT AS
SELECT
  channel,
  tool_name,
  COUNT(*) AS query_count
FROM VW_AGENT_OBSERVABILITY_CALLS
GROUP BY 1, 2;

-- True per-call totals, unaffected by how many tools a call used -- use this
-- for "Total Queries" / "Queries by channel", NOT the tool-exploded views
-- above.
CREATE OR REPLACE VIEW VW_AGENT_CALLS_SUMMARY AS
SELECT DISTINCT trace_id, request_id, started_at, latency_ms, user_name, channel
FROM VW_AGENT_OBSERVABILITY_CALLS;

-- Sanity checks
SELECT * FROM VW_AGENT_OBSERVABILITY_CALLS ORDER BY started_at DESC LIMIT 20;
SELECT * FROM VW_AGENT_CALLS_SUMMARY ORDER BY started_at DESC LIMIT 20;
SELECT * FROM VW_AGENT_CHANNEL_SPLIT ORDER BY channel, tool_name;
