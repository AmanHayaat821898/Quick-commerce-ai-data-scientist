# Power BI Integration Guide: Quick-Commerce AI Control Center 📊

This guide outlines how to link the PostgreSQL/SQLite database to Microsoft Power BI and implement the analytics metrics using standard DAX (Data Analysis Expressions) formulas.

---

## 1. Connecting Power BI to the Database

### Method A: PostgreSQL (Production Setup)
1. Open the [quick_commerce_connection.pbids](quick_commerce_connection.pbids) file in this repository by double-clicking it.
2. Power BI Desktop will launch and automatically configure the PostgreSQL adapter.
3. Input your server host credentials when prompted and choose **DirectQuery** to enable real-time analytical slicing.

### Method B: SQLite (Local Cache Setup)
1. Install the **SQLite ODBC Driver** on your system.
2. In Power BI Desktop, click **Get Data** -> **ODBC**.
3. Select your local DSN pointing to your `quick_commerce.db` database.

---

## 2. Primary DAX Measures & Metrics

Implement these DAX formulas inside your Power BI Report to replicate the control center metrics:

### 2.1 Revenue Metrics

* **Gross Merchandise Value (GMV):**
  ```dax
  GMV = SUM(orders[total_amount])
  ```

* **Average Order Value (AOV):**
  ```dax
  AOV = AVERAGE(orders[total_amount])
  ```

* **Fulfillment Rate (%):**
  ```dax
  Fulfillment Rate = 
  DIVIDE(
      CALCULATE(COUNT(orders[order_id]), orders[status] = "delivered"),
      COUNT(orders[order_id])
  )
  ```

### 2.2 Customer Retention Metrics

* **Gold Tier Customer Share (%):**
  ```dax
  Gold Customer Share = 
  DIVIDE(
      CALCULATE(COUNT(customers[customer_id]), customers[customer_tier] = "gold"),
      COUNT(customers[customer_id])
  )
  ```

* **Average Purchase Interval (Days):**
  ```dax
  Avg Interval Days = 
  AVERAGEX(
      VALUES(orders[customer_id]),
      VAR CustOrders = CALCULATETABLE(orders)
      RETURN DATEDIFF(MINX(CustOrders, orders[created_at]), MAXX(CustOrders, orders[created_at]), DAY)
  )
  ```

### 2.3 Inventory Control Metrics

* **Out of Stock (OOS) Rate (%):**
  ```dax
  OOS Rate = 
  DIVIDE(
      CALCULATE(COUNT(inventory[inventory_id]), inventory[stock_level] = 0),
      COUNT(inventory[inventory_id])
  )
  ```

* **Capital Exposure (Holding Cost Value):**
  ```dax
  Capital Locked = SUMX(inventory, inventory[stock_level] * RELATED(products[cost_price]))
  ```
