-- ============================================================================
-- FIX: multi-tool questions were silently attributed to only ONE tool
--
-- Found by comparing a real question ("What are the top friction points
-- causing claim delays in Q1?") against its own observability trace: the
-- agent genuinely invoked BOTH Document_Q_A_Agent (Cortex Search, for policy
-- document context) AND Self-Service_Analytics_Agent (structured claims
-- data) to answer it -- confirmed by replaying the exact question and
-- inspecting the raw tool_use sequence in the response. But:
--   - streamlit/app.py only ever kept the FIRST tool_use with a name and
--     silently dropped the rest, so the chat UI's "via ..." caption,
--     AGENT_INTERACTION_LOG.TOOL_NAME, and everything downstream of it only
--     ever recorded one tool per question.
--   - VW_AGENT_OBSERVABILITY_CALLS (sql/07/10) had the same problem from a
--     different angle: `QUALIFY ROW_NUMBER() OVER (PARTITION BY trace_id
--     ORDER BY tool_name) = 1` deliberately collapsed each trace down to
--     one (alphabetically-first) tool_name, discarding any others used in
--     that same call.
--
-- Fixed streamlit/app.py to collect every distinct named tool used (see
-- call_agent()) and store them comma-joined in TOOL_NAME. This script:
--   1. Widens AGENT_INTERACTION_LOG.TOOL_NAME (a 3-tool combination can
--      exceed the original VARCHAR(50)).
--   2. Redefines VW_AGENT_ACCURACY_METRICS / VW_AGENT_USAGE_OVER_TIME to
--      split that comma-joined value and count each tool's participation
--      separately -- a multi-tool question now correctly contributes to
--      EVERY tool it used, not just one.
--   3. Redefines VW_AGENT_OBSERVABILITY_CALLS to stop collapsing to one
--      tool per trace (keeps the sql/10 reset-baseline cutoff).
--   4. Adds VW_AGENT_CALLS_SUMMARY: one row per actual call (not per tool),
--      for "Total Queries" / "Queries by channel" metrics that must NOT be
--      inflated by multi-tool questions -- a 2-tool question should count
--      as 1 call, even though it correctly contributes to 2 tools' totals
--      in the views above.
-- ============================================================================

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA PUBLIC;

-- ----------------------------------------------------------------------------
-- 1. Widen TOOL_NAME for comma-joined multi-tool values
-- ----------------------------------------------------------------------------
ALTER TABLE AGENT_INTERACTION_LOG ALTER COLUMN TOOL_NAME SET DATA TYPE VARCHAR(200);

-- ----------------------------------------------------------------------------
-- 2. Per-tool breakdown views: split TOOL_NAME, one row per tool used
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_AGENT_ACCURACY_METRICS AS
WITH exploded AS (
  SELECT
    l.LOG_ID,
    TRIM(t.value::STRING) AS TOOL_NAME,
    l.HELPFUL_FLAG,
    l.LATENCY_MS
  FROM AGENT_INTERACTION_LOG l,
       LATERAL FLATTEN(INPUT => SPLIT(l.TOOL_NAME, ',')) t
)
SELECT
  TOOL_NAME,
  COUNT(*)                                                        AS total_queries,
  COUNT_IF(HELPFUL_FLAG = TRUE)                                   AS thumbs_up,
  COUNT_IF(HELPFUL_FLAG = FALSE)                                  AS thumbs_down,
  COUNT_IF(HELPFUL_FLAG IS NOT NULL)                              AS total_rated,
  COUNT_IF(HELPFUL_FLAG = TRUE) / NULLIF(COUNT_IF(HELPFUL_FLAG IS NOT NULL), 0) AS helpful_rate,
  AVG(LATENCY_MS)                                                 AS avg_latency_ms
FROM exploded
GROUP BY TOOL_NAME;

CREATE OR REPLACE VIEW VW_AGENT_USAGE_OVER_TIME AS
WITH exploded AS (
  SELECT
    DATE_TRUNC('DAY', l.CREATED_AT)::DATE AS day,
    TRIM(t.value::STRING)                 AS TOOL_NAME
  FROM AGENT_INTERACTION_LOG l,
       LATERAL FLATTEN(INPUT => SPLIT(l.TOOL_NAME, ',')) t
)
SELECT day, TOOL_NAME, COUNT(*) AS query_count
FROM exploded
GROUP BY day, TOOL_NAME
ORDER BY day;

-- ----------------------------------------------------------------------------
-- 3. Observability view: stop collapsing multi-tool traces to one tool
--    (keeps the sql/10 reset-baseline cutoff -- update it here too if you
--    re-run sql/10 later to reset again)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_AGENT_OBSERVABILITY_CALLS AS
WITH events AS (
  SELECT *
  FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'INSURANCE_AI_HUB', 'PUBLIC', 'ENTERPRISE_AI_AGENT', 'CORTEX AGENT'
  ))
  WHERE TIMESTAMP >= '2026-09-07 13:01:44'::TIMESTAMP_NTZ  -- see sql/10_reset_observability_baseline.sql
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

-- VW_AGENT_USAGE_ALL_CHANNELS / VW_AGENT_CHANNEL_SPLIT (sql/07) are
-- unchanged -- they already GROUP BY tool_name, so they now correctly
-- reflect tool participation now that the source view emits one row per
-- (trace, tool) instead of collapsing to one.

-- ----------------------------------------------------------------------------
-- 4. True per-call totals, unaffected by how many tools a call used --
--    use this for "Total Queries" / "Queries by channel", NOT the
--    tool-exploded views above (which intentionally over-count relative to
--    call totals when a question used more than one tool).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_AGENT_CALLS_SUMMARY AS
SELECT DISTINCT trace_id, request_id, started_at, latency_ms, user_name, channel
FROM VW_AGENT_OBSERVABILITY_CALLS;

-- Sanity checks
SELECT * FROM VW_AGENT_OBSERVABILITY_CALLS ORDER BY started_at DESC LIMIT 20;
SELECT * FROM VW_AGENT_CALLS_SUMMARY ORDER BY started_at DESC LIMIT 20;
SELECT * FROM VW_AGENT_ACCURACY_METRICS;
