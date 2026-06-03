import os
import sqlite3
import pandas as pd

db_path = r"c:\Users\darwi\Downloads\sql_adv\quick_commerce.db"
csv_dir = r"c:\Users\darwi\Downloads\sql_adv"

# Connect to SQLite
print(f"Creating SQLite database for validation at: {db_path}")
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

files = {
    'stores': 'stores.csv',
    'products': 'products.csv',
    'customers': 'customers.csv',
    'promotions': 'promotions.csv',
    'inventory': 'inventory.csv',
    'orders': 'orders.csv',
    'order_items': 'order_items.csv'
}

# Create tables and load data using pandas
for table, filename in files.items():
    csv_path = os.path.join(csv_dir, filename)
    if not os.path.exists(csv_path):
        print(f"Error: {filename} not found!")
        continue
    
    print(f"Loading {filename} into table '{table}'...")
    # Read CSV in chunks to optimize memory footprint
    chunk_size = 100000
    first_chunk = True
    for chunk in pd.read_csv(csv_path, chunksize=chunk_size):
        # Clean columns to ensure compatibility
        chunk.to_sql(table, conn, if_exists='append' if not first_chunk else 'replace', index=False)
        first_chunk = False
        
    print(f"Successfully loaded '{table}' table.")

# Create indexes to speed up future analytical runs
print("Creating indexes...")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_orders_store ON orders(store_id);")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id);")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_inventory_store_product ON inventory(store_id, product_id);")
conn.commit()

# Validation Queries
print("\n=== Validation Results ===")

# 1. Fetch table names and row counts
cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
tables = [row[0] for row in cursor.fetchall()]

for t in tables:
    cursor.execute(f"SELECT COUNT(*) FROM {t};")
    count = cursor.fetchone()[0]
    print(f"Table: {t:12} | Row Count: {count:,}")

# 2. Database Schema preview
print("\n=== Database Schema ===")
for t in tables:
    print(f"\nSchema for table: {t}")
    cursor.execute(f"PRAGMA table_info({t});")
    for col in cursor.fetchall():
        print(f"  - Column ID: {col[0]} | Name: {col[1]:15} | Type: {col[2]}")

conn.close()
print("\nValidation complete. Database file ready.")
