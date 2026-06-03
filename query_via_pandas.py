import os
import pandas as pd

csv_dir = r"c:\Users\darwi\Downloads\sql_adv"

print("Loading datasets with Pandas for high-speed in-memory computation...")

# Load necessary dataframes
orders_df = pd.read_csv(os.path.join(csv_dir, 'orders.csv'))
order_items_df = pd.read_csv(os.path.join(csv_dir, 'order_items.csv'))
products_df = pd.read_csv(os.path.join(csv_dir, 'products.csv'))
stores_df = pd.read_csv(os.path.join(csv_dir, 'stores.csv'))

print("Computing metrics...")

# 1. Total Revenue
delivered_orders = orders_df[orders_df['status'] == 'delivered']
total_revenue = delivered_orders['total_amount'].sum()
delivered_count = len(delivered_orders)

print("\n=== Total Revenue (Delivered Orders) ===")
print(f"Total Revenue (USD)       : ${total_revenue:,.2f}")
print(f"Delivered Orders Count     : {delivered_count:,}")

# 2. Top Products by Revenue
# Group order items by product_id and calculate total revenue
top_product_rev = order_items_df.groupby('product_id')['total_price'].sum().reset_index()
top_product_rev = top_product_rev.sort_values(by='total_price', ascending=False).head(5)
# Merge with products info
top_products = top_product_rev.merge(products_df, on='product_id')

print("\n=== Top 5 Products by Revenue ===")
for idx, row in top_products.iterrows():
    print(f"Name: {row['name']:30} | SKU: {row['sku']:10} | Revenue: ${row['total_price']:,.2f}")

# 3. Top Stores by Revenue
top_store_rev = delivered_orders.groupby('store_id')['total_amount'].sum().reset_index()
top_store_rev = top_store_rev.sort_values(by='total_amount', ascending=False).head(5)
# Merge with stores info
top_stores = top_store_rev.merge(stores_df, on='store_id')

print("\n=== Top 5 Stores by Revenue ===")
for idx, row in top_stores.iterrows():
    print(f"Name: {row['name']:35} | City: {row['city']:10} | Revenue: ${row['total_amount']:,.2f}")

# 4. Monthly Sales (GMV and Count)
delivered_orders['sales_month'] = pd.to_datetime(delivered_orders['created_at']).dt.strftime('%Y-%m')
monthly_sales = delivered_orders.groupby('sales_month').agg(
    monthly_gmv=('total_amount', 'sum'),
    orders_count=('order_id', 'count')
).reset_index().sort_values(by='sales_month')

print("\n=== Monthly Sales Volume and GMV ===")
for idx, row in monthly_sales.iterrows():
    print(f"Month: {row['sales_month']} | GMV: ${row['monthly_gmv']:,.2f} | Orders Count: {row['orders_count']:,}")

print("\nAll computations complete.")
