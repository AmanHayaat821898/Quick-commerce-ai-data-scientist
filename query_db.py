import sqlite3

db_path = r"c:\Users\darwi\Downloads\sql_adv\quick_commerce.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Set optimization pragmas for lightning-fast queries
cursor.execute("PRAGMA cache_size = 100000;")
cursor.execute("PRAGMA journal_mode = OFF;")
cursor.execute("PRAGMA synchronous = OFF;")
cursor.execute("PRAGMA temp_store = MEMORY;")

def run_query(title, query):
    print(f"\n=== {title} ===")
    cursor.execute(query)
    columns = [col[0] for col in cursor.description]
    rows = cursor.fetchall()
    
    # Print header
    header_str = " | ".join(f"{col:25}" for col in columns)
    print(header_str)
    print("-" * len(header_str))
    
    # Print rows
    for row in rows:
        row_str = " | ".join(f"{str(val):25}" for val in row)
        print(row_str)

# 1. Total Revenue
run_query("Total Revenue (Delivered Orders)", 
          "SELECT SUM(total_amount) as total_revenue_usd, COUNT(order_id) as delivered_orders_count FROM orders WHERE status = 'delivered';")

# 2. Top Products (Optimized GROUP BY first, then JOIN)
run_query("Top 5 Products by Revenue", 
          """SELECT p.name, p.sku, t.revenue 
             FROM (
                 SELECT product_id, SUM(total_price) as revenue 
                 FROM order_items 
                 GROUP BY product_id
             ) t 
             JOIN products p ON t.product_id = p.product_id 
             ORDER BY t.revenue DESC 
             LIMIT 5;""")

# 3. Top Stores (Optimized GROUP BY first, then JOIN)
run_query("Top 5 Stores by Revenue", 
          """SELECT s.name, s.city, t.revenue 
             FROM (
                 SELECT store_id, SUM(total_amount) as revenue 
                 FROM orders 
                 WHERE status = 'delivered' 
                 GROUP BY store_id
             ) t 
             JOIN stores s ON t.store_id = s.store_id 
             ORDER BY t.revenue DESC 
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
