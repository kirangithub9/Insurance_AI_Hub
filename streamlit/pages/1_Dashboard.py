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

    st.markdown("#### Usage — all channels (Streamlit + MCP)")
    st.caption(
        "Sourced from Snowflake's native SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS — "
        "captures every call to ENTERPRISE_AI_AGENT regardless of caller, including "
        "questions asked through the MCP connector (claude.ai, Cursor, etc.), which "
        "AGENT_INTERACTION_LOG below never sees. Requires sql/07_unified_agent_observability.sql."
    )
    try:
        split = load("SELECT * FROM INSURANCE_AI_HUB.PUBLIC.VW_AGENT_CHANNEL_SPLIT")
        if split.empty:
            st.info("No observability events yet — ask the agent a few questions first (either channel).")
        else:
            total_all = int(split["QUERY_COUNT"].sum())
            mcp_total = int(split.loc[split["CHANNEL"] == "MCP", "QUERY_COUNT"].sum())
            direct_total = total_all - mcp_total

            c1, c2, c3 = st.columns(3)
            c1.metric("Total Queries (all channels)", total_all)
            c2.metric("via Streamlit/Direct", direct_total)
            c3.metric("via MCP", mcp_total)

            left, right = st.columns(2)
            with left:
                st.markdown("**Queries by tool (all channels)**")
                by_tool = split.groupby("TOOL_NAME")["QUERY_COUNT"].sum()
                st.bar_chart(by_tool)
            with right:
                st.markdown("**Queries by channel**")
                by_channel = split.groupby("CHANNEL")["QUERY_COUNT"].sum()
                st.bar_chart(by_channel)

            usage_all = load("SELECT * FROM INSURANCE_AI_HUB.PUBLIC.VW_AGENT_USAGE_ALL_CHANNELS ORDER BY DAY")
            if not usage_all.empty:
                st.markdown("**Query volume over time, by channel**")
                pivot_channel = usage_all.pivot_table(
                    index="DAY", columns="CHANNEL", values="QUERY_COUNT", aggfunc="sum"
                ).fillna(0)
                st.line_chart(pivot_channel)

            with st.expander("Raw channel-split data"):
                st.dataframe(split, use_container_width=True)
    except Exception as e:
        st.warning(
            f"Couldn't load unified observability metrics — has "
            f"sql/07_unified_agent_observability.sql been run, and does the role "
            f"running this app have SNOWFLAKE.CORTEX_USER + MONITOR on the agent? ({e})"
        )

    st.divider()
    st.markdown("#### Accuracy — Streamlit only")
    st.caption(
        "Sourced from AGENT_INTERACTION_LOG. Helpful-rate feedback (👍/👎) only exists "
        "for the Streamlit chat UI — the MCP connector has no feedback mechanism, so "
        "this section can't include MCP traffic."
    )
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
            c1.metric("Total Queries (Streamlit)", total_q)
            c2.metric("Feedback Given", total_rated)
            c3.metric("Helpful Rate", f"{overall_helpful:.0%}" if overall_helpful is not None else "—")

            left, right = st.columns(2)
            with left:
                st.markdown("**Queries by tool (Streamlit only)**")
                st.bar_chart(acc.set_index("TOOL_NAME")["TOTAL_QUERIES"])
            with right:
                st.markdown("**Helpful Rate by Tool**")
                feedback_display = acc.set_index("TOOL_NAME")[["THUMBS_UP", "THUMBS_DOWN"]].copy()
                feedback_display["HELPFUL_RATE"] = feedback_display.apply(
                    lambda r: f"👍 {int(r['THUMBS_UP'])}   👎 {int(r['THUMBS_DOWN'])}", axis=1
                )
                st.dataframe(feedback_display[["HELPFUL_RATE"]], use_container_width=True)
            usage = load("SELECT * FROM INSURANCE_AI_HUB.PUBLIC.VW_AGENT_USAGE_OVER_TIME ORDER BY DAY")
            if not usage.empty:
                st.markdown("**Query volume over time (Streamlit only)**")
                pivot = usage.pivot(index="DAY", columns="TOOL_NAME", values="QUERY_COUNT").fillna(0)
                st.line_chart(pivot)

            with st.expander("Raw accuracy data"):
                st.dataframe(acc, use_container_width=True)
    except Exception as e:
        st.warning(f"Couldn't load agent metrics — has sql/05_dashboards_and_agent_logging.sql been run? ({e})")
