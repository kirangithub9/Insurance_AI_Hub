-- ============================================================================
-- UNIFIED ENTERPRISE AI AGENTS PLATFORM
-- One Cortex Agent, three tools — this is literally the hackathon's "Unified"
-- framing: a single conversational entry point that routes each question to
-- the right underlying capability automatically.
--
--   Tool "AnalyticsAgent"   -> cortex_analyst_text_to_sql over ANALYTICS_SEMANTIC_VIEW
--   Tool "DocumentQA"       -> cortex_search over POLICY_DOCUMENT_SEARCH_SVC
--   Tool "DataQualityAgent" -> cortex_analyst_text_to_sql over a DQ semantic view
--                              (placeholder below — finish once DATA_QUALITY
--                              schema DDL is available; see 04_data_quality_agent.sql)
--
-- Run 01_create_semantic_view_analytics.sql and 02_document_search_agent2.sql
-- BEFORE this script.
-- ============================================================================

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA PUBLIC;

CREATE OR REPLACE AGENT ENTERPRISE_AI_AGENT
  COMMENT = 'Unified Enterprise AI Agents Platform: self-service analytics, document Q&A/RAG, and conversational data-quality root cause analysis in one agent.'
  PROFILE = '{"display_name": "Enterprise AI Agent", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  orchestration:
    tool_not_accessible: accept
    budget:
      seconds: 45
      tokens: 16000

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "AnalyticsAgent"
        description: "Answers natural-language questions about customers, policies, claims, billing, agents, and at-risk/churn data using structured SQL analytics. Use for anything involving counts, sums, averages, trends, loss ratio, premiums, fraud, or churn risk."
    - tool_spec:
        type: "cortex_search"
        name: "DocumentQA"
        description: "Searches and answers questions about the text of insurance policy documents, contracts, exclusion clauses, and coverage summaries. Use when the question is about what a specific policy document says, not about aggregate numbers."
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "DataQualityAgent"
        description: "Answers conversational root-cause questions about data quality rule failures, column health, and DQ scores across the platform's tables."

  tool_resources:
    AnalyticsAgent:
      semantic_view: "INSURANCE_AI_HUB.ANALYTICS.ANALYTICS_SEMANTIC_VIEW"
      warehouse: "COMPUTE_WH"
    DocumentQA:
      search_service: "INSURANCE_AI_HUB.DOCUMENTS.POLICY_DOCUMENT_SEARCH_SVC"
      max_results: "5"
      id_column: "CHUNK_ID"
      title_column: "DOCUMENT_TITLE"
    DataQualityAgent:
      semantic_view: "INSURANCE_AI_HUB.DATA_QUALITY.DQ_SEMANTIC_VIEW"
      warehouse: "COMPUTE_WH"
  $$;

-- Confirm it's registered
SHOW AGENTS IN SCHEMA INSURANCE_AI_HUB.PUBLIC;
DESCRIBE AGENT ENTERPRISE_AI_AGENT;

GRANT USAGE ON AGENT ENTERPRISE_AI_AGENT TO ROLE PUBLIC;
