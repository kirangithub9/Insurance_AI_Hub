-- ============================================================================
-- UNIFIED AGENT USAGE — ALL CHANNELS (Streamlit + MCP)
-- AGENT_INTERACTION_LOG (05_dashboards_and_agent_logging.sql) only captures
-- Streamlit traffic, since it's written by streamlit/app.py's own code path.
-- MCP calls (claude.ai connector, Cursor, etc.) never touch app.py, so they
-- were invisible to the "Agent Accuracy & Usage" dashboard tab.
--
-- Snowflake's native SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS captures
-- every call to the agent regardless of caller. Confirmed live against this
-- project's real traces:
--   - The chosen tool's literal name (AnalyticsAgent/DocumentQA/
--     DataQualityAgent) always appears as a suffix on a child span's name
--     (e.g. "SemanticContextTool_AnalyticsAgent", "CortexSearchService_
--     DocumentQA") -- regardless of prefix, so REGEXP_SUBSTR pulls it out
--     generically.
--   - RESOURCE_ATTRIBUTES:"snow.user.name" distinguishes CLAUDE_MCP_USER
--     (the dedicated MCP connector user, see 06_create_mcp_server.sql) from
--     every other caller, which for this project means Streamlit/Snowsight.
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
  SELECT
    TRACE:trace_id::STRING AS trace_id,
    REGEXP_SUBSTR(RECORD:name::STRING, 'AnalyticsAgent|DocumentQA|DataQualityAgent') AS tool_name
  FROM events
  WHERE REGEXP_SUBSTR(RECORD:name::STRING, 'AnalyticsAgent|DocumentQA|DataQualityAgent') IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY trace_id ORDER BY tool_name) = 1
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

-- Sanity checks
SELECT * FROM VW_AGENT_OBSERVABILITY_CALLS ORDER BY started_at DESC LIMIT 20;
SELECT * FROM VW_AGENT_CHANNEL_SPLIT ORDER BY channel, tool_name;
