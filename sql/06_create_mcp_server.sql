-- ============================================================================
-- MCP INTEGRATION
-- Exposes the platform's semantic views / search service as an MCP server,
-- so any MCP-compatible client (Claude, Cursor, etc.) can query the same
-- data the chat app uses — this is the genuine "applicable" MCP integration
-- for this use case (not the retail-boilerplate line item in the doc).
-- ============================================================================

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA PUBLIC;

CREATE OR REPLACE MCP SERVER ENTERPRISE_AI_MCP_SERVER
  FROM SPECIFICATION $$
    tools:
      - title: "Enterprise Analytics"
        name: "analytics_agent"
        type: "CORTEX_ANALYST_MESSAGE"
        identifier: "INSURANCE_AI_HUB.ANALYTICS.ANALYTICS_SEMANTIC_VIEW"
        description: "Natural-language SQL analytics over customers, policies, claims, billing, agents, and at-risk/churn data."

      - title: "Policy Document Search"
        name: "document_qa"
        type: "CORTEX_SEARCH_SERVICE_QUERY"
        identifier: "INSURANCE_AI_HUB.DOCUMENTS.POLICY_DOCUMENT_SEARCH_SVC"
        description: "Semantic search over insurance policy documents, contracts, and exclusion clauses."

      # - title: "Data Quality Root Cause"
      #   name: "data_quality_agent"
      #   type: "CORTEX_ANALYST_MESSAGE"
      #   identifier: "INSURANCE_AI_HUB.DATA_QUALITY.DQ_SEMANTIC_VIEW"
      #   description: "Conversational root-cause analysis over data quality rules, results, and column health."
  $$;

SHOW MCP SERVERS IN SCHEMA INSURANCE_AI_HUB.PUBLIC;
DESCRIBE MCP SERVER ENTERPRISE_AI_MCP_SERVER;

-- ----------------------------------------------------------------------------
-- Access for a role that will connect an external MCP client (e.g. Claude,
-- Cursor). Adjust MCP_ACCESS_ROLE / warehouse to match your setup.
-- ----------------------------------------------------------------------------
GRANT USAGE ON MCP SERVER ENTERPRISE_AI_MCP_SERVER TO ROLE PUBLIC;
GRANT SELECT ON SEMANTIC VIEW INSURANCE_AI_HUB.ANALYTICS.ANALYTICS_SEMANTIC_VIEW TO ROLE PUBLIC;
GRANT USAGE ON CORTEX SEARCH SERVICE INSURANCE_AI_HUB.DOCUMENTS.POLICY_DOCUMENT_SEARCH_SVC TO ROLE PUBLIC;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE PUBLIC;

-- ----------------------------------------------------------------------------
-- OAuth is required for an EXTERNAL MCP client to connect (Snowflake-managed
-- MCP servers use OAuth 2.0, not a plain password/PAT). This is the minimum
-- security integration for Snowflake's own OAuth provider; skip this whole
-- block if you're only demoing the MCP server's existence via SHOW/DESCRIBE
-- and not actually connecting an external client during the demo.
-- ----------------------------------------------------------------------------
-- CREATE SECURITY INTEGRATION MCP_OAUTH_INTEGRATION
--   TYPE = OAUTH
--   OAUTH_CLIENT = CUSTOM
--   OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
--   ENABLED = TRUE
--   OAUTH_REDIRECT_URI = 'https://<your-mcp-client-redirect-uri>'
--   OAUTH_USE_SECONDARY_ROLES = NONE
--   ALLOWED_ROLES_LIST = ('PUBLIC');
--
-- SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('MCP_OAUTH_INTEGRATION');
--
-- Client (e.g. Cursor) config once you have the client id/secret:
-- {
--   "mcpServers": {
--     "enterprise_ai": {
--       "url": "https://<your_account_url>/api/v2/databases/INSURANCE_AI_HUB/schemas/PUBLIC/mcp-servers/ENTERPRISE_AI_MCP_SERVER",
--       "auth": { "CLIENT_ID": "<client_id>", "CLIENT_SECRET": "<client_secret>" }
--     }
--   }
-- }
