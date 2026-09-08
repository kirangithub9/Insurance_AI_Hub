"""
Unified Enterprise AI Agents Platform — chat front end
Snowflake Hackathon (Capgemini x Snowflake)

Single chat UI that talks to the ENTERPRISE_AI_AGENT (Cortex Agent), which
internally routes each question to whichever tool fits:
  - Self-Service Analytics Agent -> Cortex Analyst semantic view (structured data)
  - Document Q&A Agent           -> Cortex Search service (policy documents / RAG)
  - Data Quality Agent           -> Cortex Analyst semantic view over DATA_QUALITY (root cause)

Tool names match the requirement doc word-for-word in sql/05_create_unified_agent.sql,
but the agent runtime sanitizes spaces/"&" to underscores in anything it actually
returns (tool_use.name, logs, traces) -- see TOOL_LABELS below, which maps those
sanitized identifiers back to the doc's exact display text.

Deploy this as a Streamlit-in-Snowflake app (Snowsight > Streamlit > + Streamlit App)
inside the INSURANCE_AI_HUB database / PUBLIC schema, on any warehouse.
"""

import json
import time
import uuid
import streamlit as st

st.set_page_config(page_title="Enterprise AI Agent", page_icon="🧠", layout="wide")

# ---------------------------------------------------------------------------
# Connection setup — works both inside Streamlit-in-Snowflake (SiS) and, for
# local development, against an external Snowflake connection defined in
# .streamlit/secrets.toml (see streamlit/secrets.toml.example in this repo).
# ---------------------------------------------------------------------------
IS_SIS = False
try:
    from snowflake.snowpark.context import get_active_session
    import _snowflake

    session = get_active_session()
    IS_SIS = True
except Exception:
    import requests
    from snowflake.snowpark import Session

    session = Session.builder.configs(st.secrets["connections"]["snowflake"]).create()
    conn = session._conn._conn
    HOST, TOKEN = conn.host, conn.rest.token

DB_NAME = "INSURANCE_AI_HUB"
SCHEMA_NAME = "PUBLIC"
AGENT_NAME = "ENTERPRISE_AI_AGENT"
AGENT_ENDPOINT = f"/api/v2/databases/{DB_NAME}/schemas/{SCHEMA_NAME}/agents/{AGENT_NAME}:run"

# Keys are the sanitized identifiers the agent runtime actually returns
# (spaces -> "_", "&" dropped) for tool_spec.name values that contain them --
# confirmed live against ENTERPRISE_AI_AGENT's real tool_use responses.
TOOL_LABELS = {
    "Self-Service_Analytics_Agent": "📊 Self-Service Analytics Agent",
    "Document_Q_A_Agent": "📄 Document Q&A Agent",
    "Data_Quality_Agent": "🛡️ Data Quality Agent",
}


def log_interaction(log_id: str, question: str, result: dict, latency_ms: int) -> None:
    """Write one row per question/answer to AGENT_INTERACTION_LOG for the
    Snowflake Intelligence usage/accuracy dashboard. Best-effort — a logging
    failure should never break the chat experience."""
    try:
        q = question.replace("'", "''")
        resp = (result.get("text") or "").replace("'", "''")[:15000]
        tool = result.get("tool_name") or "Unknown"
        had_sql = bool(result.get("sql"))
        had_citations = bool(result.get("citations"))
        session.sql(
            f"""
            INSERT INTO INSURANCE_AI_HUB.PUBLIC.AGENT_INTERACTION_LOG
              (LOG_ID, QUESTION, TOOL_NAME, RESPONSE_TEXT, HAD_SQL, HAD_CITATIONS, LATENCY_MS)
            VALUES
              ('{log_id}', '{q}', '{tool}', '{resp}', {had_sql}, {had_citations}, {latency_ms})
            """
        ).collect()
    except Exception:
        pass  # logging is best-effort; don't surface to the user


def record_feedback(log_id: str, helpful: bool) -> None:
    try:
        session.sql(
            f"""
            UPDATE INSURANCE_AI_HUB.PUBLIC.AGENT_INTERACTION_LOG
            SET HELPFUL_FLAG = {helpful}
            WHERE LOG_ID = '{log_id}'
            """
        ).collect()
    except Exception:
        pass


def call_agent(query: str) -> dict:
    """Call the ENTERPRISE_AI_AGENT and return parsed text/sql/citations."""
    payload = {
        "messages": [{"role": "user", "content": [{"type": "text", "text": query}]}],
        "stream": False,
    }

    result = {"text": "", "tool_name": None, "tool_type": None, "sql": None, "citations": []}

    try:
        if IS_SIS:
            resp = _snowflake.send_snow_api_request(
                "POST", AGENT_ENDPOINT, {}, {}, payload, None, 60000
            )
            status = resp.get("status", 200) if isinstance(resp, dict) else 200
            content = resp.get("content", "") if isinstance(resp, dict) else str(resp)
            if status >= 400:
                result["text"] = f"⚠️ Agent API error ({status}): {content}"
                return result
            body = json.loads(content) if isinstance(content, str) else content
        else:
            url = f"https://{HOST}{AGENT_ENDPOINT}"
            headers = {
                "Authorization": f'Snowflake Token="{TOKEN}"',
                "Content-Type": "application/json",
                "Accept": "application/json",
            }
            r = requests.post(url, headers=headers, json=payload, timeout=60)
            r.raise_for_status()
            body = r.json()

        # `body` is either a single response object (stream: false) or a list
        # of SSE-style events, depending on backend version — handle both.
        events = body if isinstance(body, list) else [{"event": "response", "data": body}]

        for event in events:
            event_type = event.get("event", "response")
            data = event.get("data", event)

            if event_type in ("response.text.delta",):
                result["text"] += data.get("text", "")
            elif event_type == "response.tool_use":
                result["tool_name"] = data.get("name")
                result["tool_type"] = data.get("type")
                if data.get("type") == "cortex_analyst_text_to_sql":
                    result["sql"] = data.get("input", {}).get("sql")
            elif event_type == "response":
                for item in data.get("content", []):
                    item_type = item.get("type")
                    if item_type == "text":
                        result["text"] += item.get("text", "")
                        for ann in item.get("annotations", []):
                            if ann.get("type") == "cortex_search_citation":
                                result["citations"].append(ann)
                    elif item_type == "tool_use":
                        # The tool's name/type live nested under "tool_use", not
                        # on the item itself (confirmed against the live API).
                        # A single question triggers several internal tool_use
                        # events in sequence (e.g. Self-Service_Analytics_Agent ->
                        # system_execute_sql -> server_skill -> data_to_chart);
                        # only the FIRST one is the actual named capability
                        # (Self-Service_Analytics_Agent/Document_Q_A_Agent/
                        # Data_Quality_Agent) we want to show as "via ...", so
                        # don't overwrite it once set.
                        tool_use = item.get("tool_use", {})
                        tu_name = tool_use.get("name")
                        tu_type = tool_use.get("type")
                        if tu_type == "system_execute_sql":
                            result["sql"] = tool_use.get("input", {}).get("sql")
                        elif tu_name and not result["tool_name"]:
                            result["tool_name"] = tu_name
                            result["tool_type"] = tu_type

    except Exception as e:
        result["text"] = f"⚠️ Error calling agent: {e}"

    return result


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
st.title("🧠 Unified Enterprise AI Agent")
st.caption(
    "Ask about policies, claims, and billing in plain English, search policy "
    "documents, or ask why a data quality check failed — one chat box, three "
    "agents working behind the scenes."
)

with st.sidebar:
    st.subheader("Try asking")
    st.markdown(
        "- *What is our average loss ratio by policy type?*\n"
        "- *Which agents have the highest performance rating?*\n"
        "- *How much revenue is at risk from high-churn customers?*\n"
        "- *What are the exclusion clauses for water damage in policy POL-1023?*\n"
        "- *Why did the DQ check on CUSTOMERS.EMAIL fail last week?*\n"
        "- *Which column caused the biggest data quality score drop?*\n"
        "- *Is any downstream reporting impacted by the CUSTOMERS data quality issues?*"
    )
    if st.button("Clear conversation"):
        st.session_state.messages = []
        st.rerun()

st.session_state.setdefault("messages", [])

for i, msg in enumerate(st.session_state.messages):
    with st.chat_message(msg["role"]):
        if msg.get("tool_name"):
            st.caption(f"via {TOOL_LABELS.get(msg['tool_name'], msg['tool_name'])}")
        st.markdown(msg["content"])
        if msg.get("sql"):
            with st.expander("Generated SQL"):
                st.code(msg["sql"], language="sql")
        if msg.get("citations"):
            with st.expander(f"Sources ({len(msg['citations'])})"):
                for c in msg["citations"]:
                    st.markdown(f"- **{c.get('doc_title', 'Document')}**: {c.get('text', '')[:200]}...")
        if msg["role"] == "assistant" and msg.get("log_id"):
            fb_col1, fb_col2, _ = st.columns([1, 1, 8])
            if fb_col1.button("👍", key=f"up_{i}"):
                record_feedback(msg["log_id"], True)
                st.toast("Thanks for the feedback!")
            if fb_col2.button("👎", key=f"down_{i}"):
                record_feedback(msg["log_id"], False)
                st.toast("Thanks — this helps improve the accuracy metrics.")

user_input = st.chat_input("Ask a question about policies, claims, documents, or data quality...")

if user_input:
    with st.chat_message("user"):
        st.markdown(user_input)
    st.session_state.messages.append({"role": "user", "content": user_input})

    with st.chat_message("assistant"):
        with st.spinner("Thinking..."):
            start = time.time()
            result = call_agent(user_input)
            latency_ms = int((time.time() - start) * 1000)

        if result.get("tool_name"):
            st.caption(f"via {TOOL_LABELS.get(result['tool_name'], result['tool_name'])}")
        st.markdown(result["text"] or "_No response text returned._")
        if result.get("sql"):
            with st.expander("Generated SQL"):
                st.code(result["sql"], language="sql")
        if result.get("citations"):
            with st.expander(f"Sources ({len(result['citations'])})"):
                for c in result["citations"]:
                    st.markdown(f"- **{c.get('doc_title', 'Document')}**: {c.get('text', '')[:200]}...")

        log_id = str(uuid.uuid4())
        log_interaction(log_id, user_input, result, latency_ms)

    st.session_state.messages.append(
        {
            "role": "assistant",
            "content": result["text"],
            "tool_name": result.get("tool_name"),
            "sql": result.get("sql"),
            "citations": result.get("citations"),
            "log_id": log_id,
        }
    )
