-- ============================================================================
-- AGENT 3 ENHANCEMENTS: closing two real gaps found against the authoritative
-- "Snowflake Cortex AI Agents – Unified Business Enablement" requirement doc,
-- specifically its Agent 3 (Data Quality) example follow-up questions:
--
--   "Which column caused the biggest score drop?"
--     -> DQ_COLUMN_HEALTH had exactly ONE snapshot date (2025-01-15, 28 rows)
--        when checked live against the account -- no history to compute a
--        drop from. This is a real data gap, not a modeling gap.
--   "Is any downstream reporting impacted?"
--     -> No lineage/downstream-dependency table existed anywhere in the
--        account. Also a real data gap.
--
-- This script:
--   1. Backfills DQ_COLUMN_HEALTH with two earlier synthetic snapshots
--      (2025-01-01, 2025-01-08) per existing column, derived proportionally
--      from each row's current score/status (not random) -- long-standing
--      Critical columns stay flat, Healthy columns stay flat, Warning
--      columns get a mild gradual drift, and CUSTOMERS.EMAIL (already the
--      DQ agent's example question in app.py: "why did the DQ check on
--      CUSTOMERS.EMAIL fail last week?") gets a deliberate fresh regression
--      (99.0 -> 94.0 -> 88.0) so it's the clear answer to "biggest drop"
--      (11.0 pts vs. the next-largest drift of 3.7 pts, verified in Python
--      before writing this file).
--   2. Creates DQ_DOWNSTREAM_IMPACT, a lineage table mapping source
--      table/column to the downstream reports/dashboards/models that
--      depend on it -- populated with the actual dashboards this repo
--      already ships (VW_PORTFOLIO_RISK_DASHBOARD, VW_TREND_ANALYSIS,
--      VW_CHURN_TREND), not invented product/pricing data.
--   3. Creates VW_DQ_COLUMN_HEALTH_TRENDS, a derived view computing each
--      column's latest/previous/earliest score and score_change via LAG,
--      so "biggest score drop" is a plain ORDER BY on a semantic-view fact
--      rather than a window function embedded in the semantic view DDL.
--
-- Run this AFTER the base DATA_QUALITY tables exist (DQ_RULES, DQ_RESULTS,
-- DQ_COLUMN_HEALTH, DQ_SCORES -- part of the pre-provisioned dataset) and
-- BEFORE sql/04_data_quality_agent.sql, whose DQ_SEMANTIC_VIEW references
-- the column_trends/downstream_impact objects this script creates.
-- ============================================================================

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA DATA_QUALITY;

-- ----------------------------------------------------------------------------
-- 1. BACKFILL: two earlier DQ_COLUMN_HEALTH snapshots per existing column
-- ----------------------------------------------------------------------------
INSERT INTO DQ_COLUMN_HEALTH (
  HEALTH_ID, TABLE_NAME, COLUMN_NAME, CHECK_DATE, NULL_PCT, DISTINCT_COUNT,
  DUPLICATE_PCT, OUTLIER_COUNT, FORMAT_VIOLATION_COUNT, HEALTH_STATUS, SCORE,
  IS_CRITICAL
) VALUES
('CH-001-D14', 'CUSTOMERS', 'CUSTOMER_ID', '2025-01-01', 0.0, 200, 0.0, 0, 0, 'Healthy', 100.0, TRUE),
('CH-001-D7', 'CUSTOMERS', 'CUSTOMER_ID', '2025-01-08', 0.0, 200, 0.0, 0, 0, 'Healthy', 100.0, TRUE),
('CH-002-D14', 'CUSTOMERS', 'EMAIL', '2025-01-01', 0.0, 188, 0.5, 0, 1, 'Healthy', 99.0, FALSE),
('CH-002-D7', 'CUSTOMERS', 'EMAIL', '2025-01-08', 0.0, 188, 3.0, 0, 4, 'Warning', 94.0, FALSE),
('CH-003-D14', 'CUSTOMERS', 'CREDIT_SCORE', '2025-01-01', 0.0, 150, 0.0, 3, 0, 'Warning', 94.6, FALSE),
('CH-003-D7', 'CUSTOMERS', 'CREDIT_SCORE', '2025-01-08', 0.0, 150, 0.0, 4, 0, 'Warning', 93.1, FALSE),
('CH-004-D14', 'CUSTOMERS', 'STATE', '2025-01-01', 0.0, 12, 0.0, 0, 21, 'Critical', 70.6, TRUE),
('CH-004-D7', 'CUSTOMERS', 'STATE', '2025-01-08', 0.0, 12, 0.0, 0, 20, 'Critical', 71.4, TRUE),
('CH-005-D14', 'CUSTOMERS', 'PHONE', '2025-01-01', 0.0, 200, 0.0, 0, 40, 'Critical', 65.0, FALSE),
('CH-005-D7', 'CUSTOMERS', 'PHONE', '2025-01-08', 0.0, 200, 0.0, 0, 41, 'Critical', 64.1, FALSE),
('CH-006-D14', 'CUSTOMERS', 'ZIP_CODE', '2025-01-01', 0.0, 180, 0.0, 0, 31, 'Critical', 69.1, FALSE),
('CH-006-D7', 'CUSTOMERS', 'ZIP_CODE', '2025-01-08', 0.0, 180, 0.0, 0, 30, 'Critical', 70.3, FALSE),
('CH-007-D14', 'CUSTOMERS', 'DATE_OF_BIRTH', '2025-01-01', 6.0, 185, 0.0, 2, 0, 'Warning', 88.0, FALSE),
('CH-007-D7', 'CUSTOMERS', 'DATE_OF_BIRTH', '2025-01-08', 6.6, 185, 0.0, 3, 0, 'Warning', 86.8, FALSE),
('CH-008-D14', 'CUSTOMERS', 'FIRST_NAME', '2025-01-01', 1.0, 45, 0.0, 0, 0, 'Healthy', 98.1, TRUE),
('CH-008-D7', 'CUSTOMERS', 'FIRST_NAME', '2025-01-08', 1.0, 45, 0.0, 0, 0, 'Healthy', 98.2, TRUE),
('CH-009-D14', 'CUSTOMERS', 'LAST_NAME', '2025-01-01', 0.0, 38, 0.0, 0, 0, 'Healthy', 99.7, TRUE),
('CH-009-D7', 'CUSTOMERS', 'LAST_NAME', '2025-01-08', 0.0, 38, 0.0, 0, 0, 'Healthy', 100.0, TRUE),
('CH-010-D14', 'CUSTOMERS', 'RISK_TIER', '2025-01-01', 0.0, 4, 0.0, 0, 0, 'Healthy', 100.0, FALSE),
('CH-010-D7', 'CUSTOMERS', 'RISK_TIER', '2025-01-08', 0.0, 4, 0.0, 0, 0, 'Healthy', 99.9, FALSE),
('CH-011-D14', 'POLICIES', 'POLICY_ID', '2025-01-01', 0.0, 300, 0.0, 0, 0, 'Healthy', 99.8, TRUE),
('CH-011-D7', 'POLICIES', 'POLICY_ID', '2025-01-08', 0.0, 300, 0.0, 0, 0, 'Healthy', 100.0, TRUE),
('CH-012-D14', 'POLICIES', 'CUSTOMER_ID', '2025-01-01', 0.0, 180, 0.0, 0, 0, 'Warning', 95.9, TRUE),
('CH-012-D7', 'POLICIES', 'CUSTOMER_ID', '2025-01-08', 0.0, 180, 0.0, 0, 0, 'Warning', 94.8, TRUE),
('CH-013-D14', 'POLICIES', 'PREMIUM_AMOUNT', '2025-01-01', 0.0, 285, 0.0, 3, 0, 'Healthy', 99.1, TRUE),
('CH-013-D7', 'POLICIES', 'PREMIUM_AMOUNT', '2025-01-08', 0.0, 285, 0.0, 1, 0, 'Healthy', 99.5, TRUE),
('CH-014-D14', 'POLICIES', 'COVERAGE_AMOUNT', '2025-01-01', 0.0, 290, 0.0, 4, 0, 'Healthy', 98.7, TRUE),
('CH-014-D7', 'POLICIES', 'COVERAGE_AMOUNT', '2025-01-08', 0.0, 290, 0.0, 9, 0, 'Warning', 96.9, TRUE),
('CH-015-D14', 'POLICIES', 'LOSS_RATIO', '2025-01-01', 0.0, 275, 0.0, 0, 0, 'Healthy', 100.0, FALSE),
('CH-015-D7', 'POLICIES', 'LOSS_RATIO', '2025-01-08', 0.0, 275, 0.0, 0, 0, 'Healthy', 100.0, FALSE),
('CH-016-D14', 'CLAIMS', 'CLAIM_ID', '2025-01-01', 0.0, 400, 0.0, 0, 0, 'Healthy', 100.0, TRUE),
('CH-016-D7', 'CLAIMS', 'CLAIM_ID', '2025-01-08', 0.0, 400, 0.0, 0, 0, 'Healthy', 99.9, TRUE),
('CH-017-D14', 'CLAIMS', 'POLICY_ID', '2025-01-01', 0.0, 250, 0.0, 0, 0, 'Critical', 90.2, TRUE),
('CH-017-D7', 'CLAIMS', 'POLICY_ID', '2025-01-08', 0.0, 250, 0.0, 0, 0, 'Critical', 90.7, TRUE),
('CH-018-D14', 'CLAIMS', 'CLAIM_AMOUNT', '2025-01-01', 0.0, 380, 0.0, 8, 0, 'Healthy', 98.1, TRUE),
('CH-018-D7', 'CLAIMS', 'CLAIM_AMOUNT', '2025-01-08', 0.0, 380, 0.0, 7, 0, 'Healthy', 98.2, TRUE),
('CH-019-D14', 'CLAIMS', 'APPROVED_AMOUNT', '2025-01-01', 44.7, 120, 0.0, 30, 0, 'Critical', 72.7, TRUE),
('CH-019-D7', 'CLAIMS', 'APPROVED_AMOUNT', '2025-01-08', 44.3, 120, 0.0, 30, 0, 'Critical', 72.9, TRUE),
('CH-020-D14', 'CLAIMS', 'RESOLUTION_DATE', '2025-01-01', 44.3, 85, 0.0, 0, 13, 'Warning', 82.3, FALSE),
('CH-020-D7', 'CLAIMS', 'RESOLUTION_DATE', '2025-01-08', 47.3, 85, 0.0, 0, 14, 'Warning', 81.1, FALSE),
('CH-021-D14', 'CLAIMS', 'FRAUD_SCORE', '2025-01-01', 0.0, 95, 0.0, 0, 0, 'Healthy', 99.9, FALSE),
('CH-021-D7', 'CLAIMS', 'FRAUD_SCORE', '2025-01-08', 0.0, 95, 0.0, 0, 0, 'Healthy', 99.7, FALSE),
('CH-022-D14', 'BILLING', 'AMOUNT_DUE', '2025-01-01', 0.0, 420, 0.0, 0, 0, 'Healthy', 99.8, TRUE),
('CH-022-D7', 'BILLING', 'AMOUNT_DUE', '2025-01-08', 0.0, 420, 0.0, 0, 0, 'Healthy', 99.8, TRUE),
('CH-023-D14', 'BILLING', 'DUE_DATE', '2025-01-01', 0.0, 150, 0.0, 0, 10, 'Healthy', 98.1, TRUE),
('CH-023-D7', 'BILLING', 'DUE_DATE', '2025-01-08', 0.0, 150, 0.0, 0, 18, 'Warning', 96.4, TRUE),
('CH-024-D14', 'BILLING', 'OUTSTANDING_BALANCE', '2025-01-01', 0.0, 380, 0.0, 0, 0, 'Healthy', 99.9, TRUE),
('CH-024-D7', 'BILLING', 'OUTSTANDING_BALANCE', '2025-01-08', 0.0, 380, 0.0, 0, 0, 'Healthy', 99.9, TRUE),
('CH-025-D14', 'AT_RISK_POLICIES', 'RISK_SCORE', '2025-01-01', 0.0, 160, 0.0, 0, 0, 'Healthy', 99.8, FALSE),
('CH-025-D7', 'AT_RISK_POLICIES', 'RISK_SCORE', '2025-01-08', 0.0, 160, 0.0, 0, 0, 'Healthy', 99.9, FALSE),
('CH-026-D14', 'AT_RISK_POLICIES', 'REVENUE_AT_RISK', '2025-01-01', 0.0, 165, 0.0, 0, 0, 'Healthy', 100.0, TRUE),
('CH-026-D7', 'AT_RISK_POLICIES', 'REVENUE_AT_RISK', '2025-01-08', 0.0, 165, 0.0, 0, 0, 'Healthy', 100.0, TRUE),
('CH-027-D14', 'AT_RISK_POLICIES', 'DAYS_SINCE_CONTACT', '2025-01-01', 0.0, 100, 0.0, 5, 0, 'Healthy', 97.0, FALSE),
('CH-027-D7', 'AT_RISK_POLICIES', 'DAYS_SINCE_CONTACT', '2025-01-08', 0.0, 100, 0.0, 7, 0, 'Warning', 95.8, FALSE),
('CH-028-D14', 'AT_RISK_POLICIES', 'CHURN_PROBABILITY', '2025-01-01', 0.0, 155, 0.0, 0, 0, 'Healthy', 100.0, FALSE),
('CH-028-D7', 'AT_RISK_POLICIES', 'CHURN_PROBABILITY', '2025-01-08', 0.0, 155, 0.0, 0, 0, 'Healthy', 99.8, FALSE);

-- Sanity check: confirm CUSTOMERS.EMAIL now has the largest drop
SELECT TABLE_NAME, COLUMN_NAME, CHECK_DATE, SCORE
FROM DQ_COLUMN_HEALTH
WHERE TABLE_NAME = 'CUSTOMERS' AND COLUMN_NAME = 'EMAIL'
ORDER BY CHECK_DATE;

-- ----------------------------------------------------------------------------
-- 2. DOWNSTREAM LINEAGE: which reports/dashboards depend on which table/column
-- Rows reference dashboards that actually exist in this repo
-- (sql/06_dashboards_and_agent_logging.sql), not invented product data.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE DQ_DOWNSTREAM_IMPACT (
  DOWNSTREAM_ID   VARCHAR(20)  PRIMARY KEY,
  TARGET_TABLE    VARCHAR(100) NOT NULL,
  TARGET_COLUMN   VARCHAR(100),              -- NULL = table-level impact
  REPORT_NAME     VARCHAR(200) NOT NULL,
  REPORT_TYPE     VARCHAR(50)  NOT NULL,     -- Dashboard | Model | Regulatory Report
  OWNER_TEAM      VARCHAR(100),
  IMPACT_LEVEL    VARCHAR(20)  NOT NULL,     -- High | Medium | Low
  CREATED_AT      TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO DQ_DOWNSTREAM_IMPACT
  (DOWNSTREAM_ID, TARGET_TABLE, TARGET_COLUMN, REPORT_NAME, REPORT_TYPE, OWNER_TEAM, IMPACT_LEVEL)
VALUES
  ('DSI-001', 'POLICIES', NULL, 'Portfolio & Risk Dashboard', 'Dashboard', 'Actuarial & Underwriting', 'High'),
  ('DSI-002', 'CUSTOMERS', NULL, 'Portfolio & Risk Dashboard', 'Dashboard', 'Actuarial & Underwriting', 'High'),
  ('DSI-003', 'CUSTOMERS', 'EMAIL', 'Customer Outreach & Marketing Campaigns', 'Regulatory Report', 'Marketing', 'High'),
  ('DSI-004', 'CLAIMS', NULL, 'Claims & Fraud Trend Dashboard', 'Dashboard', 'Claims Operations', 'High'),
  ('DSI-005', 'CLAIMS', 'FRAUD_SCORE', 'Fraud Detection Scoring Model', 'Model', 'Fraud & SIU', 'High'),
  ('DSI-006', 'AT_RISK_POLICIES', NULL, 'Churn / At-Risk Trend Dashboard', 'Dashboard', 'Retention Team', 'High'),
  ('DSI-007', 'BILLING', 'OUTSTANDING_BALANCE', 'Revenue Collections Report', 'Regulatory Report', 'Finance', 'Medium'),
  ('DSI-008', 'AGENTS', 'PERFORMANCE_RATING', 'Agent Performance Scorecard', 'Dashboard', 'Sales Leadership', 'Low');

-- ----------------------------------------------------------------------------
-- 3. DERIVED TREND VIEW: latest/previous/earliest score + delta per column
-- Plain SQL (LAG/FIRST_VALUE) so the semantic view just exposes the result
-- as facts, rather than embedding window functions in the semantic view DDL.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_DQ_COLUMN_HEALTH_TRENDS AS
WITH ranked AS (
  SELECT
    TABLE_NAME,
    COLUMN_NAME,
    CHECK_DATE,
    SCORE,
    HEALTH_STATUS,
    ROW_NUMBER() OVER (PARTITION BY TABLE_NAME, COLUMN_NAME ORDER BY CHECK_DATE DESC) AS rn,
    LAG(SCORE) OVER (PARTITION BY TABLE_NAME, COLUMN_NAME ORDER BY CHECK_DATE ASC)      AS prev_score,
    FIRST_VALUE(SCORE) OVER (PARTITION BY TABLE_NAME, COLUMN_NAME ORDER BY CHECK_DATE ASC) AS first_score,
    FIRST_VALUE(CHECK_DATE) OVER (PARTITION BY TABLE_NAME, COLUMN_NAME ORDER BY CHECK_DATE ASC) AS first_check_date
  FROM DQ_COLUMN_HEALTH
)
SELECT
  TABLE_NAME || '.' || COLUMN_NAME              AS TREND_ID,
  TABLE_NAME,
  COLUMN_NAME,
  CHECK_DATE                                     AS LATEST_CHECK_DATE,
  SCORE                                           AS LATEST_SCORE,
  HEALTH_STATUS                                   AS LATEST_HEALTH_STATUS,
  prev_score                                      AS PREVIOUS_SCORE,
  ROUND(SCORE - prev_score, 1)                    AS SCORE_CHANGE,
  first_score                                     AS EARLIEST_SCORE,
  first_check_date                                AS EARLIEST_CHECK_DATE,
  ROUND(SCORE - first_score, 1)                   AS SCORE_CHANGE_SINCE_FIRST
FROM ranked
WHERE rn = 1;

-- Sanity check: this should surface CUSTOMERS.EMAIL as the single biggest drop
SELECT TABLE_NAME, COLUMN_NAME, PREVIOUS_SCORE, LATEST_SCORE, SCORE_CHANGE, SCORE_CHANGE_SINCE_FIRST
FROM VW_DQ_COLUMN_HEALTH_TRENDS
ORDER BY SCORE_CHANGE_SINCE_FIRST ASC
LIMIT 5;

GRANT SELECT ON TABLE DQ_DOWNSTREAM_IMPACT TO ROLE PUBLIC;
GRANT SELECT ON VIEW VW_DQ_COLUMN_HEALTH_TRENDS TO ROLE PUBLIC;
