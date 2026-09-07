-- ============================================================================
-- RESET THE "AGENT ACCURACY & USAGE" DASHBOARD'S OBSERVABILITY BASELINE
--
-- The "Usage — all channels" tab (sql/07_unified_agent_observability.sql)
-- reads Snowflake's native SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS,
-- which is Snowflake-managed system telemetry -- there is no DELETE/TRUNCATE
-- available on it (unlike AGENT_INTERACTION_LOG, which we own and already
-- cleared). It was showing "3" queries that were direct API test calls made
-- while verifying the tool rename (sql/09_rename_agent_tools.sql), not real
-- demo/chat activity, and those will sit in the trace history regardless of
-- what we do to our own tables.
--
-- Since VW_AGENT_OBSERVABILITY_CALLS is a view we own, we can't erase the
-- underlying trace rows, but we can change what the view surfaces: add a
-- baseline cutoff so only events from this reset point forward are counted.
-- Genuine future usage (Streamlit chat, MCP callers) is unaffected -- this
-- only hides the pre-reset test traffic.
--
-- Re-run this script (with a fresh baseline -- see STEP 1) any time you
-- want to reset the "Usage — all channels" counters again, e.g. right
-- before a demo.
--
-- GOTCHA: CURRENT_TIMESTAMP()::TIMESTAMP_NTZ does NOT convert to UTC -- it
-- keeps the session's local wall-clock value (this account's session
-- timezone defaults to America/Los_Angeles) as a naive timestamp, while
-- GET_AI_OBSERVABILITY_EVENTS.TIMESTAMP is UTC-naive. A first attempt at
-- this reset used CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as the cutoff and it
-- silently failed to hide anything -- 06:45 PDT-labeled-as-naive sorted
-- *before* the 13:00 UTC-naive event rows, so the ">=" filter passed every
-- existing row through instead of excluding it. Fixed by using
-- MAX(TIMESTAMP) read directly from the events table function itself
-- (STEP 1 below) as the cutoff, which is guaranteed to be in the same
-- reference frame as the column being filtered.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- STEP 1: capture the current high-water mark from the events source itself
-- (NOT CURRENT_TIMESTAMP() -- see GOTCHA above) and paste it into STEP 2's
-- WHERE clause below before running.
-- ----------------------------------------------------------------------------
-- SELECT MAX(TIMESTAMP) FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
--   'INSURANCE_AI_HUB', 'PUBLIC', 'ENTERPRISE_AI_AGENT', 'CORTEX AGENT'
-- ));

-- ----------------------------------------------------------------------------
-- STEP 2: redeploy the view with that value (+ a 1-second buffer) as the cutoff
-- ----------------------------------------------------------------------------

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA PUBLIC;

CREATE OR REPLACE VIEW VW_AGENT_OBSERVABILITY_CALLS AS
WITH events AS (
  SELECT *
  FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'INSURANCE_AI_HUB', 'PUBLIC', 'ENTERPRISE_AI_AGENT', 'CORTEX AGENT'
  ))
  WHERE TIMESTAMP >= '2026-09-07 13:01:44'::TIMESTAMP_NTZ  -- baseline reset: MAX(TIMESTAMP) + 1s as of this reset, hides pre-existing test traffic
),
tool_spans AS (
  SELECT
    TRACE:trace_id::STRING AS trace_id,
    REGEXP_SUBSTR(RECORD:name::STRING, 'Self-Service_Analytics_Agent|Document_Q_A_Agent|Data_Quality_Agent') AS tool_name
  FROM events
  WHERE REGEXP_SUBSTR(RECORD:name::STRING, 'Self-Service_Analytics_Agent|Document_Q_A_Agent|Data_Quality_Agent') IS NOT NULL
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

-- Sanity check: should be empty immediately after reset
SELECT * FROM VW_AGENT_OBSERVABILITY_CALLS ORDER BY started_at DESC LIMIT 20;
SELECT * FROM VW_AGENT_CHANNEL_SPLIT ORDER BY channel, tool_name;
