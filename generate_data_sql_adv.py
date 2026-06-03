import os
import uuid
import random
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from faker import Faker

# Initialize Faker and seed for reproducibility
fake = Faker()
Faker.seed(42)
np.random.seed(42)

# Configuration
NUM_STORES = 100
NUM_PRODUCTS = 5000
NUM_CUSTOMERS = 100000
NUM_ORDERS = 1000000
DAYS_OF_DATA = 730 # 2 Years
START_DATE = datetime(2024, 6, 1)

output_dir = r"c:\Users\darwi\Downloads\sql_adv"
os.makedirs(output_dir, exist_ok=True)

print(f"Generating synthetic Quick-Commerce data in: {output_dir}")

# 1. Stores
store_ids = [str(uuid.uuid4()) for _ in range(NUM_STORES)]
stores_df = pd.DataFrame({
    'store_id': store_ids,
    'name': [f"Store - {fake.city()} Express" for _ in range(NUM_STORES)],
    'city': [random.choice(['Mumbai', 'Delhi', 'Bangalore', 'Hyderabad', 'Pune']) for _ in range(NUM_STORES)],
    'pincode': [fake.postcode() for _ in range(NUM_STORES)],
    'geohash': [''.join(random.choices('0123456789bcdefghjkmnpqrstuvwxyz', k=8)) for _ in range(NUM_STORES)],
    'is_active': [True] * NUM_STORES,
    'created_at': [START_DATE - timedelta(days=365) for _ in range(NUM_STORES)]
})
stores_df.to_csv(os.path.join(output_dir, 'stores.csv'), index=False)

# 2. Products
categories = {
    'Fresh Produce': ['Fruits', 'Vegetables', 'Herbs'],
    'Dairy & Eggs': ['Milk', 'Cheese', 'Butter', 'Yogurt', 'Eggs'],
    'Beverages': ['Soft Drinks', 'Juices', 'Energy Drinks', 'Water', 'Tea & Coffee'],
    'Bakery & Bread': ['Sliced Bread', 'Buns', 'Cakes', 'Cookies'],
    'Snacks & Munchies': ['Chips', 'Popcorn', 'Chocolates', 'Nuts'],
    'Instant Food': ['Noodles', 'Ready-to-eat', 'Pasta'],
    'Personal Care': ['Shampoo', 'Soap', 'Toothpaste', 'Deodorants'],
    'Home Care': ['Detergents', 'Dishwashers', 'Cleaners']
}

product_ids = [str(uuid.uuid4()) for _ in range(NUM_PRODUCTS)]
product_skus = [f"SKU-{i:05d}" for i in range(NUM_PRODUCTS)]
prod_cats = []
prod_subcats = []
prices = []
cost_prices = []
perishable = []

cat_keys = list(categories.keys())
for _ in range(NUM_PRODUCTS):
    cat = random.choice(cat_keys)
    sub = random.choice(categories[cat])
    cost = round(np.random.exponential(scale=80.0) + 10.0, 2)
    margin = np.random.uniform(0.15, 0.40)
    price = round(cost * (1 + margin), 2)
    
    prod_cats.append(cat)
    prod_subcats.append(sub)
    cost_prices.append(cost)
    prices.append(price)
    perishable.append(cat in ['Fresh Produce', 'Dairy & Eggs', 'Bakery & Bread'])

products_df = pd.DataFrame({
    'product_id': product_ids,
    'sku': product_skus,
    'name': [f"{fake.word().capitalize()} {prod_subcats[i]} {random.randint(100, 500)}g" for i in range(NUM_PRODUCTS)],
    'category': prod_cats,
    'sub_category': prod_subcats,
    'price': prices,
    'cost_price': cost_prices,
    'is_perishable': perishable,
    'created_at': [START_DATE - timedelta(days=365) for _ in range(NUM_PRODUCTS)]
})
products_df.to_csv(os.path.join(output_dir, 'products.csv'), index=False)

# 3. Customers
customer_ids = [str(uuid.uuid4()) for _ in range(NUM_CUSTOMERS)]
customers_df = pd.DataFrame({
    'customer_id': customer_ids,
    'phone_number': [fake.unique.phone_number()[:15] for _ in range(NUM_CUSTOMERS)],
    'email': [fake.unique.email() for _ in range(NUM_CUSTOMERS)],
    'first_name': [fake.first_name() for _ in range(NUM_CUSTOMERS)],
    'last_name': [fake.last_name() for _ in range(NUM_CUSTOMERS)],
    'customer_tier': np.random.choice(['bronze', 'silver', 'gold'], size=NUM_CUSTOMERS, p=[0.70, 0.20, 0.10]),
    'created_at': [START_DATE - timedelta(days=random.randint(1, 365)) for _ in range(NUM_CUSTOMERS)]
})
customers_df.to_csv(os.path.join(output_dir, 'customers.csv'), index=False)

# 4. Promotions
promotions_df = pd.DataFrame({
    'promotion_id': [str(uuid.uuid4()) for _ in range(5)],
    'code': ['WELCOME100', 'SAVE20', 'MONSOON50', 'FESTIVE10', 'FREESHIP'],
    'discount_type': ['flat_amount', 'percentage', 'percentage', 'percentage', 'free_delivery'],
    'discount_value': [100.0, 20.0, 50.0, 10.0, 0.0],
    'min_order_value': [499.0, 299.0, 399.0, 199.0, 150.0],
    'max_discount_limit': [100.0, 150.0, 80.0, 200.0, 0.0],
    'start_date': [START_DATE] * 5,
    'end_date': [START_DATE + timedelta(days=DAYS_OF_DATA)] * 5,
    'is_active': [True] * 5
})
promotions_df.to_csv(os.path.join(output_dir, 'promotions.csv'), index=False)

# 5. Inventory
inventory_records = []
for s_id in store_ids:
    stock = np.random.randint(0, 150, size=NUM_PRODUCTS)
    shortage_mask = np.random.rand(NUM_PRODUCTS) < 0.08
    stock[shortage_mask] = 0
    reorder = np.random.randint(5, 20, size=NUM_PRODUCTS)
    
    store_inv = pd.DataFrame({
        'inventory_id': [str(uuid.uuid4()) for _ in range(NUM_PRODUCTS)],
        'store_id': [s_id] * NUM_PRODUCTS,
        'product_id': product_ids,
        'stock_level': stock,
        'reorder_level': reorder,
        'last_updated': [START_DATE] * NUM_PRODUCTS
    })
    inventory_records.append(store_inv)

inventory_df = pd.concat(inventory_records)
inventory_df.to_csv(os.path.join(output_dir, 'inventory.csv'), index=False)
del inventory_records

# 6. Orders
dates = [START_DATE + timedelta(days=i) for i in range(DAYS_OF_DATA)]
date_weights = []
for d in dates:
    w = 1.0
    if d.weekday() in [4, 5, 6]: w *= 1.25
    if d.month in [7, 8, 10, 11, 12]: w *= 1.15
    elif d.month in [4, 5]: w *= 0.85
    if (d.month == 11 and 1 <= d.day <= 5) or (d.month == 12 and d.day >= 30) or (d.month == 1 and d.day == 1):
        w *= 2.30
    elif d.month == 3 and 15 <= d.day <= 20:
        w *= 1.80
    date_weights.append(w)

date_weights = np.array(date_weights)
date_probs = date_weights / date_weights.sum()

order_dates_idx = np.random.choice(len(dates), size=NUM_ORDERS, p=date_probs)
order_dates_base = [dates[idx] for idx in order_dates_idx]

hours = np.arange(24)
hour_probs = np.array([
    0.005, 0.002, 0.001, 0.001, 0.005, 0.020, 0.050, 0.080,
    0.110, 0.100, 0.080, 0.060, 0.040, 0.030, 0.020, 0.030,
    0.050, 0.080, 0.100, 0.110, 0.026, 0.005, 0.005, 0.005
])
hour_probs /= hour_probs.sum()
order_hours = np.random.choice(hours, size=NUM_ORDERS, p=hour_probs)
order_minutes = np.random.randint(0, 60, size=NUM_ORDERS)
order_seconds = np.random.randint(0, 60, size=NUM_ORDERS)

order_timestamps = [
    base_dt.replace(hour=h, minute=m, second=s)
    for base_dt, h, m, s in zip(order_dates_base, order_hours, order_minutes, order_seconds)
]

cust_weights = np.random.zipf(a=1.5, size=NUM_CUSTOMERS)
cust_probs = cust_weights / cust_weights.sum()
selected_customers = np.random.choice(customer_ids, size=NUM_ORDERS, p=cust_probs)
selected_stores = np.random.choice(store_ids, size=NUM_ORDERS)
statuses = np.random.choice(['delivered', 'cancelled', 'out_for_delivery'], size=NUM_ORDERS, p=[0.94, 0.05, 0.01])
order_uuids = [str(uuid.uuid4()) for _ in range(NUM_ORDERS)]

orders_df = pd.DataFrame({
    'order_id': order_uuids,
    'customer_id': selected_customers,
    'store_id': selected_stores,
    'status': statuses,
    'created_at': order_timestamps
})
orders_df = orders_df.sort_values(by='created_at').reset_index(drop=True)

# 7. Order Items
basket_sizes = np.random.poisson(lam=4.2, size=NUM_ORDERS) + 1
order_idx_repeats = np.repeat(np.arange(NUM_ORDERS), basket_sizes)
total_items = len(order_idx_repeats)

prod_indices = np.random.randint(0, NUM_PRODUCTS, size=total_items)
quantities = np.random.choice([1, 2, 3, 4], size=total_items, p=[0.75, 0.18, 0.05, 0.02])

prices_arr = np.array(prices)
costs_arr = np.array(cost_prices)
selected_product_ids = [product_ids[i] for i in prod_indices]
selected_prices = prices_arr[prod_indices]
selected_totals = selected_prices * quantities

order_ids_repeated = orders_df['order_id'].values[order_idx_repeats]
order_timestamps_repeated = orders_df['created_at'].values[order_idx_repeats]

order_items_df = pd.DataFrame({
    'order_item_id': [str(uuid.uuid4()) for _ in range(total_items)],
    'order_id': order_ids_repeated,
    'product_id': selected_product_ids,
    'quantity': quantities,
    'unit_price': selected_prices,
    'total_price': selected_totals,
    'created_at': order_timestamps_repeated
})
order_items_df.to_csv(os.path.join(output_dir, 'order_items.csv'), index=False)

# Finalize Orders
subtotals = order_items_df.groupby('order_id')['total_price'].sum()
orders_df = orders_df.set_index('order_id')
orders_df['subtotal'] = subtotals
orders_df['tax'] = (orders_df['subtotal'] * 0.05).round(2)
orders_df['delivery_fee'] = np.where(orders_df['subtotal'] < 30.00, 3.00, 0.00)

promo_ids = promotions_df['promotion_id'].values
promo_mins = promotions_df['min_order_value'].values
promo_vals = promotions_df['discount_value'].values
promo_types = promotions_df['discount_type'].values

applied_promo_id = []
applied_discounts = []
for sub in orders_df['subtotal'].values:
    if np.random.rand() < 0.35:
        eligible_promos = np.where(promo_mins <= sub)[0]
        if len(eligible_promos) > 0:
            idx = random.choice(eligible_promos)
            applied_promo_id.append(promo_ids[idx])
            val = promo_vals[idx]
            disc = round(sub * (val / 100.0), 2) if promo_types[idx] == 'percentage' else val
            applied_discounts.append(disc)
            continue
    applied_promo_id.append(None)
    applied_discounts.append(0.00)

orders_df['promotion_id'] = applied_promo_id
orders_df['discount_amount'] = applied_discounts
orders_df['total_amount'] = (orders_df['subtotal'] + orders_df['tax'] + orders_df['delivery_fee'] - orders_df['discount_amount']).clip(lower=0.0)

delivered_mask = orders_df['status'] == 'delivered'
delivered_times = []
for ct, dm in zip(orders_df['created_at'].values, delivered_mask):
    delivered_times.append(pd.to_datetime(ct) + timedelta(minutes=random.randint(10, 25)) if dm else None)
orders_df['delivered_at'] = delivered_times

orders_df = orders_df.reset_index()
orders_df.to_csv(os.path.join(output_dir, 'orders.csv'), index=False)

print("\n--- Summary ---")
files = ['stores.csv', 'products.csv', 'customers.csv', 'promotions.csv', 'inventory.csv', 'orders.csv', 'order_items.csv']
for f in files:
    path = os.path.join(output_dir, f)
    df = pd.read_csv(path)
    print(f"File: {f} | Rows: {len(df)}")
    print("Sample Record:")
    print(df.iloc[0].to_dict())
    print("-" * 50)
