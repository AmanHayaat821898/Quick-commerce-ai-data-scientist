import sqlite3

db_path = r"c:\Users\darwi\Downloads\sql_adv\quick_commerce.db"
# Open in read-only mode to prevent any locking issues
conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
cursor = conn.cursor()

# Set aggressive pragmas for speed
cursor.execute("PRAGMA cache_size = 200000;")
cursor.execute("PRAGMA temp_store = MEMORY;")
cursor.execute("PRAGMA synchronous = OFF;")

def run_query(title, query):
    print(f"\n=== {title} ===")
    cursor.execute(query)
    columns = [col[0] for col in cursor.description]
    rows = cursor.fetchall()
    
    header_str = " | ".join(f"{col:25}" for col in columns)
    print(header_str)
    print("-" * len(header_str))
    
    for row in rows:
        row_str = " | ".join(f"{str(val):25}" for val in row)
        print(row_str)

# 1. Total Revenue
run_query("Total Revenue (Delivered Orders)", 
          "SELECT SUM(total_amount) as total_revenue_usd, COUNT(order_id) as delivered_orders_count FROM orders WHERE status = 'delivered';")

# 2. Top Products by Revenue
run_query("Top 5 Products by Revenue", 
          """SELECT p.name, p.sku, SUM(oi.total_price) as revenue 
             FROM order_items oi 
             INDEXED BY idx_order_items_product
             JOIN products p ON oi.product_id = p.product_id 
             GROUP BY oi.product_id 
             ORDER BY revenue DESC 
             LIMIT 5;""")

# 3. Top Stores by Revenue
run_query("Top 5 Stores by Revenue", 
          """SELECT s.name, s.city, SUM(o.total_amount) as revenue 
             FROM orders o 
             INDEXED BY idx_orders_store
             JOIN stores s ON o.store_id = s.store_id 
             WHERE o.status = 'delivered' 
             GROUP BY o.store_id 
             ORDER BY revenue DESC 
             LIMIT 5;""")

# 4. Monthly Sales
run_query("Monthly Sales Volume and GMV", 
          """SELECT strftime('%Y-%m', created_at) as sales_month, 
                    SUM(total_amount) as monthly_gmv, 
                    COUNT(order_id) as orders_count 
             FROM orders 
             WHERE status = 'delivered' 
             GROUP BY sales_month 
             ORDER BY sales_month;""")

conn.close()
