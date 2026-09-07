-- ============================================================================
-- SNOWFLAKE INTELLIGENCE: DASHBOARDS
-- Domain-translated equivalents of the doc's retail-boilerplate requirement
-- ("competitive pricing dashboard / market trend analysis / matching
-- accuracy metrics") — there's no product catalog or competitor pricing in
-- this schema, so these are the insurance/enterprise-ops equivalents:
--   1. Portfolio & risk dashboard   (~ "competitive pricing dashboard")
--   2. Trend analysis               (~ "market trend analysis")
--   3. Agent accuracy/usage metrics (~ "matching accuracy metrics")
-- ============================================================================

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA ANALYTICS;

-- ----------------------------------------------------------------------------
-- 1. PORTFOLIO & RISK DASHBOARD
-- Premium, loss ratio, claims, and revenue-at-risk sliced by the dimensions
-- a business user actually cares about.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_PORTFOLIO_RISK_DASHBOARD AS
SELECT
  p.POLICY_TYPE,
  p.PLAN_TIER,
  a.REGION,
  COUNT(DISTINCT p.POLICY_ID)                          AS policy_count,
  SUM(p.PREMIUM_AMOUNT)                                AS total_premium,
  AVG(p.LOSS_RATIO)                                     AS avg_loss_ratio,
  COUNT(DISTINCT c.CLAIM_ID)                            AS claim_count,
  SUM(c.CLAIM_AMOUNT)                                   AS total_claim_amount,
  SUM(IFF(c.FRAUD_FLAG, 1, 0))                          AS fraud_claim_count,
  COALESCE(SUM(ar.REVENUE_AT_RISK), 0)                  AS total_revenue_at_risk,
  AVG(ar.CHURN_PROBABILITY)                             AS avg_churn_probability
FROM POLICIES p
LEFT JOIN AGENTS a           ON p.AGENT_ID = a.AGENT_ID
LEFT JOIN CLAIMS c           ON c.POLICY_ID = p.POLICY_ID
LEFT JOIN AT_RISK_POLICIES ar ON ar.POLICY_ID = p.POLICY_ID
GROUP BY p.POLICY_TYPE, p.PLAN_TIER, a.REGION;

-- ----------------------------------------------------------------------------
-- 2. TREND ANALYSIS
-- Month-over-month view of claims volume, fraud rate, and new at-risk
-- policies, so trend direction is visible at a glance.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_TREND_ANALYSIS AS
SELECT
  DATE_TRUNC('MONTH', c.CLAIM_DATE)::DATE               AS month,
  COUNT(DISTINCT c.CLAIM_ID)                            AS claim_count,
  SUM(c.CLAIM_AMOUNT)                                   AS total_claim_amount,
  AVG(c.CLAIM_AMOUNT)                                   AS avg_claim_amount,
  SUM(IFF(c.FRAUD_FLAG, 1, 0))                          AS fraud_claim_count,
  AVG(c.FRAUD_SCORE)                                    AS avg_fraud_score,
  AVG(c.DAYS_TO_RESOLVE)                                AS avg_days_to_resolve
FROM CLAIMS c
WHERE c.CLAIM_DATE IS NOT NULL
GROUP BY DATE_TRUNC('MONTH', c.CLAIM_DATE)
ORDER BY month;

CREATE OR REPLACE VIEW VW_CHURN_TREND AS
SELECT
  DATE_TRUNC('MONTH', ar.IDENTIFIED_DATE)::DATE         AS month,
  COUNT(DISTINCT ar.RISK_ID)                            AS new_at_risk_policies,
  SUM(ar.REVENUE_AT_RISK)                               AS revenue_at_risk,
  AVG(ar.CHURN_PROBABILITY)                             AS avg_churn_probability
FROM AT_RISK_POLICIES ar
WHERE ar.IDENTIFIED_DATE IS NOT NULL
GROUP BY DATE_TRUNC('MONTH', ar.IDENTIFIED_DATE)
ORDER BY month;

-- ----------------------------------------------------------------------------
-- 3. AGENT ACCURACY / USAGE METRICS
-- This needs an interaction log the Streamlit app writes to on every
-- question, so we have something to measure. Table + view below; the
-- updated streamlit/app.py inserts into this table after every agent call
-- and after the user clicks a 👍/👎 feedback button.
-- ----------------------------------------------------------------------------
USE SCHEMA PUBLIC;

CREATE TABLE IF NOT EXISTS AGENT_INTERACTION_LOG (
  LOG_ID          VARCHAR(36)      DEFAULT UUID_STRING(),
  QUESTION        VARCHAR(2000),
  TOOL_NAME       VARCHAR(50),      -- Self-Service_Analytics_Agent | Document_Q_A_Agent | Data_Quality_Agent (sanitized tool_spec.name -- see sql/03_create_unified_agent.sql)
  RESPONSE_TEXT   VARCHAR(16777216),
  HAD_SQL         BOOLEAN DEFAULT FALSE,
  HAD_CITATIONS   BOOLEAN DEFAULT FALSE,
  HELPFUL_FLAG    BOOLEAN,          -- NULL = no feedback given, TRUE = 👍, FALSE = 👎
  LATENCY_MS      NUMBER(10,0),
  CREATED_AT      TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (LOG_ID)
);

CREATE OR REPLACE VIEW VW_AGENT_ACCURACY_METRICS AS
SELECT
  TOOL_NAME,
  COUNT(*)                                                        AS total_queries,
  COUNT_IF(HELPFUL_FLAG = TRUE)                                   AS thumbs_up,
  COUNT_IF(HELPFUL_FLAG = FALSE)                                  AS thumbs_down,
  COUNT_IF(HELPFUL_FLAG IS NOT NULL)                              AS total_rated,
  COUNT_IF(HELPFUL_FLAG = TRUE) / NULLIF(COUNT_IF(HELPFUL_FLAG IS NOT NULL), 0) AS helpful_rate,
  AVG(LATENCY_MS)                                                 AS avg_latency_ms
FROM AGENT_INTERACTION_LOG
GROUP BY TOOL_NAME;

CREATE OR REPLACE VIEW VW_AGENT_USAGE_OVER_TIME AS
SELECT
  DATE_TRUNC('DAY', CREATED_AT)::DATE AS day,
  TOOL_NAME,
  COUNT(*) AS query_count
FROM AGENT_INTERACTION_LOG
GROUP BY DATE_TRUNC('DAY', CREATED_AT), TOOL_NAME
ORDER BY day;

-- Sanity checks
SELECT * FROM ANALYTICS.VW_PORTFOLIO_RISK_DASHBOARD LIMIT 20;
SELECT * FROM ANALYTICS.VW_TREND_ANALYSIS LIMIT 20;
SELECT * FROM PUBLIC.VW_AGENT_ACCURACY_METRICS;
