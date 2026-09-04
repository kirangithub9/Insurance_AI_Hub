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

      - title: "Data Quality Root Cause"
        name: "data_quality_agent"
        type: "CORTEX_ANALYST_MESSAGE"
        identifier: "INSURANCE_AI_HUB.DATA_QUALITY.DQ_SEMANTIC_VIEW"
        description: "Conversational root-cause analysis over data quality rules, results, and column health."
  $$;

SHOW MCP SERVERS IN SCHEMA INSURANCE_AI_HUB.PUBLIC;
DESCRIBE MCP SERVER ENTERPRISE_AI_MCP_SERVER;

-- ----------------------------------------------------------------------------
-- Access for a role that will connect an external MCP client (e.g. Claude,
-- Cursor). Adjust MCP_ACCESS_ROLE / warehouse to match your setup.
--
-- NOTE: USAGE on the MCP server / semantic views / search service alone is
-- NOT enough -- the calling role also needs USAGE on the DATABASE and every
-- SCHEMA in the path, or the endpoint returns a generic "does not exist or
-- not authorized" error that looks like a missing object, not a missing
-- grant. Confirmed by testing directly against the live endpoint.
-- ----------------------------------------------------------------------------
GRANT USAGE ON DATABASE INSURANCE_AI_HUB TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA INSURANCE_AI_HUB.PUBLIC TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA INSURANCE_AI_HUB.ANALYTICS TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA INSURANCE_AI_HUB.DOCUMENTS TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA INSURANCE_AI_HUB.DATA_QUALITY TO ROLE PUBLIC;
GRANT USAGE ON MCP SERVER ENTERPRISE_AI_MCP_SERVER TO ROLE PUBLIC;
GRANT SELECT ON SEMANTIC VIEW INSURANCE_AI_HUB.ANALYTICS.ANALYTICS_SEMANTIC_VIEW TO ROLE PUBLIC;
GRANT USAGE ON CORTEX SEARCH SERVICE INSURANCE_AI_HUB.DOCUMENTS.POLICY_DOCUMENT_SEARCH_SVC TO ROLE PUBLIC;
GRANT SELECT ON SEMANTIC VIEW INSURANCE_AI_HUB.DATA_QUALITY.DQ_SEMANTIC_VIEW TO ROLE PUBLIC;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE PUBLIC;

-- ----------------------------------------------------------------------------
-- QUICK SMOKE TEST (no OAuth needed): a Programmatic Access Token (PAT) works
-- as a bearer credential against the MCP endpoint, which is enough to prove
-- the server responds without wiring up a real external client. Verified
-- working end-to-end (tools/list + tools/call) against this exact server.
--
--   ALTER USER <your_user> ADD PROGRAMMATIC ACCESS TOKEN mcp_demo_token
--     ROLE_RESTRICTION = 'PUBLIC' DAYS_TO_EXPIRY = 1;
--   -- copy the returned token_secret, then:
--   curl -X POST "https://<account>.snowflakecomputing.com/api/v2/databases/INSURANCE_AI_HUB/schemas/PUBLIC/mcp-servers/ENTERPRISE_AI_MCP_SERVER" \
--     -H "Content-Type: application/json" -H "Accept: application/json" \
--     -H "Authorization: Bearer <token_secret>" \
--     -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
--   -- clean up afterwards:
--   ALTER USER <your_user> REMOVE PROGRAMMATIC ACCESS TOKEN mcp_demo_token;
--
-- OAuth is only required for a pre-built client's interactive sign-in flow
-- (Claude's Connectors UI, Cursor's "Sign in" button) -- those expect a
-- browser-based auth handshake rather than a token pasted into config.
-- This is the minimum security integration for that case; skip it if you're
-- only proving the server works via the PAT test above.
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
