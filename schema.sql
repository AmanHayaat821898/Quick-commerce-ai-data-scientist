-- ==========================================
-- Production-Grade PostgreSQL Database Schema
-- Designed for Quick-Commerce (e.g., Blinkit, Swiggy Instamart)
--
-- Target Metrics (2-Year Scale):
--   - 100 Stores
--   - 5,000 Products
--   - 100,000 Customers
--   - 1,000,000 Orders (Partitioned monthly)
-- ==========================================

-- Enable pgcrypto for UUID generation if needed
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==========================================
-- 1. STORES TABLE
-- ==========================================
CREATE TABLE stores (
    store_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    city VARCHAR(50) NOT NULL,
    pincode VARCHAR(10) NOT NULL,
    geohash VARCHAR(12) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Indexing for geographic and city-level routing
CREATE INDEX idx_stores_city ON stores(city);
CREATE INDEX idx_stores_pincode ON stores(pincode);
CREATE INDEX idx_stores_active ON stores(is_active) WHERE is_active = TRUE;


-- ==========================================
-- 2. PRODUCTS TABLE
-- ==========================================
CREATE TABLE products (
    product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100) NOT NULL,
    sub_category VARCHAR(100) NOT NULL,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    cost_price NUMERIC(10, 2) NOT NULL CHECK (cost_price >= 0),
    is_perishable BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT chk_price_margin CHECK (price >= cost_price)
);

-- Indexing for category searches and catalog browsing
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_products_category_sub ON products(category, sub_category);
CREATE INDEX idx_products_sku ON products(sku);


-- ==========================================
-- 3. CUSTOMERS TABLE
-- ==========================================
CREATE TABLE customers (
    customer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number VARCHAR(15) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100),
    customer_tier VARCHAR(20) DEFAULT 'bronze' NOT NULL CHECK (customer_tier IN ('bronze', 'silver', 'gold')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Indexing for tier-based cohort analysis and phone searches
CREATE INDEX idx_customers_phone ON customers(phone_number);
CREATE INDEX idx_customers_tier ON customers(customer_tier);
CREATE INDEX idx_customers_created ON customers(created_at);


-- ==========================================
-- 4. PROMOTIONS TABLE
-- ==========================================
CREATE TABLE promotions (
    promotion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) UNIQUE NOT NULL,
    discount_type VARCHAR(20) NOT NULL CHECK (discount_type IN ('percentage', 'flat_amount', 'free_delivery')),
    discount_value NUMERIC(10, 2) NOT NULL CHECK (discount_value > 0),
    min_order_value NUMERIC(10, 2) DEFAULT 0.00 NOT NULL CHECK (min_order_value >= 0),
    max_discount_limit NUMERIC(10, 2), -- Applicable for percentage discount types
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    
    CONSTRAINT chk_dates CHECK (end_date > start_date)
);

-- Indexing active promotion codes and validity dates
CREATE INDEX idx_promotions_code ON promotions(code);
CREATE INDEX idx_promotions_active_dates ON promotions(start_date, end_date) WHERE is_active = TRUE;


-- ==========================================
-- 5. INVENTORY TABLE
-- ==========================================
CREATE TABLE inventory (
    inventory_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES stores(store_id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    stock_level INTEGER DEFAULT 0 NOT NULL CHECK (stock_level >= 0),
    reorder_level INTEGER DEFAULT 10 NOT NULL CHECK (reorder_level >= 0),
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT uq_store_product UNIQUE (store_id, product_id)
);

-- Indexes for lightning-fast stock availability checks (store-specific catalog checks)
CREATE INDEX idx_inventory_store_product ON inventory(store_id, product_id);
CREATE INDEX idx_inventory_low_stock ON inventory(store_id) WHERE stock_level <= reorder_level;


-- ==========================================
-- 6. ORDERS TABLE (Partitioned by Month)
-- ==========================================
-- Partitioned table on order placement date to support scalable query pruning
CREATE TABLE orders (
    order_id UUID NOT NULL,
    customer_id UUID NOT NULL REFERENCES customers(customer_id),
    store_id UUID NOT NULL REFERENCES stores(store_id),
    promotion_id UUID REFERENCES promotions(promotion_id),
    status VARCHAR(30) NOT NULL CHECK (status IN ('placed', 'packing', 'out_for_delivery', 'delivered', 'cancelled')),
    subtotal NUMERIC(10, 2) NOT NULL CHECK (subtotal >= 0),
    tax NUMERIC(10, 2) NOT NULL CHECK (tax >= 0),
    delivery_fee NUMERIC(10, 2) NOT NULL CHECK (delivery_fee >= 0),
    discount_amount NUMERIC(10, 2) DEFAULT 0.00 NOT NULL CHECK (discount_amount >= 0),
    total_amount NUMERIC(10, 2) NOT NULL CHECK (total_amount >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    delivered_at TIMESTAMP WITH TIME ZONE,
    
    PRIMARY KEY (order_id, created_at) -- Partition key must be part of the primary key
) PARTITION BY RANGE (created_at);

-- Indexes on partitioned parent table (automatically inherited/propagated in newer PostgreSQL versions)
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_store_id ON orders(store_id);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);


-- ==========================================
-- 7. ORDER ITEMS TABLE (Partitioned by Month)
-- ==========================================
CREATE TABLE order_items (
    order_item_id UUID NOT NULL,
    order_id UUID NOT NULL,
    product_id UUID NOT NULL REFERENCES products(product_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    total_price NUMERIC(10, 2) NOT NULL CHECK (total_price >= 0),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    
    PRIMARY KEY (order_item_id, created_at)
) PARTITION BY RANGE (created_at);

-- Foreign key linking order_items back to orders (using composite primary key of orders table)
-- Note: Foreign keys to partitioned tables require referencing both the primary keys (order_id, created_at)
ALTER TABLE order_items 
ADD CONSTRAINT fk_order_items_orders 
FOREIGN KEY (order_id, created_at) REFERENCES orders (order_id, created_at) ON DELETE CASCADE;

CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_order_items_order_id ON order_items(order_id, created_at);


-- ==========================================
-- Example Partition Creation (Auto-generation scripts recommended in production)
-- Creating initial partition tables for the current 2-year projection (e.g., 2026)
-- ==========================================
CREATE TABLE orders_y2026m06 PARTITION OF orders
    FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE order_items_y2026m06 PARTITION OF order_items
    FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');
