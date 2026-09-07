-- ============================================================================
-- RENAME AGENT TOOLS TO MATCH THE REQUIREMENT DOC EXACTLY
--
-- sql/03_create_unified_agent.sql's tool_spec.name values were renamed from
-- compact identifiers (AnalyticsAgent/DocumentQA/DataQualityAgent) to the
-- authoritative requirement doc's exact wording ("Self-Service Analytics
-- Agent" / "Document Q&A Agent" / "Data Quality Agent").
--
-- The agent runtime sanitizes that name in everything it actually returns
-- (tool_use.name, observability spans): spaces -> "_", "&" dropped. So the
-- values that appear at runtime -- and that streamlit/app.py writes into
-- AGENT_INTERACTION_LOG.TOOL_NAME -- are:
--   Self-Service_Analytics_Agent | Document_Q_A_Agent | Data_Quality_Agent
-- Confirmed live by calling the redeployed agent and inspecting both the
-- direct API response and GET_AI_OBSERVABILITY_EVENTS rows.
--
-- This script backfills the rows logged before the rename (old compact
-- names) to the new sanitized names, so VW_AGENT_ACCURACY_METRICS and
-- VW_AGENT_USAGE_OVER_TIME (sql/05_dashboards_and_agent_logging.sql) don't
-- silently split one tool's history across two TOOL_NAME values.
--
-- Run AFTER redeploying sql/03_create_unified_agent.sql.
-- ============================================================================

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA PUBLIC;

UPDATE AGENT_INTERACTION_LOG
SET TOOL_NAME = CASE TOOL_NAME
  WHEN 'AnalyticsAgent'   THEN 'Self-Service_Analytics_Agent'
  WHEN 'DocumentQA'       THEN 'Document_Q_A_Agent'
  WHEN 'DataQualityAgent' THEN 'Data_Quality_Agent'
  ELSE TOOL_NAME
END
WHERE TOOL_NAME IN ('AnalyticsAgent', 'DocumentQA', 'DataQualityAgent');

-- Sanity check: should show only the new sanitized names now
SELECT TOOL_NAME, COUNT(*) AS n
FROM AGENT_INTERACTION_LOG
GROUP BY TOOL_NAME
ORDER BY TOOL_NAME;
