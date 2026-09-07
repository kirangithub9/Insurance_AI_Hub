-- ============================================================================
-- UNIFIED ENTERPRISE AI AGENTS PLATFORM
-- One Cortex Agent, three tools — this is literally the hackathon's "Unified"
-- framing: a single conversational entry point that routes each question to
-- the right underlying capability automatically.
--
-- Tool names match the authoritative requirement doc ("Snowflake Cortex AI
-- Agents – Unified Business Enablement") word-for-word — confirmed live that
-- Cortex Agent tool_spec.name accepts spaces/punctuation before committing
-- to this rename (see docs/ARCHITECTURE.md "Resolved during build").
--
--   Tool "Self-Service Analytics Agent" -> cortex_analyst_text_to_sql over ANALYTICS_SEMANTIC_VIEW
--   Tool "Document Q&A Agent"           -> cortex_search over POLICY_DOCUMENT_SEARCH_SVC
--   Tool "Data Quality Agent"           -> cortex_analyst_text_to_sql over DQ_SEMANTIC_VIEW
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
        name: "Self-Service Analytics Agent"
        description: "Answers natural-language questions about customers, policies, claims, billing, agents, and at-risk/churn data using structured SQL analytics. Use for anything involving counts, sums, averages, trends, loss ratio, premiums, fraud, or churn risk."
    - tool_spec:
        type: "cortex_search"
        name: "Document Q&A Agent"
        description: "Searches and answers questions about the text of insurance policy documents, contracts, exclusion clauses, and coverage summaries. Use when the question is about what a specific policy document says, not about aggregate numbers."
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "Data Quality Agent"
        description: "Answers conversational root-cause questions about data quality rule failures, column health, score trends, and downstream reporting impact across the platform's tables."

  tool_resources:
    "Self-Service Analytics Agent":
      semantic_view: "INSURANCE_AI_HUB.ANALYTICS.ANALYTICS_SEMANTIC_VIEW"
      execution_environment:
        type: warehouse
        warehouse: COMPUTE_WH
        query_timeout: 60
    "Document Q&A Agent":
      search_service: "INSURANCE_AI_HUB.DOCUMENTS.POLICY_DOCUMENT_SEARCH_SVC"
      max_results: "5"
      id_column: "CHUNK_ID"
      title_column: "DOCUMENT_TITLE"
    "Data Quality Agent":
      semantic_view: "INSURANCE_AI_HUB.DATA_QUALITY.DQ_SEMANTIC_VIEW"
      execution_environment:
        type: warehouse
        warehouse: COMPUTE_WH
        query_timeout: 60
  $$;

-- Confirm it's registered
SHOW AGENTS IN SCHEMA INSURANCE_AI_HUB.PUBLIC;
DESCRIBE AGENT ENTERPRISE_AI_AGENT;

GRANT USAGE ON AGENT ENTERPRISE_AI_AGENT TO ROLE PUBLIC;
