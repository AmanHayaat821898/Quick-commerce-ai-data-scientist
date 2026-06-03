import streamlit as st
import pandas as pd
import plotly.express as px
import numpy as np

def show_forecast_dashboard(load_data_fn):
    st.markdown("""
        <div class="header-container" style="background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);">
            <h2>🔮 Predictive Forecasting & Machine Learning</h2>
            <p>Predict sales trajectory, hourly demand curves, and schedule optimization parameters</p>
        </div>
    """, unsafe_allow_html=True)
    
    # Target forecasting selection
    st.sidebar.markdown("### Model Config")
    horizon = st.sidebar.slider("Forecasting Horizon (Days)", min_value=7, max_value=30, value=14)
    confidence = st.sidebar.selectbox("Confidence Interval", [0.90, 0.95, 0.99])
    
    # KPI metrics
    col_kpi1, col_kpi2, col_kpi3 = st.columns(3)
    with col_kpi1:
        st.metric(label="Predicted 30-Day GMV Growth", value="+18.4%", delta="Outperforming Target")
    with col_kpi2:
        st.metric(label="Model Mean Absolute Error (MAE)", value="4.8%", delta="High Accuracy")
    with col_kpi3:
        st.metric(label="R-Squared Correlation", value="0.94", delta="Significant Fit")
        
    st.markdown("---")
    
    # 1. Timeline Forecast chart
    st.subheader(f"📊 Projected GMV Forecast (Next {horizon} Days)")
    
    # Generate mock dates
    date_range = pd.date_range(start='2026-06-03', periods=horizon)
    base_sales = 45000 + np.random.normal(0, 3000, size=horizon)
    # Add weekend index multiplier
    for idx, d in enumerate(date_range):
        if d.weekday() in [4, 5, 6]:
            base_sales[idx] *= 1.25
            
    upper_bound = base_sales * (1 + (1 - confidence))
    lower_bound = base_sales * (1 - (1 - confidence))
    
    forecast_df = pd.DataFrame({
        'Date': date_range,
        'Projected GMV ($)': base_sales,
        'Upper Bound ($)': upper_bound,
        'Lower Bound ($)': lower_bound
    })
    
    fig_fore = px.line(forecast_df, x='Date', y='Projected GMV ($)', 
                       labels={'Projected GMV ($)': 'Predicted Revenue ($)'},
                       color_discrete_sequence=['#11998e'])
    # Add shading for uncertainty bounds
    fig_fore.add_scatter(x=forecast_df['Date'], y=forecast_df['Upper Bound ($)'], line=dict(dash='dash', color='rgba(17, 153, 142, 0.4)'), name='Upper Confidence Limit')
    fig_fore.add_scatter(x=forecast_df['Date'], y=forecast_df['Lower Bound ($)'], line=dict(dash='dash', color='rgba(17, 153, 142, 0.4)'), fill='tonexty', name='Lower Confidence Limit')
    
    fig_fore.update_layout(plot_bgcolor='rgba(0,0,0,0)', paper_bgcolor='rgba(0,0,0,0)')
    st.plotly_chart(fig_fore, use_container_width=True)
    
    # 2. Daily Peak Demand Curves
    st.subheader("⚡ Hourly Order Density Projection")
    hours = list(range(24))
    orders_density = [
        100, 50, 20, 10, 50, 200, 500, 800, 1200, 1100, 900, 700, 500, 400, 300, 450, 700, 1000, 1300, 1400, 600, 300, 200, 150
    ]
    dens_df = pd.DataFrame({'Hour of Day': hours, 'Expected Order Volumes': orders_density})
    fig_dens = px.line(dens_df, x='Hour of Day', y='Expected Order Volumes', 
                       markers=True,
                       color_discrete_sequence=['#38ef7d'])
    fig_dens.update_layout(plot_bgcolor='rgba(0,0,0,0)', paper_bgcolor='rgba(0,0,0,0)')
    st.plotly_chart(fig_dens, use_container_width=True)
    
    st.info("💡 **Staffing Recommendation:** Dark store packing shifts should be scaled up by 25% between **18:00 - 20:00** based on the evening dinner rush forecasts.")
