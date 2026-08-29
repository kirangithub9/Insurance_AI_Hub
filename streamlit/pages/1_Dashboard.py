"""
Snowflake Intelligence dashboard page.

Domain-translated versions of the challenge doc's retail-boilerplate
requirement ("competitive pricing dashboard / market trend analysis /
matching accuracy metrics") — there's no product catalog or competitor
pricing in this schema, so this shows the insurance/enterprise-ops
equivalents instead: portfolio & risk, claims/churn trend, and agent
accuracy/usage (sourced from AGENT_INTERACTION_LOG, written by app.py).

Requires sql/05_dashboards_and_agent_logging.sql to have been run first.
"""

import streamlit as st

st.set_page_config(page_title="Dashboard", page_icon="📊", layout="wide")

try:
    from snowflake.snowpark.context import get_active_session

    session = get_active_session()
except Exception:
    st.error("This dashboard page must run inside Streamlit-in-Snowflake (or with a configured Snowpark session).")
    st.stop()


@st.cache_data(ttl=60)
def load(query: str):
    return session.sql(query).to_pandas()


st.title("📊 Enterprise AI Agent — Dashboard")
st.caption(
    "Portfolio & risk, trend analysis, and agent accuracy/usage — the "
    "insurance-domain equivalents of the challenge's pricing/trend/matching "
    "dashboard requirements."
)

tab1, tab2, tab3 = st.tabs(["Portfolio & Risk", "Trend Analysis", "Agent Accuracy & Usage"])

# ---------------------------------------------------------------------------
with tab1:
    st.subheader("Portfolio & Risk by Policy Type / Region")
    try:
        df = load("SELECT * FROM INSURANCE_AI_HUB.ANALYTICS.VW_PORTFOLIO_RISK_DASHBOARD")
        c1, c2, c3, c4 = st.columns(4)
        c1.metric("Total Premium", f"${df['TOTAL_PREMIUM'].sum():,.0f}")
        c2.metric("Avg Loss Ratio", f"{df['AVG_LOSS_RATIO'].mean():.2f}")
        c3.metric("Total Revenue at Risk", f"${df['TOTAL_REVENUE_AT_RISK'].sum():,.0f}")
        c4.metric("Fraud-Flagged Claims", f"{int(df['FRAUD_CLAIM_COUNT'].sum())}")

        left, right = st.columns(2)
        with left:
            st.markdown("**Total premium by policy type**")
            st.bar_chart(df.groupby("POLICY_TYPE")["TOTAL_PREMIUM"].sum())
        with right:
            st.markdown("**Avg loss ratio by policy type**")
            st.bar_chart(df.groupby("POLICY_TYPE")["AVG_LOSS_RATIO"].mean())

        st.markdown("**Revenue at risk by region**")
        st.bar_chart(df.groupby("REGION")["TOTAL_REVENUE_AT_RISK"].sum())

        with st.expander("Raw data"):
            st.dataframe(df, use_container_width=True)
    except Exception as e:
        st.warning(f"Couldn't load portfolio dashboard — has sql/05_dashboards_and_agent_logging.sql been run? ({e})")

# ---------------------------------------------------------------------------
with tab2:
    st.subheader("Claims & Fraud Trend")
    try:
        trend = load("SELECT * FROM INSURANCE_AI_HUB.ANALYTICS.VW_TREND_ANALYSIS ORDER BY MONTH")
        trend = trend.set_index("MONTH")
        left, right = st.columns(2)
        with left:
            st.markdown("**Claim count by month**")
            st.line_chart(trend["CLAIM_COUNT"])
        with right:
            st.markdown("**Fraud-flagged claims by month**")
            st.line_chart(trend["FRAUD_CLAIM_COUNT"])
        st.markdown("**Average claim resolution time (days) by month**")
        st.line_chart(trend["AVG_DAYS_TO_RESOLVE"])
    except Exception as e:
        st.warning(f"Couldn't load claims trend — ({e})")

    st.subheader("Churn / At-Risk Trend")
    try:
        churn = load("SELECT * FROM INSURANCE_AI_HUB.ANALYTICS.VW_CHURN_TREND ORDER BY MONTH")
        churn = churn.set_index("MONTH")
        left, right = st.columns(2)
        with left:
            st.markdown("**New at-risk policies by month**")
            st.line_chart(churn["NEW_AT_RISK_POLICIES"])
        with right:
            st.markdown("**Revenue at risk by month**")
            st.line_chart(churn["REVENUE_AT_RISK"])
    except Exception as e:
        st.warning(f"Couldn't load churn trend — ({e})")

# ---------------------------------------------------------------------------
with tab3:
    st.subheader("Agent Accuracy & Usage")
    st.caption("Sourced from AGENT_INTERACTION_LOG — populates as people use the chat app.")
    try:
        acc = load("SELECT * FROM INSURANCE_AI_HUB.PUBLIC.VW_AGENT_ACCURACY_METRICS")
        if acc.empty:
            st.info("No agent interactions logged yet — ask the chat app a few questions first.")
        else:
            total_q = int(acc["TOTAL_QUERIES"].sum())
            total_rated = int(acc["TOTAL_RATED"].sum())
            thumbs_up = int(acc["THUMBS_UP"].sum())
            overall_helpful = (thumbs_up / total_rated) if total_rated else None

            c1, c2, c3 = st.columns(3)
            c1.metric("Total Queries", total_q)
            c2.metric("Feedback Given", total_rated)
            c3.metric("Helpful Rate", f"{overall_helpful:.0%}" if overall_helpful is not None else "—")

            left, right = st.columns(2)
            with left:
                st.markdown("**Queries by tool**")
                st.bar_chart(acc.set_index("TOOL_NAME")["TOTAL_QUERIES"])
            with right:
                st.markdown("**Helpful rate by tool**")
                st.bar_chart(acc.set_index("TOOL_NAME")["HELPFUL_RATE"])

            usage = load("SELECT * FROM INSURANCE_AI_HUB.PUBLIC.VW_AGENT_USAGE_OVER_TIME ORDER BY DAY")
            if not usage.empty:
                st.markdown("**Query volume over time**")
                pivot = usage.pivot(index="DAY", columns="TOOL_NAME", values="QUERY_COUNT").fillna(0)
                st.line_chart(pivot)

            with st.expander("Raw accuracy data"):
                st.dataframe(acc, use_container_width=True)
    except Exception as e:
        st.warning(f"Couldn't load agent metrics — has sql/05_dashboards_and_agent_logging.sql been run? ({e})")
