import streamlit as st
from db import run_query_df, get_connection

# Page Configuration
st.set_page_config(
    page_title="InstaAnalytics | Quick-Commerce Control Center",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Inject Premium Custom Styling
st.markdown("""
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap');
        html, body, [class*="css"] {
            font-family: 'Plus Jakarta Sans', sans-serif;
        }
        .header-container {
            background: linear-gradient(135deg, #FF4B4B 0%, #FF8F00 100%);
            padding: 2rem;
            border-radius: 16px;
            color: white;
            margin-bottom: 2rem;
            box-shadow: 0 10px 20px rgba(255, 75, 75, 0.15);
        }
        div[data-testid="stMetricValue"] {
            font-size: 2.2rem;
            font-weight: 700;
            color: #1E1E24;
        }
    </style>
""", unsafe_allow_html=True)

# Fetch connection info to show in sidebar
_, db_type = get_connection()

# Navigation Sidebar
st.sidebar.image("https://img.icons8.com/clouds/200/000000/lightning-bolt.png", width=100)
st.sidebar.title("InstaAnalytics")
st.sidebar.caption("Production Quick-Commerce Control Center")

st.sidebar.info(f"Database: **{db_type}**")

page = st.sidebar.radio(
    "Modules",
    ["Revenue Dashboard", "Customer Dashboard", "Inventory Dashboard"]
)

# Router
if page == "Revenue Dashboard":
    from views.revenue import show_revenue_dashboard
    show_revenue_dashboard(run_query_df)
elif page == "Customer Dashboard":
    from views.customers import show_customer_dashboard
    show_customer_dashboard(run_query_df)
elif page == "Inventory Dashboard":
    from views.inventory import show_inventory_dashboard
    show_inventory_dashboard(run_query_df)
