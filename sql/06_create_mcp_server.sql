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
-- Skip this whole block if you're only proving the server works via the PAT
-- test above.
--
-- CONFIRMED WORKING SETUP (tested end-to-end with Claude's Connectors UI):
--
-- 1. Do NOT point ALLOWED_ROLES_LIST at PUBLIC (or any role) while signing in
--    as a user that also holds ACCOUNTADMIN/SECURITYADMIN/ORGADMIN. Claude's
--    connector currently requests "session:role:ALL" (every role the signing-in
--    user holds, bundled together) rather than a single scoped role -- and
--    Snowflake hard-blocks ACCOUNTADMIN/SECURITYADMIN/ORGADMIN/GLOBALORGADMIN
--    from ANY custom OAuth integration, with no way to override it. If the
--    signing-in user holds one of those roles at all, the whole "ALL" bundle
--    gets rejected with "The role ALL requested has been explicitly blocked",
--    even though the specific role you wanted (e.g. PUBLIC) was never blocked.
--
-- 2. The fix: create a dedicated role AND a dedicated user that holds ONLY
--    that role (no admin roles at all), and sign in to the OAuth flow as that
--    user, not your own admin account.
--
-- ----------------------------------------------------------------------------

-- Dedicated role scoped to exactly what the MCP server's tools need
CREATE ROLE IF NOT EXISTS MCP_CLAUDE_ROLE;
GRANT USAGE ON DATABASE INSURANCE_AI_HUB TO ROLE MCP_CLAUDE_ROLE;
GRANT USAGE ON SCHEMA INSURANCE_AI_HUB.PUBLIC TO ROLE MCP_CLAUDE_ROLE;
GRANT USAGE ON SCHEMA INSURANCE_AI_HUB.ANALYTICS TO ROLE MCP_CLAUDE_ROLE;
GRANT USAGE ON SCHEMA INSURANCE_AI_HUB.DOCUMENTS TO ROLE MCP_CLAUDE_ROLE;
GRANT USAGE ON SCHEMA INSURANCE_AI_HUB.DATA_QUALITY TO ROLE MCP_CLAUDE_ROLE;
GRANT USAGE ON MCP SERVER ENTERPRISE_AI_MCP_SERVER TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON SEMANTIC VIEW INSURANCE_AI_HUB.ANALYTICS.ANALYTICS_SEMANTIC_VIEW TO ROLE MCP_CLAUDE_ROLE;
GRANT USAGE ON CORTEX SEARCH SERVICE INSURANCE_AI_HUB.DOCUMENTS.POLICY_DOCUMENT_SEARCH_SVC TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON SEMANTIC VIEW INSURANCE_AI_HUB.DATA_QUALITY.DQ_SEMANTIC_VIEW TO ROLE MCP_CLAUDE_ROLE;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE MCP_CLAUDE_ROLE;

-- IMPORTANT: SELECT on a SEMANTIC VIEW does NOT implicitly grant access to
-- its underlying base tables -- Cortex Analyst's generated SQL runs with the
-- CALLING role's own table-level privileges (invoker's rights), not the
-- semantic view owner's. Without these, a non-admin role's questions fail
-- with a generic authorization error even though SELECT on the semantic
-- view itself succeeded. This only surfaces when testing as a role other
-- than ACCOUNTADMIN (which has implicit access to everything) -- confirmed
-- by testing analytics_agent through a real external MCP client.
GRANT SELECT ON TABLE INSURANCE_AI_HUB.ANALYTICS.CUSTOMERS TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON TABLE INSURANCE_AI_HUB.ANALYTICS.POLICIES TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON TABLE INSURANCE_AI_HUB.ANALYTICS.CLAIMS TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON TABLE INSURANCE_AI_HUB.ANALYTICS.BILLING TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON TABLE INSURANCE_AI_HUB.ANALYTICS.AGENTS TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON TABLE INSURANCE_AI_HUB.ANALYTICS.AT_RISK_POLICIES TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON TABLE INSURANCE_AI_HUB.DATA_QUALITY.DQ_RULES TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON TABLE INSURANCE_AI_HUB.DATA_QUALITY.DQ_RESULTS TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON TABLE INSURANCE_AI_HUB.DATA_QUALITY.DQ_COLUMN_HEALTH TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON TABLE INSURANCE_AI_HUB.DATA_QUALITY.DQ_SCORES TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON TABLE INSURANCE_AI_HUB.DOCUMENTS.POLICY_DOCUMENTS TO ROLE MCP_CLAUDE_ROLE;
GRANT SELECT ON TABLE INSURANCE_AI_HUB.DOCUMENTS.DOCUMENT_CHUNKS TO ROLE MCP_CLAUDE_ROLE;

-- Dedicated user that holds ONLY MCP_CLAUDE_ROLE -- never grant this user
-- ACCOUNTADMIN or any other admin role, or the "ALL roles" block returns.
-- Set your own password below; do not commit a real one to source control.
-- CREATE USER IF NOT EXISTS CLAUDE_MCP_USER
--   PASSWORD = '<choose-a-strong-password-yourself>'
--   DEFAULT_ROLE = MCP_CLAUDE_ROLE
--   DEFAULT_WAREHOUSE = COMPUTE_WH
--   MUST_CHANGE_PASSWORD = FALSE;
-- GRANT ROLE MCP_CLAUDE_ROLE TO USER CLAUDE_MCP_USER;

CREATE OR REPLACE SECURITY INTEGRATION CLAUDE_MCP_INTEGRATION
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  ENABLED = TRUE
  OAUTH_REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback'
  OAUTH_USE_SECONDARY_ROLES = NONE
  ALLOWED_ROLES_LIST = ('MCP_CLAUDE_ROLE');

-- Run this once to get the client id/secret Claude's connector setup asks for
-- (shown once per rotation -- store it somewhere safe, not in this file):
-- SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('CLAUDE_MCP_INTEGRATION');

-- Claude connector setup (claude.ai -> Settings -> Connectors -> Add custom
-- connector):
--   Name:                 Insurance AI Hub
--   Remote MCP server URL: https://<account>.snowflakecomputing.com/api/v2/databases/INSURANCE_AI_HUB/schemas/PUBLIC/mcp-servers/ENTERPRISE_AI_MCP_SERVER
--   Client ID:             <OAUTH_CLIENT_ID from SYSTEM$SHOW_OAUTH_CLIENT_SECRETS>
--   Client Secret:         <OAUTH_CLIENT_SECRET from SYSTEM$SHOW_OAUTH_CLIENT_SECRETS>
-- On connect, Claude opens Snowflake's login page -- sign in as CLAUDE_MCP_USER
-- (NOT your own admin account), approve the consent screen, and the
-- connector shows the three tools (Enterprise Analytics, Data Quality Root
-- Cause, Policy Document Search) as "Connected".

-- Same client id/secret also work for Cursor's mcp.json:
-- {
--   "mcpServers": {
--     "enterprise_ai": {
--       "url": "https://<your_account_url>/api/v2/databases/INSURANCE_AI_HUB/schemas/PUBLIC/mcp-servers/ENTERPRISE_AI_MCP_SERVER",
--       "auth": { "CLIENT_ID": "<client_id>", "CLIENT_SECRET": "<client_secret>" }
--     }
--   }
-- }
