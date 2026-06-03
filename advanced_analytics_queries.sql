-- ============================================================================
-- ADVANCED SQL ANALYTICS QUERIES FOR QUICK-COMMERCE (100-QUERY PORTFOLIO)
--
-- Target Platform: PostgreSQL
-- Database Schema Target: Quick-Commerce (Orders, Customers, Products, Stores, Inventory)
--
-- Categories Covered:
--   1. Customer Cohort & Retention Analysis (Queries 1-15)
--   2. RFM (Recency, Frequency, Monetary) Segmentation (Queries 16-30)
--   3. Customer Lifetime Value (CLV) & Valuation (Queries 31-45)
--   4. Revenue Trends & Velocity Analysis (Queries 46-65)
--   5. Inventory Analytics & Supply Chain (Queries 66-80)
--   6. Delivery Operations & SLA Performance (Queries 81-100)
-- ============================================================================

-- ============================================================================
-- CATEGORY 1: CUSTOMER COHORT & RETENTION ANALYSIS (Queries 1-15)
-- ============================================================================

-- Q1: Classic Monthly Acquisition Cohort Retention (MoM)
-- Explanation: Establishes a customer's acquisition month and monitors their purchase activity in subsequent months.
WITH customer_acquisition AS (
    SELECT customer_id, DATE_TRUNC('month', MIN(created_at)) AS acquisition_month
    FROM orders
    WHERE status = 'delivered'
    GROUP BY 1
),
customer_activity AS (
    SELECT o.customer_id,
           DATE_TRUNC('month', o.created_at) AS activity_month,
           EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', o.created_at), ca.acquisition_month)) AS cohort_index
    FROM orders o
    JOIN customer_acquisition ca ON o.customer_id = ca.customer_id
    WHERE o.status = 'delivered'
    GROUP BY 1, 2, 3
)
SELECT ca.acquisition_month,
       ca.cohort_index,
       COUNT(DISTINCT ca.customer_id) AS active_customers,
       ROUND(COUNT(DISTINCT ca.customer_id)::NUMERIC / FIRST_VALUE(COUNT(DISTINCT ca.customer_id)) OVER(PARTITION BY ca.acquisition_month ORDER BY ca.cohort_index) * 100, 2) AS retention_rate
FROM customer_activity ca
GROUP BY 1, 2
ORDER BY 1, 2;

-- Q2: Rolling 30-Day Active Users (DAU/MAU)
-- Explanation: Computes the rolling ratio of daily active users to monthly active users to gauge engagement intensity.
WITH daily_active AS (
    SELECT created_at::date AS active_date, COUNT(DISTINCT customer_id) AS dau
    FROM orders
    WHERE status = 'delivered'
    GROUP BY 1
),
rolling_mau AS (
    SELECT active_date,
           dau,
           (SELECT COUNT(DISTINCT customer_id) 
            FROM orders o 
            WHERE o.created_at::date BETWEEN da.active_date - INTERVAL '29 days' AND da.active_date
              AND o.status = 'delivered') AS mau
    FROM daily_active da
)
SELECT active_date, dau, mau, ROUND((dau::numeric / NULLIF(mau, 0)) * 100, 2) AS engagement_ratio
FROM rolling_mau
ORDER BY active_date DESC;

-- Q3: Weekly Retention Matrix
-- Explanation: Similar to monthly, but tracks week-over-week (WoW) trends, crucial for high-frequency quick commerce purchases.
WITH first_week AS (
    SELECT customer_id, DATE_TRUNC('week', MIN(created_at)) AS first_week_start
    FROM orders
    GROUP BY 1
),
orders_by_week AS (
    SELECT o.customer_id,
           DATE_TRUNC('week', o.created_at) AS order_week,
           ROUND(EXTRACT(epoch FROM (DATE_TRUNC('week', o.created_at) - fw.first_week_start)) / 604800) AS week_index
    FROM orders o
    JOIN first_week fw ON o.customer_id = fw.customer_id
)
SELECT first_week_start,
       week_index,
       COUNT(DISTINCT customer_id) AS customers_active
FROM orders_by_week
GROUP BY 1, 2
ORDER BY 1, 2;

-- Q4: Churn Rate Analysis (MoM)
-- Explanation: Measures customers who ordered in Month N but failed to order in Month N+1.
WITH monthly_users AS (
    SELECT DISTINCT customer_id, DATE_TRUNC('month', created_at) AS active_month
    FROM orders
    WHERE status = 'delivered'
),
user_churn AS (
    SELECT mu1.active_month,
           COUNT(DISTINCT mu1.customer_id) AS current_month_users,
           COUNT(DISTINCT CASE WHEN mu2.customer_id IS NULL THEN mu1.customer_id END) AS churned_users
    FROM monthly_users mu1
    LEFT JOIN monthly_users mu2 
      ON mu1.customer_id = mu2.customer_id 
     AND mu2.active_month = mu1.active_month + INTERVAL '1 month'
    GROUP BY 1
)
SELECT active_month,
       current_month_users,
       churned_users,
       ROUND((churned_users::numeric / current_month_users) * 100, 2) AS churn_rate
FROM user_churn
ORDER BY active_month;

-- Q5: Re-engagement Latency (Average days between order 1, 2, and 3)
-- Explanation: Identifies how long it takes for a newly acquired customer to make their second and third order.
WITH ordered_sequence AS (
    SELECT customer_id,
           created_at,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at) as order_num
    FROM orders
    WHERE status = 'delivered'
),
latency_calc AS (
    SELECT customer_id,
           MAX(CASE WHEN order_num = 1 THEN created_at END) as order1,
           MAX(CASE WHEN order_num = 2 THEN created_at END) as order2,
           MAX(CASE WHEN order_num = 3 THEN created_at END) as order3
    FROM ordered_sequence
    WHERE order_num <= 3
    GROUP BY 1
)
SELECT AVG(EXTRACT(epoch FROM (order2 - order1)) / 86400)::NUMERIC(10,2) AS days_between_1_and_2,
       AVG(EXTRACT(epoch FROM (order3 - order2)) / 86400)::NUMERIC(10,2) AS days_between_2_and_3
FROM latency_calc
WHERE order2 IS NOT NULL;

-- Q6: Dormant Users Re-acquisition Success Rate
-- Explanation: Evaluates active reactivation. Defines dormancy as 60+ days of inactivity and checks if a promotion code reactivated them.
WITH dormant_users AS (
    SELECT customer_id,
           MAX(created_at) as last_order_before_dormancy
    FROM orders
    GROUP BY 1
    HAVING MAX(created_at) < CURRENT_TIMESTAMP - INTERVAL '60 days'
),
reactivations AS (
    SELECT du.customer_id,
           o.order_id,
           o.promotion_id,
           o.created_at as reactivated_at
    FROM dormant_users du
    JOIN orders o ON du.customer_id = o.customer_id
    WHERE o.created_at > du.last_order_before_dormancy
)
SELECT COUNT(DISTINCT customer_id) as total_dormant_reactivated,
       COUNT(DISTINCT CASE WHEN promotion_id IS NOT NULL THEN customer_id END) as reactivated_with_promo,
       ROUND(COUNT(DISTINCT CASE WHEN promotion_id IS NOT NULL THEN customer_id END)::numeric / COUNT(DISTINCT customer_id) * 100, 2) as promo_reactivation_share
FROM reactivations;

-- Q7: Multi-session / Multi-day Reorder Behavior (Within 24 Hours)
-- Explanation: Quick commerce relies heavily on impulse orders. Tracks how many customers order twice on the same day.
SELECT DATE_TRUNC('day', o1.created_at) as order_day,
       COUNT(DISTINCT o1.customer_id) as total_active_customers,
       COUNT(DISTINCT CASE WHEN o2.order_id IS NOT NULL THEN o1.customer_id END) as multi_order_customers,
       ROUND(COUNT(DISTINCT CASE WHEN o2.order_id IS NOT NULL THEN o1.customer_id END)::numeric / COUNT(DISTINCT o1.customer_id) * 100, 2) as multi_order_percentage
FROM orders o1
LEFT JOIN orders o2 
  ON o1.customer_id = o2.customer_id 
 AND o1.order_id <> o2.order_id 
 AND o2.created_at BETWEEN o1.created_at AND o1.created_at + INTERVAL '24 hours'
GROUP BY 1
ORDER BY 1 DESC
LIMIT 30;

-- Q8: Cohort Retention by Acquisition Store City
-- Explanation: Evaluates if specific cities acquire higher-retaining customers than others.
WITH first_order_city AS (
    SELECT DISTINCT ON (o.customer_id) 
           o.customer_id,
           s.city,
           DATE_TRUNC('quarter', o.created_at) AS cohort_quarter
    FROM orders o
    JOIN stores s ON o.store_id = s.store_id
    ORDER BY o.customer_id, o.created_at ASC
),
retention_quarters AS (
    SELECT foc.cohort_quarter,
           foc.city,
           ROUND(EXTRACT(epoch FROM (DATE_TRUNC('quarter', o.created_at) - foc.cohort_quarter)) / 7776000) AS quarter_index,
           COUNT(DISTINCT o.customer_id) AS active_users
    FROM orders o
    JOIN first_order_city foc ON o.customer_id = foc.customer_id
    GROUP BY 1, 2, 3
)
SELECT cohort_quarter, city, quarter_index, active_users
FROM retention_quarters
ORDER BY cohort_quarter, city, quarter_index;

-- Q9: Next-Day Cart Retention (Reorder rate of specific items)
-- Explanation: If a client orders a perishable item (e.g. Milk), check if they reorder from the same sub-category within 3 days.
WITH milk_purchases AS (
    SELECT oi.order_id, o.customer_id, o.created_at, p.sub_category
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE p.sub_category = 'Milk'
)
SELECT COUNT(DISTINCT mp1.customer_id) AS total_milk_buyers,
       COUNT(DISTINCT mp2.customer_id) AS repeat_milk_buyers_3days,
       ROUND(COUNT(DISTINCT mp2.customer_id)::numeric / COUNT(DISTINCT mp1.customer_id) * 100, 2) AS milk_reorder_rate
FROM milk_purchases mp1
LEFT JOIN milk_purchases mp2 
  ON mp1.customer_id = mp2.customer_id 
 AND mp2.created_at BETWEEN mp1.created_at + INTERVAL '1 day' AND mp1.created_at + INTERVAL '3 days';

-- Q10: Survival Analysis (Lifetime distribution of customers)
-- Explanation: Identifies the lifespan of customers (days between first and last recorded orders).
WITH user_lifespans AS (
    SELECT customer_id,
           MIN(created_at) as first_order,
           MAX(created_at) as last_order,
           EXTRACT(DAY FROM (MAX(created_at) - MIN(created_at))) as lifespan_days
    FROM orders
    GROUP BY 1
)
SELECT CASE 
         WHEN lifespan_days = 0 THEN '1-Day Wonder'
         WHEN lifespan_days BETWEEN 1 AND 7 THEN 'Under a Week'
         WHEN lifespan_days BETWEEN 8 AND 30 THEN 'Under a Month'
         WHEN lifespan_days BETWEEN 31 AND 180 THEN 'Medium Term (1-6 Months)'
         ELSE 'Long Term (6+ Months)'
       END as customer_lifespan_bucket,
       COUNT(*) as customer_count,
       ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER() * 100, 2) as pct_of_base
FROM user_lifespans
GROUP BY 1;

-- Q11: Sticky Factor (DAU/WAU)
-- Explanation: Popular SaaS and consumer app metric measuring how many weekly active users engage daily.
WITH daily_counts AS (
    SELECT created_at::date as date_day, COUNT(DISTINCT customer_id) as dau
    FROM orders
    GROUP BY 1
),
weekly_counts AS (
    SELECT date_day,
           dau,
           (SELECT COUNT(DISTINCT customer_id) 
            FROM orders o 
            WHERE o.created_at::date BETWEEN dc.date_day - INTERVAL '6 days' AND dc.date_day) as wau
    FROM daily_counts dc
)
SELECT date_day, dau, wau, ROUND((dau::numeric / NULLIF(wau, 0)) * 100, 2) as sticky_factor
FROM weekly_counts
ORDER BY date_day DESC
LIMIT 30;

-- Q12: Order Frequency Distribution Analysis
-- Explanation: Groups customers by the total number of orders placed in their lifetime.
WITH lifetime_orders AS (
    SELECT customer_id, COUNT(order_id) as total_orders
    FROM orders
    GROUP BY 1
)
SELECT CASE 
         WHEN total_orders = 1 THEN '1 Order'
         WHEN total_orders BETWEEN 2 AND 5 THEN '2-5 Orders (Casual)'
         WHEN total_orders BETWEEN 6 AND 15 THEN '6-15 Orders (Regular)'
         WHEN total_orders BETWEEN 16 AND 50 THEN '16-50 Orders (Frequent)'
         ELSE '50+ Orders (Super User)'
       END as loyalty_class,
       COUNT(*) as customer_count
FROM lifetime_orders
GROUP BY 1;

-- Q13: Average Tenure of Active Cohorts
-- Explanation: Measures how long active customers have been buying from the platform on average.
SELECT customer_tier,
       ROUND(AVG(EXTRACT(day FROM (NOW() - created_at)))::numeric, 1) as avg_tenure_days
FROM customers
GROUP BY 1;

-- Q14: Promotion Usage Impact on 2nd Order Retention
-- Explanation: Checks if customers who use a coupon on order 1 exhibit higher retention rates than those who pay full price.
WITH first_order_promo AS (
    SELECT DISTINCT ON (customer_id) 
           customer_id, 
           (promotion_id IS NOT NULL) AS used_promo_on_first,
           created_at AS first_order_time
    FROM orders
    ORDER BY customer_id, created_at ASC
),
second_order AS (
    SELECT o.customer_id, MIN(o.created_at) as second_order_time
    FROM orders o
    JOIN first_order_promo fop ON o.customer_id = fop.customer_id AND o.created_at > fop.first_order_time
    GROUP BY 1
)
SELECT fop.used_promo_on_first,
       COUNT(fop.customer_id) as total_customers,
       COUNT(so.customer_id) as ret_second_order,
       ROUND(COUNT(so.customer_id)::numeric / COUNT(fop.customer_id) * 100, 2) as retention_rate
FROM first_order_promo fop
LEFT JOIN second_order so ON fop.customer_id = so.customer_id
GROUP BY 1;

-- Q15: High-value Perishable Cohorts Retention
-- Explanation: Determines if buying perishable products (Fresh produce) creates high-retaining customer cohorts.
WITH customer_first_purchase_type AS (
    SELECT DISTINCT ON (o.customer_id) 
           o.customer_id,
           p.is_perishable AS first_item_perishable,
           o.created_at as first_order_time
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    ORDER BY o.customer_id, o.created_at ASC
),
subsequent_orders AS (
    SELECT o.customer_id, COUNT(*) as post_orders
    FROM orders o
    JOIN customer_first_purchase_type cf ON o.customer_id = cf.customer_id AND o.created_at > cf.first_order_time
    GROUP BY 1
)
SELECT cf.first_item_perishable,
       COUNT(cf.customer_id) as cohort_size,
       AVG(COALESCE(so.post_orders, 0))::NUMERIC(10, 2) as avg_additional_orders
FROM customer_first_purchase_type cf
LEFT JOIN subsequent_orders so ON cf.customer_id = so.customer_id
GROUP BY 1;


-- ============================================================================
-- CATEGORY 2: RFM (RECENCY, FREQUENCY, MONETARY) SEGMENTATION (Queries 16-30)
-- ============================================================================

-- Q16: Decile RFM Score Assignment
-- Explanation: Divides the customer base into deciles for Recency, Frequency, and Monetary parameters.
WITH customer_rfm_raw AS (
    SELECT customer_id,
           EXTRACT(DAY FROM (NOW() - MAX(created_at))) AS recency,
           COUNT(order_id) AS frequency,
           SUM(total_amount) AS monetary
    FROM orders
    WHERE status = 'delivered'
    GROUP BY 1
),
rfm_scores AS (
    SELECT customer_id,
           NTILE(5) OVER (ORDER BY recency ASC) AS r_score, -- Lower recency days = better (1 represents most recent)
           NTILE(5) OVER (ORDER BY frequency DESC) AS f_score, -- Higher frequency = better
           NTILE(5) OVER (ORDER BY monetary DESC) AS m_score -- Higher monetary = better
    FROM customer_rfm_raw
)
SELECT customer_id, r_score, f_score, m_score,
       (r_score || f_score || m_score) AS rfm_combined
FROM rfm_scores;

-- Q17: RFM Customer Segments Mapping
-- Explanation: Aggregates individual score vectors into standard marketing personas (Champions, Loyal, Churn-risk).
WITH customer_rfm_raw AS (
    SELECT customer_id,
           EXTRACT(DAY FROM (NOW() - MAX(created_at))) AS recency,
           COUNT(order_id) AS frequency,
           SUM(total_amount) AS monetary
    FROM orders
    WHERE status = 'delivered'
    GROUP BY 1
),
rfm_scores AS (
    SELECT customer_id,
           NTILE(5) OVER (ORDER BY recency ASC) AS r_score,
           NTILE(5) OVER (ORDER BY frequency DESC) AS f_score,
           NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
    FROM customer_rfm_raw
),
personas AS (
    SELECT customer_id,
           CASE 
               WHEN r_score <= 2 AND f_score <= 2 THEN 'Champions / Power Users'
               WHEN r_score <= 2 AND f_score BETWEEN 3 AND 4 THEN 'Active Loyal'
               WHEN r_score BETWEEN 3 AND 4 AND f_score <= 2 THEN 'Needs Attention'
               WHEN r_score >= 4 AND f_score <= 2 THEN 'Cant Lose Them'
               WHEN r_score >= 4 AND f_score >= 4 THEN 'Lost / Dormant'
               ELSE 'Sleeper'
           END AS customer_segment
    FROM rfm_scores
)
SELECT customer_segment, COUNT(*) as total_customers
FROM personas
GROUP BY 1
ORDER BY 2 DESC;

-- Q18: Recency Distribution by Customer Tier
-- Explanation: Checks if Gold/Silver tier customers order more recently on average than Bronze.
SELECT c.customer_tier,
       MIN(EXTRACT(DAY FROM (NOW() - o.created_at))) as min_recency_days,
       AVG(EXTRACT(DAY FROM (NOW() - o.created_at)))::numeric(10,2) as avg_recency_days,
       MAX(EXTRACT(DAY FROM (NOW() - o.created_at))) as max_recency_days
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.status = 'delivered'
GROUP BY 1;

-- Q19: High-Value Recency Churn Identification
-- Explanation: Targets VIP customers (top 10% in spend) whose last purchase was more than 45 days ago.
WITH vip_monetary AS (
    SELECT customer_id,
           SUM(total_amount) as total_spend,
           PERCENT_RANK() OVER (ORDER BY SUM(total_amount) DESC) as spend_percentile
    FROM orders
    WHERE status = 'delivered'
    GROUP BY 1
),
recency_check AS (
    SELECT o.customer_id,
           MAX(o.created_at) as last_order_date
    FROM orders o
    GROUP BY 1
)
SELECT vm.customer_id, vm.total_spend, rc.last_order_date,
       EXTRACT(day FROM (NOW() - rc.last_order_date)) as days_since_last_order
FROM vip_monetary vm
JOIN recency_check rc ON vm.customer_id = rc.customer_id
WHERE vm.spend_percentile <= 0.10
  AND rc.last_order_date < NOW() - INTERVAL '45 days'
ORDER BY vm.total_spend DESC;

-- Q20: Frequency Velocity (Avg days between orders per customer segment)
-- Explanation: Calculates the typical purchase cadence (velocity) across different customer segments.
WITH order_diffs AS (
    SELECT customer_id,
           created_at,
           LAG(created_at) OVER (PARTITION BY customer_id ORDER BY created_at) as prev_order
    FROM orders
    WHERE status = 'delivered'
),
intervals AS (
    SELECT customer_id,
           AVG(EXTRACT(epoch FROM (created_at - prev_order)) / 86400) as avg_interval_days
    FROM order_diffs
    WHERE prev_order IS NOT NULL
    GROUP BY 1
)
SELECT CASE 
         WHEN avg_interval_days <= 2 THEN 'Daily/Multi-weekly (0-2 Days)'
         WHEN avg_interval_days BETWEEN 2.1 AND 7 THEN 'Weekly (2-7 Days)'
         WHEN avg_interval_days BETWEEN 7.1 AND 30 THEN 'Monthly (7-30 Days)'
         ELSE 'Infrequent (30+ Days)'
       END as velocity_segment,
       COUNT(*) as customer_count
FROM intervals
GROUP BY 1;

-- Q21: Monetary Contribution of RFM Segments
-- Explanation: Reveals which RFM segments drive the bulk of total platform revenue (validating the Pareto rule).
WITH customer_rfm_raw AS (
    SELECT customer_id,
           EXTRACT(DAY FROM (NOW() - MAX(created_at))) AS recency,
           COUNT(order_id) AS frequency,
           SUM(total_amount) AS monetary
    FROM orders
    WHERE status = 'delivered'
    GROUP BY 1
),
rfm_scores AS (
    SELECT customer_id,
           monetary,
           NTILE(5) OVER (ORDER BY recency ASC) AS r_score,
           NTILE(5) OVER (ORDER BY frequency DESC) AS f_score
    FROM customer_rfm_raw
),
segments AS (
    SELECT monetary,
           CASE 
               WHEN r_score <= 2 AND f_score <= 2 THEN 'Power Users'
               WHEN r_score <= 2 AND f_score > 2 THEN 'New / Occasional'
               ELSE 'Slipping / Dormant'
           END AS segment_class
    FROM rfm_scores
)
SELECT segment_class,
       SUM(monetary) as total_revenue,
       ROUND(SUM(monetary) / SUM(SUM(monetary)) OVER() * 100, 2) as revenue_share_pct
FROM segments
GROUP BY 1;

-- Q22: Active Promos vs. RFM Segments
-- Explanation: Checks if slipping or dormant segments are highly responsive to promotions.
WITH customer_rfm AS (
    SELECT customer_id,
           EXTRACT(DAY FROM (NOW() - MAX(created_at))) AS recency,
           COUNT(order_id) AS frequency
    FROM orders
    GROUP BY 1
),
segments AS (
    SELECT customer_id,
           CASE 
               WHEN recency <= 15 AND frequency >= 10 THEN 'Loyals'
               WHEN recency BETWEEN 16 AND 45 THEN 'Slipping'
               ELSE 'Cold'
           END AS segment
    FROM customer_rfm
)
SELECT s.segment,
       COUNT(o.order_id) as total_orders,
       COUNT(o.promotion_id) as promo_orders,
       ROUND(COUNT(o.promotion_id)::numeric / COUNT(o.order_id) * 100, 2) as promo_adoption_rate
FROM orders o
JOIN segments s ON o.customer_id = s.customer_id
GROUP BY 1;

-- Q23: Customer Lifecycle Status based on Moving Average Recency
-- Explanation: Compares the customer's current recency to their historical moving average purchase interval to detect churn early.
WITH order_gaps AS (
    SELECT customer_id,
           created_at,
           EXTRACT(day FROM (created_at - LAG(created_at) OVER (PARTITION BY customer_id ORDER BY created_at))) as gap
    FROM orders
),
avg_gaps AS (
    SELECT customer_id,
           AVG(gap) as hist_avg_gap,
           MAX(created_at) as last_order_time
    FROM order_gaps
    WHERE gap IS NOT NULL
    GROUP BY 1
)
SELECT customer_id,
       hist_avg_gap,
       EXTRACT(day FROM (NOW() - last_order_time)) as current_recency,
       CASE 
         WHEN EXTRACT(day FROM (NOW() - last_order_time)) > (hist_avg_gap * 2.5) THEN 'At High Risk of Churn'
         ELSE 'Normal'
       END as lifecycle_alert
FROM avg_gaps
WHERE hist_avg_gap > 0
LIMIT 50;

-- Q24: Average Basket Size by RFM Quintile
-- Explanation: Analyses whether high-frequency customers buy more items per basket or fewer (micro-shopping).
WITH customer_rfm AS (
    SELECT customer_id,
           NTILE(5) OVER (ORDER BY COUNT(order_id) DESC) as f_score
    FROM orders
    GROUP BY 1
),
order_sizes AS (
    SELECT o.customer_id,
           o.order_id,
           SUM(oi.quantity) as total_items
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY 1, 2
)
SELECT cr.f_score,
       AVG(os.total_items)::NUMERIC(10,2) as avg_items_per_basket
FROM order_sizes os
JOIN customer_rfm cr ON os.customer_id = cr.customer_id
GROUP BY 1
ORDER BY 1;

-- Q25: Seasonality and Day-of-week Bias by RFM Segment
-- Explanation: Checks if power users order evenly, while dormant users react only to weekend events.
WITH customer_rfm AS (
    SELECT customer_id,
           NTILE(5) OVER (ORDER BY COUNT(order_id) DESC) as f_score
    FROM orders
    GROUP BY 1
)
SELECT cr.f_score,
       EXTRACT(ISODOW FROM o.created_at) as day_of_week,
       COUNT(o.order_id) as order_volume
FROM orders o
JOIN customer_rfm cr ON o.customer_id = cr.customer_id
GROUP BY 1, 2
ORDER BY 1, 2;

-- Q26: F & M Correlation Analysis
-- Explanation: Measures statistical correlation between order count (frequency) and order monetary values.
WITH customer_stats AS (
    SELECT customer_id,
           COUNT(order_id) as freq,
           SUM(total_amount) as mont
    FROM orders
    GROUP BY 1
)
SELECT corr(freq, mont) as frequency_monetary_correlation
FROM customer_stats;

-- Q27: Dynamic RFM Cohort Shift Tracking
-- Explanation: Tracks if users in a specific RFM segment in Q1 migrated to a lower/higher segment by Q2.
WITH rfm_q1 AS (
    SELECT customer_id,
           NTILE(5) OVER (ORDER BY COUNT(order_id) DESC) as f_q1
    FROM orders
    WHERE created_at BETWEEN '2025-01-01' AND '2025-03-31'
    GROUP BY 1
),
rfm_q2 AS (
    SELECT customer_id,
           NTILE(5) OVER (ORDER BY COUNT(order_id) DESC) as f_q2
    FROM orders
    WHERE created_at BETWEEN '2025-04-01' AND '2025-06-30'
    GROUP BY 1
)
SELECT q1.f_q1 as segment_q1,
       q2.f_q2 as segment_q2,
       COUNT(*) as customer_transitions
FROM rfm_q1 q1
JOIN rfm_q2 q2 ON q1.customer_id = q2.customer_id
GROUP BY 1, 2
ORDER BY 1, 2;

-- Q28: Average Delivery Rating by RFM Segment
-- Explanation: Checks if lower satisfaction ratings correlate with clients slipping into colder RFM segments.
WITH customer_rfm AS (
    SELECT o.customer_id,
           MAX(o.created_at) as last_order_date
    FROM orders o
    GROUP BY 1
),
ratings AS (
    SELECT o.customer_id,
           AVG(d.rating) as avg_rating
    FROM orders o
    JOIN deliveries d ON o.order_id = d.order_id
    GROUP BY 1
)
SELECT CASE 
         WHEN EXTRACT(DAY FROM (NOW() - cr.last_order_date)) <= 15 THEN 'Active (0-15 Days)'
         WHEN EXTRACT(DAY FROM (NOW() - cr.last_order_date)) BETWEEN 16 AND 45 THEN 'Slipping (16-45 Days)'
         ELSE 'Cold (45+ Days)'
       END as segments,
       AVG(r.avg_rating)::NUMERIC(10,2) as score_rating
FROM customer_rfm cr
JOIN ratings r ON cr.customer_id = r.customer_id
GROUP BY 1;

-- Q29: Most Popular Category by RFM Segment
-- Explanation: Highlights what catalog items loyal vs. slipping customers buy.
WITH customer_rfm AS (
    SELECT customer_id,
           NTILE(5) OVER (ORDER BY COUNT(order_id) DESC) as f_score
    FROM orders
    GROUP BY 1
),
item_popularity AS (
    SELECT cr.f_score,
           p.category,
           COUNT(*) as purchase_count,
           ROW_NUMBER() OVER (PARTITION BY cr.f_score ORDER BY COUNT(*) DESC) as rank
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    JOIN customer_rfm cr ON o.customer_id = cr.customer_id
    GROUP BY 1, 2
)
SELECT f_score, category, purchase_count
FROM item_popularity
WHERE rank = 1;

-- Q30: Margin Generation by RFM Segment
-- Explanation: Measures exact profitability metrics (Price - Cost Price) generated by each RFM tier.
WITH customer_rfm AS (
    SELECT customer_id,
           NTILE(5) OVER (ORDER BY COUNT(order_id) DESC) as f_score
    FROM orders
    GROUP BY 1
)
SELECT cr.f_score,
       SUM((oi.unit_price - p.cost_price) * oi.quantity) as generated_margin,
       SUM(oi.total_price) as gross_revenue,
       ROUND((SUM((oi.unit_price - p.cost_price) * oi.quantity) / SUM(oi.total_price)) * 100, 2) as margin_efficiency_pct
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN products p ON oi.product_id = p.product_id
JOIN customer_rfm cr ON o.customer_id = cr.customer_id
GROUP BY 1
ORDER BY 1;


-- ============================================================================
-- CATEGORY 3: CUSTOMER LIFETIME VALUE (CLV) & VALUATION (Queries 31-45)
-- ============================================================================

-- Q31: Lifetime Value (LTV) Decile Rank
-- Explanation: Identifies the top lifetime spenders and rank-orders the entire customer base.
WITH customer_spend AS (
    SELECT customer_id,
           SUM(total_amount) as lifetime_spend,
           COUNT(order_id) as total_orders
    FROM orders
    WHERE status = 'delivered'
    GROUP BY 1
)
SELECT customer_id,
       lifetime_spend,
       total_orders,
       NTILE(10) OVER (ORDER BY lifetime_spend DESC) as ltv_decile
FROM customer_spend;

-- Q32: Monthly Cohort LTV Trajectory
-- Explanation: Tracks cumulative spend trajectories of quarterly acquisition cohorts to predict future valuation.
WITH customer_acquisition AS (
    SELECT customer_id, DATE_TRUNC('quarter', MIN(created_at)) AS acq_quarter
    FROM orders
    GROUP BY 1
),
order_timeline AS (
    SELECT o.customer_id,
           o.total_amount,
           EXTRACT(month from AGE(DATE_TRUNC('month', o.created_at), ca.acq_quarter)) as month_index
    FROM orders o
    JOIN customer_acquisition ca ON o.customer_id = ca.customer_id
)
SELECT acq_quarter,
       month_index,
       SUM(total_amount) as aggregate_spend,
       SUM(SUM(total_amount)) OVER (PARTITION BY acq_quarter ORDER BY month_index) as cumulative_ltv
FROM order_timeline
WHERE month_index BETWEEN 0 AND 12
GROUP BY 1, 2
ORDER BY 1, 2;

-- Q33: Customer Acquisition Cost (CAC) Payback Period Simulation
-- Explanation: Simulates payback loops assuming target marketing cost of $25.00 per customer, tracking margin cumulative returns.
WITH customer_margins AS (
    SELECT o.customer_id,
           o.created_at,
           SUM((oi.unit_price - p.cost_price) * oi.quantity) as order_margin
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY 1, 2
),
acquisition_dates AS (
    SELECT customer_id, MIN(created_at) as acq_time
    FROM orders
    GROUP BY 1
),
running_margin AS (
    SELECT cm.customer_id,
           EXTRACT(day from (cm.created_at - ad.acq_time)) as days_since_acquisition,
           SUM(cm.order_margin) OVER (PARTITION BY cm.customer_id ORDER BY cm.created_at) as cumulative_margin
    FROM customer_margins cm
    JOIN acquisition_dates ad ON cm.customer_id = ad.customer_id
)
SELECT customer_id,
       MIN(CASE WHEN cumulative_margin >= 25.00 THEN days_since_acquisition END) as days_to_cac_payback
FROM running_margin
GROUP BY 1
HAVING MIN(CASE WHEN cumulative_margin >= 25.00 THEN days_since_acquisition END) IS NOT NULL
LIMIT 50;

-- Q34: Discount Penetration impact on Customer Valuation
-- Explanation: Checks if high promo use reduces long-term user valuation.
WITH customer_discount_dependency AS (
    SELECT customer_id,
           SUM(discount_amount) as total_discounts,
           SUM(total_amount) as total_spent,
           SUM(discount_amount) / NULLIF(SUM(total_amount) + SUM(discount_amount), 0) as discount_ratio
    FROM orders
    GROUP BY 1
)
SELECT CASE 
         WHEN discount_ratio = 0 THEN 'No Discount Usage'
         WHEN discount_ratio BETWEEN 0.01 AND 0.15 THEN 'Low Promo Dependency'
         WHEN discount_ratio BETWEEN 0.16 AND 0.40 THEN 'Medium Promo Dependency'
         ELSE 'High Promo Dependency'
       END as promo_dependence_tier,
       COUNT(*) as customer_count,
       AVG(total_spent)::NUMERIC(10,2) as avg_lifetime_value
FROM customer_discount_dependency
GROUP BY 1;

-- Q35: CLV Forecast parameters (Average Order Value & Annual Purchase Frequency)
-- Explanation: Generates standard input variables needed for probabilistic forecasting models (e.g., BG/NBD models).
SELECT c.customer_tier,
       AVG(o.total_amount)::NUMERIC(10,2) as average_order_value,
       (COUNT(o.order_id)::numeric / COUNT(DISTINCT o.customer_id) * (365.0 / 730.0))::NUMERIC(10,2) as annualized_purchase_frequency,
       AVG(o.total_amount)::NUMERIC(10,2) * (COUNT(o.order_id)::numeric / COUNT(DISTINCT o.customer_id) * (365.0 / 730.0))::NUMERIC(10,2) as simple_annual_clv_estimate
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY 1;

-- Q36: Customer Churn Threshold (Maximum interval before marked inactive)
-- Explanation: Performs percentile calculations on purchase gaps to mathematically define "churn" (95th percentile of purchase intervals).
WITH order_gaps AS (
    SELECT customer_id,
           created_at,
           EXTRACT(day FROM (created_at - LAG(created_at) OVER (PARTITION BY customer_id ORDER BY created_at))) as gap
    FROM orders
    WHERE status = 'delivered'
)
SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY gap) as churn_threshold_days
FROM order_gaps
WHERE gap IS NOT NULL;

-- Q37: LTV Contribution of Top Cities
-- Explanation: Highlights geographic locations that yield the most valuable customers.
SELECT s.city,
       COUNT(DISTINCT o.customer_id) as total_customers,
       SUM(o.total_amount) as total_revenue,
       (SUM(o.total_amount) / COUNT(DISTINCT o.customer_id))::NUMERIC(10,2) as customer_ltv_average
FROM orders o
JOIN stores s ON o.store_id = s.store_id
GROUP BY 1
ORDER BY 4 DESC;

-- Q38: First Purchase Category Impact on LTV
-- Explanation: Determines if a customer whose first order was a "Fresh Produce" item generates more lifetime value than "Instant Food" items.
WITH first_order_items AS (
    SELECT DISTINCT ON (o.customer_id) 
           o.customer_id,
           p.category as first_category,
           o.created_at
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    ORDER BY o.customer_id, o.created_at ASC
),
ltv_spend AS (
    SELECT customer_id, SUM(total_amount) as lifetime_spend
    FROM orders
    GROUP BY 1
)
SELECT foi.first_category,
       COUNT(foi.customer_id) as customer_acquired,
       AVG(ls.lifetime_spend)::NUMERIC(10,2) as avg_lifetime_value
FROM first_order_items foi
JOIN ltv_spend ls ON foi.customer_id = ls.customer_id
GROUP BY 1
ORDER BY 3 DESC;

-- Q39: Repeat Purchase Rate inside 7 Days (Product Level)
-- Explanation: Focuses on quick commerce consumable products that drive frequent recurring loops.
WITH product_purchases AS (
    SELECT o.customer_id, oi.product_id, o.created_at
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
)
SELECT p.name,
       COUNT(DISTINCT pp1.customer_id) as unique_purchasers,
       COUNT(DISTINCT pp2.customer_id) as repeat_purchasers_7d,
       ROUND(COUNT(DISTINCT pp2.customer_id)::numeric / COUNT(DISTINCT pp1.customer_id) * 100, 2) as repeat_rate_7d
FROM product_purchases pp1
JOIN products p ON pp1.product_id = p.product_id
LEFT JOIN product_purchases pp2 
  ON pp1.customer_id = pp2.customer_id 
 AND pp1.product_id = pp2.product_id
 AND pp2.created_at BETWEEN pp1.created_at + INTERVAL '1 hour' AND pp1.created_at + INTERVAL '7 days'
GROUP BY p.name
HAVING COUNT(DISTINCT pp1.customer_id) > 100
ORDER BY 3 DESC
LIMIT 20;

-- Q40: High-Frequency Cancellation Cohorts
-- Explanation: Checks if customers who encounter high cancellation rates early in their lifecycle reduce their long-term value.
WITH early_experience AS (
    SELECT customer_id,
           COUNT(*) as total_first_5_orders,
           COUNT(CASE WHEN status = 'cancelled' THEN 1 END) as cancelled_orders
    FROM (
        SELECT customer_id, status,
               ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at) as order_seq
        FROM orders
    ) seq
    WHERE order_seq <= 5
    GROUP BY 1
),
lifetime_spend AS (
    SELECT customer_id, SUM(total_amount) as ltv
    FROM orders
    WHERE status = 'delivered'
    GROUP BY 1
)
SELECT ee.cancelled_orders as cancellations_in_first_5_orders,
       COUNT(ee.customer_id) as customer_count,
       AVG(COALESCE(ls.ltv, 0))::NUMERIC(10,2) as avg_lifetime_value
FROM early_experience ee
LEFT JOIN lifetime_spend ls ON ee.customer_id = ls.customer_id
GROUP BY 1
ORDER BY 1;

-- Q41: Multi-Store Buyers vs Single-Store Buyers LTV
-- Explanation: Measures if customers who order from multiple stores have a higher LTV.
WITH store_diversity AS (
    SELECT customer_id,
           COUNT(DISTINCT store_id) as unique_stores,
           SUM(total_amount) as ltv
    FROM orders
    GROUP BY 1
)
SELECT CASE 
         WHEN unique_stores = 1 THEN 'Single Store Buyer'
         WHEN unique_stores BETWEEN 2 AND 4 THEN 'Medium Variety (2-4 Stores)'
         ELSE 'High Variety (5+ Stores)'
       END as purchase_pattern,
       COUNT(*) as customer_count,
       AVG(ltv)::NUMERIC(10,2) as avg_ltv
FROM store_diversity
GROUP BY 1;

-- Q42: Lifetime Gross Profit Contribution per Customer
-- Explanation: Focuses on margins instead of top-line revenue, tracing lifetime gross profits.
WITH margin_per_order AS (
    SELECT o.customer_id,
           o.order_id,
           SUM((oi.unit_price - p.cost_price) * oi.quantity) as order_margin
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY 1, 2
)
SELECT customer_id,
       SUM(order_margin) as total_lifetime_gross_margin
FROM margin_per_order
GROUP BY 1
ORDER BY 2 DESC
LIMIT 50;

-- Q43: Time to Churn (Survival Duration in Days)
-- Explanation: Measures the duration between customer creation and their last order date.
WITH customer_lifespan AS (
    SELECT c.customer_id,
           c.created_at as signup_date,
           MAX(o.created_at) as last_order_date
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY 1, 2
)
SELECT AVG(EXTRACT(DAY FROM (last_order_date - signup_date)))::NUMERIC(10,1) as avg_active_lifespan_days
FROM customer_lifespan;

-- Q44: Delivery Time SLA Defection impact on LTV
-- Explanation: Checks if customers who experience late deliveries (>20 mins) during their first month have reduced LTV.
WITH first_month_deliveries AS (
    SELECT o.customer_id,
           d.transit_time_seconds,
           o.created_at
    FROM orders o
    JOIN deliveries d ON o.order_id = d.order_id
    WHERE o.created_at < (SELECT MIN(created_at) FROM orders) + INTERVAL '30 days'
),
sla_compliance AS (
    SELECT customer_id,
           AVG(transit_time_seconds) as avg_transit_sec,
           MAX(transit_time_seconds) as max_transit_sec
    FROM first_month_deliveries
    GROUP BY 1
),
lifetime_spend AS (
    SELECT customer_id, SUM(total_amount) as ltv
    FROM orders
    GROUP BY 1
)
SELECT CASE 
         WHEN avg_transit_sec <= 1200 THEN 'Excellent (<20 Mins)'
         WHEN avg_transit_sec BETWEEN 1201 AND 1800 THEN 'Good (20-30 Mins)'
         ELSE 'Poor (30+ Mins)'
       END as delivery_service_tier,
       COUNT(sc.customer_id) as customer_count,
       AVG(ls.ltv)::NUMERIC(10,2) as avg_ltv
FROM sla_compliance sc
JOIN lifetime_spend ls ON sc.customer_id = ls.customer_id
GROUP BY 1;

-- Q45: Referral Promotion LTV Analysis
-- Explanation: Compares LTV generated by discount codes (e.g. WELCOME100) vs organic sales.
WITH order_promo_mapping AS (
    SELECT o.customer_id,
           COALESCE(p.code, 'ORGANIC') as promo_code,
           o.total_amount
    FROM orders o
    LEFT JOIN promotions p ON o.promotion_id = p.promotion_id
)
SELECT promo_code,
       COUNT(DISTINCT customer_id) as customer_count,
       SUM(total_amount) as total_val,
       (SUM(total_amount) / COUNT(DISTINCT customer_id))::NUMERIC(10,2) as user_ltv
FROM order_promo_mapping
GROUP BY 1
ORDER BY 4 DESC;


-- ============================================================================
-- CATEGORY 4: REVENUE TRENDS & VELOCITY ANALYSIS (Queries 46-65)
-- ============================================================================

-- Q46: Gross Merchandise Value (GMV) - Weekly Trend
-- Explanation: Aggregates total order value weekly to monitor underlying core growth.
SELECT DATE_TRUNC('week', created_at) AS order_week,
       COUNT(order_id) AS total_orders,
       SUM(total_amount) AS weekly_gmv
FROM orders
WHERE status = 'delivered'
GROUP BY 1
ORDER BY 1 DESC;

-- Q47: Daily Revenue Velocity with 7-Day Moving Average
-- Explanation: Smooths daily revenue counts using standard moving average calculations.
WITH daily_revenue AS (
    SELECT created_at::date AS order_day,
           SUM(total_amount) AS daily_rev
    FROM orders
    WHERE status = 'delivered'
    GROUP BY 1
)
SELECT order_day,
       daily_rev,
       AVG(daily_rev) OVER (ORDER BY order_day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)::NUMERIC(10,2) AS rolling_7d_average
FROM daily_revenue
ORDER BY order_day DESC;

-- Q48: Month-on-Month (MoM) Growth in GMV
-- Explanation: Standard corporate finance metrics monitoring growth percentages month-on-month.
WITH monthly_rev AS (
    SELECT DATE_TRUNC('month', created_at) AS order_month,
           SUM(total_amount) AS monthly_gmv
    FROM orders
    WHERE status = 'delivered'
    GROUP BY 1
)
SELECT order_month,
       monthly_gmv,
       LAG(monthly_gmv) OVER (ORDER BY order_month) AS prev_month_gmv,
       ROUND(((monthly_gmv - LAG(monthly_gmv) OVER (ORDER BY order_month)) / LAG(monthly_gmv) OVER (ORDER BY order_month)) * 100, 2) AS growth_pct
FROM monthly_rev
ORDER BY order_month;

-- Q49: Day-of-Week Revenue Distribution
-- Explanation: Checks which day of the week generates the highest percentage of sales.
SELECT EXTRACT(ISODOW FROM created_at) AS day_of_week,
       COUNT(order_id) as total_orders,
       SUM(total_amount) AS revenue,
       ROUND(SUM(total_amount) / SUM(SUM(total_amount)) OVER() * 100, 2) AS revenue_share_pct
FROM orders
WHERE status = 'delivered'
GROUP BY 1
ORDER BY 1;

-- Q50: Hourly Revenue Peak Analysis
-- Explanation: Analyzes which hours of the day generate the most revenue (vital for workforce/rider scheduling).
SELECT EXTRACT(HOUR FROM created_at) AS hour_of_day,
       COUNT(order_id) AS total_orders,
       SUM(total_amount) AS total_revenue
FROM orders
WHERE status = 'delivered'
GROUP BY 1
ORDER BY 3 DESC;

-- Q51: Average Order Value (AOV) Monthly Trend
-- Explanation: Monitors shifts in average cart value month-on-month.
SELECT DATE_TRUNC('month', created_at) AS order_month,
       (SUM(total_amount) / COUNT(order_id))::NUMERIC(10,2) as aov
FROM orders
WHERE status = 'delivered'
GROUP BY 1
ORDER BY 1;

-- Q52: Revenue Contribution by Store Tier / Location
-- Explanation: Breaks down sales based on stores in different geographical groups.
SELECT s.city,
       COUNT(o.order_id) as total_orders,
       SUM(o.total_amount) as total_revenue
FROM orders o
JOIN stores s ON o.store_id = s.store_id
WHERE o.status = 'delivered'
GROUP BY 1
ORDER BY 3 DESC;

-- Q53: Perishable vs Non-Perishable Revenue Share
-- Explanation: Highlights how much revenue fresh items drive vs home care/packaged items.
SELECT p.is_perishable,
       SUM(oi.total_price) as gross_revenue,
       ROUND(SUM(oi.total_price) / SUM(SUM(oi.total_price)) OVER() * 100, 2) as share_pct
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY 1;

-- Q54: Promotion Cost as a Percentage of Revenue (Promo Burn)
-- Explanation: Tracks promo burn rates against GMV.
SELECT DATE_TRUNC('month', created_at) as order_month,
       SUM(total_amount) as net_revenue,
       SUM(discount_amount) as discount_cost,
       ROUND((SUM(discount_amount) / NULLIF(SUM(total_amount), 0)) * 100, 2) as discount_burn_ratio_pct
FROM orders
GROUP BY 1
ORDER BY 1;

-- Q55: Top 10 Revenue-Generating SKUs
-- Explanation: Standard Pareto tracking on individual items.
SELECT p.name, p.sku, p.category,
       SUM(oi.total_price) as total_revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY 1, 2, 3
ORDER BY 4 DESC
LIMIT 10;

-- Q56: Store Revenue Performance Deciles
-- Explanation: Classifies stores into revenue classes (ranking top 10% vs bottom 10%).
WITH store_rev AS (
    SELECT store_id, SUM(total_amount) as total_revenue
    FROM orders
    GROUP BY 1
)
SELECT store_id, total_revenue,
       NTILE(10) OVER (ORDER BY total_revenue DESC) as store_rank_decile
FROM store_rev;

-- Q57: Weekly Cancellation Revenue Losses
-- Explanation: Measures how much GMV is lost to cancelled orders.
SELECT DATE_TRUNC('week', created_at) as order_week,
       COUNT(CASE WHEN status = 'cancelled' THEN 1 END) as cancelled_count,
       SUM(CASE WHEN status = 'cancelled' THEN total_amount ELSE 0 END) as lost_revenue
FROM orders
GROUP BY 1
ORDER BY 1 DESC;

-- Q58: Delivery Fee Revenue vs Logistics Costs
-- Explanation: Analyzes delivery fee recovery rates.
SELECT DATE_TRUNC('month', created_at) as order_month,
       SUM(delivery_fee) as collected_delivery_fees,
       COUNT(order_id) as total_deliveries
FROM orders
GROUP BY 1;

-- Q59: Contribution Margin Trend by Category
-- Explanation: Standard category pricing tracking total margin contributions.
SELECT p.category,
       SUM(oi.total_price) as revenue,
       SUM((oi.unit_price - p.cost_price) * oi.quantity) as gross_margin,
       ROUND((SUM((oi.unit_price - p.cost_price) * oi.quantity) / SUM(oi.total_price)) * 100, 2) as margin_pct
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY 1
ORDER BY 3 DESC;

-- Q60: Weekend vs Weekday Revenue Comparison
-- Explanation: Breaks down average daily order velocity split by weekdays vs weekends.
SELECT CASE 
         WHEN EXTRACT(ISODOW FROM created_at) IN (6, 7) THEN 'Weekend'
         ELSE 'Weekday'
       END as day_type,
       AVG(total_amount)::NUMERIC(10,2) as average_daily_revenue
FROM orders
GROUP BY 1;

-- Q61: Year-over-Year (YoY) Sales Comparison
-- Explanation: Performs long term year-over-year revenue audits.
WITH monthly_data AS (
    SELECT EXTRACT(year from created_at) as yr,
           EXTRACT(month from created_at) as mth,
           SUM(total_amount) as revenue
    FROM orders
    GROUP BY 1, 2
)
SELECT mth,
       MAX(CASE WHEN yr = 2024 THEN revenue END) as rev_2024,
       MAX(CASE WHEN yr = 2025 THEN revenue END) as rev_2025,
       ROUND(((MAX(CASE WHEN yr = 2025 THEN revenue END) - MAX(CASE WHEN yr = 2024 THEN revenue END)) / MAX(CASE WHEN yr = 2024 THEN revenue END)) * 100, 2) as yoy_growth_pct
FROM monthly_data
GROUP BY 1
ORDER BY 1;

-- Q62: Average Items Per Order (Basket Size Value Trend)
-- Explanation: Calculates item counts per order over time.
SELECT DATE_TRUNC('month', created_at) as order_month,
       AVG(items_count)::NUMERIC(10,2) as average_basket_size
FROM (
    SELECT order_id, created_at, SUM(quantity) as items_count
    FROM order_items
    GROUP BY 1, 2
) t
GROUP BY 1
ORDER BY 1;

-- Q63: Revenue Run-Rate Projection (Current month forecast)
-- Explanation: Simulates month-end performance projections based on month-to-date velocity.
WITH mtd_revenue AS (
    SELECT SUM(total_amount) as mtd_rev,
           EXTRACT(day from NOW()) as days_elapsed,
           EXTRACT(day from (DATE_TRUNC('month', NOW()) + INTERVAL '1 month - 1 day')) as total_days
    FROM orders
    WHERE created_at BETWEEN DATE_TRUNC('month', NOW()) AND NOW()
)
SELECT mtd_rev,
       (mtd_rev / days_elapsed * total_days)::NUMERIC(10,2) as projected_monthly_revenue
FROM mtd_revenue;

-- Q64: Store Density and Revenue Correlation
-- Explanation: Checks if average store transaction values scale with total order counts.
SELECT store_id,
       COUNT(order_id) as order_volume,
       SUM(total_amount) as store_revenue,
       (SUM(total_amount) / COUNT(order_id))::NUMERIC(10,2) as store_aov
FROM orders
GROUP BY 1
ORDER BY 3 DESC;

-- Q65: Category Basket Association (Cross-selling velocity)
-- Explanation: Identifies how often item pairs from different categories exist in the same order (Market Basket Analysis).
WITH product_orders AS (
    SELECT oi.order_id, p.category
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
)
SELECT po1.category as primary_category,
       po2.category as secondary_category,
       COUNT(*) as co_occurrence_count
FROM product_orders po1
JOIN product_orders po2 ON po1.order_id = po2.order_id AND po1.category < po2.category
GROUP BY 1, 2
ORDER BY 3 DESC
LIMIT 10;


-- ============================================================================
-- CATEGORY 5: INVENTORY ANALYTICS & SUPPLY CHAIN (Queries 66-80)
-- ============================================================================

-- Q66: Out of Stock (OOS) Incidence Rate
-- Explanation: Monitors the proportion of catalog items currently showing zero stock levels.
SELECT s.city,
       s.name as store_name,
       COUNT(*) as total_catalog_items,
       COUNT(CASE WHEN i.stock_level = 0 THEN 1 END) as out_of_stock_items,
       ROUND((COUNT(CASE WHEN i.stock_level = 0 THEN 1 END)::numeric / COUNT(*)) * 100, 2) as oos_incidence_rate_pct
FROM inventory i
JOIN stores s ON i.store_id = s.store_id
GROUP BY 1, 2;

-- Q67: Days of Inventory Outstanding (DIO)
-- Explanation: Estimates how many days current stock levels will last based on historical 30-day run rate sales.
WITH product_daily_velocity AS (
    SELECT o.store_id,
           oi.product_id,
           SUM(oi.quantity)::numeric / 30.0 as daily_sales_velocity
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.created_at >= NOW() - INTERVAL '30 days'
      AND o.status = 'delivered'
    GROUP BY 1, 2
)
SELECT i.store_id,
       i.product_id,
       i.stock_level,
       pv.daily_sales_velocity,
       CASE 
         WHEN pv.daily_sales_velocity = 0 THEN 999 -- Infinite days
         ELSE ROUND(i.stock_level / pv.daily_sales_velocity, 1)
       END as days_inventory_outstanding
FROM inventory i
LEFT JOIN product_daily_velocity pv ON i.store_id = pv.store_id AND i.product_id = pv.product_id;

-- Q68: Reorder Trigger Alert List
-- Explanation: Flags stock levels falling below defined local safety triggers.
SELECT s.name as store_name,
       p.name as product_name,
       p.sku,
       i.stock_level,
       i.reorder_level
FROM inventory i
JOIN stores s ON i.store_id = s.store_id
JOIN products p ON i.product_id = p.product_id
WHERE i.stock_level < i.reorder_level
ORDER BY i.stock_level ASC;

-- Q69: Inventory Turnover Ratio (ITR)
-- Explanation: Measures how fast inventory is sold and replaced over a year.
WITH cost_of_goods_sold AS (
    SELECT o.store_id,
           SUM(p.cost_price * oi.quantity) as annual_cogs
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.created_at >= NOW() - INTERVAL '1 year'
    GROUP BY 1
),
avg_inventory AS (
    SELECT store_id,
           SUM(i.stock_level * p.cost_price) as current_inv_value
    FROM inventory i
    JOIN products p ON i.product_id = p.product_id
    GROUP BY 1
)
SELECT s.name,
       cogs.annual_cogs,
       ai.current_inv_value,
       (cogs.annual_cogs / NULLIF(ai.current_inv_value, 0))::NUMERIC(10,2) as inventory_turnover_ratio
FROM stores s
JOIN cost_of_goods_sold cogs ON s.store_id = cogs.store_id
JOIN avg_inventory ai ON s.store_id = ai.store_id;

-- Q70: Slow-Moving Stock Identification (Dead Stock risk)
-- Explanation: Identifies inventory items with zero sales in the last 90 days.
WITH recent_sales AS (
    SELECT DISTINCT o.store_id, oi.product_id
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.created_at >= NOW() - INTERVAL '90 days'
)
SELECT s.name as store_name,
       p.name as product_name,
       p.sku,
       i.stock_level
FROM inventory i
JOIN stores s ON i.store_id = s.store_id
JOIN products p ON i.product_id = p.product_id
LEFT JOIN recent_sales rs ON i.store_id = rs.store_id AND i.product_id = rs.product_id
WHERE rs.product_id IS NULL
  AND i.stock_level > 0
ORDER BY i.stock_level DESC;

-- Q71: Perishable Shrinkage Risk Valuation
-- Explanation: Values stock levels of perishable goods nearing expiration or holding costs.
SELECT s.name as store_name,
       SUM(i.stock_level * p.cost_price) as perishable_inventory_cost_exposure
FROM inventory i
JOIN products p ON i.product_id = p.product_id
JOIN stores s ON i.store_id = s.store_id
WHERE p.is_perishable = TRUE
GROUP BY 1
ORDER BY 2 DESC;

-- Q72: Product Availability Rate per Store
-- Explanation: Evaluates SKU availability rate across the target product catalogs.
SELECT store_id,
       COUNT(*) as target_skus,
       COUNT(CASE WHEN stock_level > 0 THEN 1 END) as available_skus,
       ROUND((COUNT(CASE WHEN stock_level > 0 THEN 1 END)::numeric / COUNT(*)) * 100, 2) as availability_rate_pct
FROM inventory
GROUP BY 1;

-- Q73: Stock Refill Alert Matrix (Category level)
-- Explanation: Shows overall stock deficits comparing current levels to reorder goals.
SELECT p.category,
       SUM(i.stock_level) as total_stock_available,
       SUM(i.reorder_level) as aggregate_reorder_safety_limit,
       CASE 
         WHEN SUM(i.stock_level) < SUM(i.reorder_level) THEN 'RESTOCK IMMEDIATE'
         ELSE 'SAFE'
       END as status
FROM inventory i
JOIN products p ON i.product_id = p.product_id
GROUP BY 1;

-- Q74: Estimated Sales Loss from Stockouts
-- Explanation: Estimates daily revenue leakage by checking OOS products multiplied by historical run rate values.
WITH daily_run_rates AS (
    SELECT o.store_id, oi.product_id,
           SUM(oi.total_price) / 30.0 as avg_revenue_per_day
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY 1, 2
)
SELECT s.name as store_name,
       SUM(dr.avg_revenue_per_day)::NUMERIC(10,2) as daily_revenue_leakage_estimate
FROM inventory i
JOIN stores s ON i.store_id = s.store_id
JOIN daily_run_rates dr ON i.store_id = dr.store_id AND i.product_id = dr.product_id
WHERE i.stock_level = 0
GROUP BY 1
ORDER BY 2 DESC;

-- Q75: High Inventory Holding Cost Exposure
-- Explanation: Pinpoints products consuming large volumes of capital.
SELECT p.name, p.sku,
       SUM(i.stock_level * p.cost_price) as capital_locked
FROM inventory i
JOIN products p ON i.product_id = p.product_id
GROUP BY 1, 2
ORDER BY 3 DESC
LIMIT 20;

-- Q76: Store Stocking Balance Coefficient
-- Explanation: Checks if stock is distributed proportionately based on order transaction counts.
WITH store_volume AS (
    SELECT store_id, COUNT(*) as orders_count
    FROM orders
    GROUP BY 1
),
store_stock AS (
    SELECT store_id, SUM(stock_level) as total_stock
    FROM inventory
    GROUP BY 1
)
SELECT sv.store_id,
       sv.orders_count,
       ss.total_stock,
       (ss.total_stock::numeric / sv.orders_count)::NUMERIC(10,2) as stock_to_sales_coefficient
FROM store_volume sv
JOIN store_stock ss ON sv.store_id = ss.store_id;

-- Q77: Perishable vs Non-Perishable Inventory Velocity Comparison
-- Explanation: Measures how much faster fresh goods move through inventory relative to standard lines.
WITH sales_count AS (
    SELECT p.is_perishable, SUM(oi.quantity) as items_sold
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY 1
),
inv_count AS (
    SELECT p.is_perishable, SUM(i.stock_level) as items_stock
    FROM inventory i
    JOIN products p ON i.product_id = p.product_id
    GROUP BY 1
)
SELECT sc.is_perishable,
       sc.items_sold,
       ic.items_stock,
       (sc.items_sold::numeric / ic.items_stock)::NUMERIC(10,2) as relative_velocity
FROM sales_count sc
JOIN inv_count ic ON sc.is_perishable = ic.is_perishable;

-- Q78: Reorder Frequency Predictions (Category Level)
-- Explanation: Forecasts monthly replenishment events.
WITH monthly_run_rate AS (
    SELECT p.category, SUM(oi.quantity) as units_monthly
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY 1
)
SELECT m.category,
       m.units_monthly,
       SUM(i.stock_level) as current_stock,
       (SUM(i.stock_level)::numeric / NULLIF(m.units_monthly / 4.0, 0))::NUMERIC(10,1) as weeks_of_supply_remaining
FROM inventory i
JOIN products p ON i.product_id = p.product_id
JOIN monthly_run_rate m ON p.category = m.category
GROUP BY 1, 2;

-- Q79: Local Geohash Demand Clustering
-- Explanation: Identifies areas with high orders but low inventory density (geospatial demand mapping).
SELECT s.geohash,
       COUNT(o.order_id) as total_orders,
       SUM(i.stock_level) as total_stock_held
FROM orders o
JOIN stores s ON o.store_id = s.store_id
JOIN inventory i ON o.store_id = i.store_id
GROUP BY 1
ORDER BY 2 DESC;

-- Q80: ABC Inventory Classification (Pareto categorization)
-- Explanation: Segments items by cost-weighted value into class A (top 70%), B (next 20%), or C (bottom 10%).
WITH product_values AS (
    SELECT product_id,
           SUM(stock_level * price) as inv_value,
           PERCENT_RANK() OVER (ORDER BY SUM(stock_level * price) DESC) as value_pct
    FROM inventory i
    JOIN products p ON i.product_id = p.product_id
    GROUP BY 1
)
SELECT CASE 
         WHEN value_pct <= 0.70 THEN 'Class A (High Value / Strict Control)'
         WHEN value_pct BETWEEN 0.71 AND 0.90 THEN 'Class B (Medium Value)'
         ELSE 'Class C (Low Value / Loose Control)'
       END as abc_category,
       COUNT(*) as sku_count
FROM product_values
GROUP BY 1;


-- ============================================================================
-- CATEGORY 6: DELIVERY OPERATIONS & SLA PERFORMANCE (Queries 81-100)
-- ============================================================================

-- Q81: Delivery SLA Compliance Rate (Within 20 Mins threshold)
-- Explanation: The foundational metric for Quick Commerce (e.g. Blinkit/Swiggy 20-min target).
SELECT s.city,
       COUNT(d.delivery_id) as total_deliveries,
       COUNT(CASE WHEN d.transit_time_seconds <= 1200 THEN 1 END) as compliant_deliveries,
       ROUND((COUNT(CASE WHEN d.transit_time_seconds <= 1200 THEN 1 END)::numeric / COUNT(d.delivery_id)) * 100, 2) as sla_compliance_pct
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
JOIN stores s ON o.store_id = s.store_id
GROUP BY 1;

-- Q82: Average Transit Time by Store Location
-- Explanation: Evaluates logistics bottlenecks at specific store hubs.
SELECT s.name as store_name,
       s.city,
       (AVG(d.transit_time_seconds) / 60.0)::NUMERIC(10,2) as avg_transit_minutes,
       (MAX(d.transit_time_seconds) / 60.0)::NUMERIC(10,2) as max_transit_minutes
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
JOIN stores s ON o.store_id = s.store_id
GROUP BY 1, 2
ORDER BY 3 DESC;

-- Q83: Hourly Delivery Performance Degradation
-- Explanation: Tracks if traffic or peak lunch/dinner orders cause SLA delays.
SELECT EXTRACT(HOUR FROM o.created_at) as hour_of_day,
       AVG(d.transit_time_seconds / 60.0)::NUMERIC(10,1) as average_delivery_time_mins,
       COUNT(o.order_id) as volume
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
GROUP BY 1
ORDER BY 1;

-- Q84: Delivery Rider Performance Leaderboard (Rating & Velocity)
-- Explanation: Monitors delivery partner efficiencies for incentive structures.
SELECT delivery_partner_id,
       COUNT(delivery_id) as total_deliveries,
       AVG(rating)::NUMERIC(10,2) as average_rating,
       AVG(transit_time_seconds / 60.0)::NUMERIC(10,1) as avg_minutes_per_ride
FROM deliveries
GROUP BY 1
HAVING COUNT(delivery_id) >= 50
ORDER BY 3 DESC, 4 ASC
LIMIT 20;

-- Q85: SLA Failure Cost Analysis (Cancellation refunds for late deliveries)
-- Explanation: Measures GMV lost to cancellation during transit.
SELECT DATE_TRUNC('month', o.created_at) as order_month,
       COUNT(CASE WHEN o.status = 'cancelled' AND d.picked_up_at IS NOT NULL THEN 1 END) as in_transit_cancellations,
       SUM(CASE WHEN o.status = 'cancelled' AND d.picked_up_at IS NOT NULL THEN o.total_amount ELSE 0 END) as wasted_inventory_exposure
FROM orders o
JOIN deliveries d ON o.order_id = d.order_id
GROUP BY 1
ORDER BY 1;

-- Q86: Delivery Times vs Order Size (Heavy Carts vs Speed)
-- Explanation: Investigates if large item counts slow down transit speeds.
SELECT CASE 
         WHEN quantity_bucket <= 2 THEN 'Small (1-2 items)'
         WHEN quantity_bucket BETWEEN 3 AND 6 THEN 'Medium (3-6 items)'
         ELSE 'Large (7+ items)'
       END as order_size_class,
       AVG(transit_time_seconds / 60.0)::NUMERIC(10,2) as avg_transit_minutes
FROM (
    SELECT d.transit_time_seconds, SUM(oi.quantity) as quantity_bucket
    FROM deliveries d
    JOIN order_items oi ON d.order_id = oi.order_id
    GROUP BY d.delivery_id, d.transit_time_seconds
) t
GROUP BY 1;

-- Q87: SLA Compliance on Rainy/Peak Seasons (Anomaly periods)
-- Explanation: Measures performance during seasonal monsoon peak periods (Jul/Aug) where operations get disrupted.
SELECT CASE 
         WHEN EXTRACT(MONTH FROM o.created_at) IN (7, 8) THEN 'Monsoon Season'
         ELSE 'Standard Operations'
       END as period,
       COUNT(d.delivery_id) as deliveries_count,
       AVG(d.transit_time_seconds / 60.0)::NUMERIC(10,1) as avg_minutes
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
GROUP BY 1;

-- Q88: Customer Tier Priority Delivery Service Verification
-- Explanation: Assesses if Gold-tier members get dispatched faster or receive better ratings.
SELECT c.customer_tier,
       AVG(d.transit_time_seconds / 60.0)::NUMERIC(10,2) as avg_delivery_minutes,
       AVG(d.rating)::NUMERIC(10,2) as average_delivery_rating
FROM orders o
JOIN deliveries d ON o.order_id = d.order_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY 1;

-- Q89: Late Delivery Rate (Percentage of orders exceeding 30 mins)
-- Explanation: Identifies critical failures where riders take more than 30 minutes.
SELECT s.city,
       COUNT(d.delivery_id) as total_deliveries,
       COUNT(CASE WHEN d.transit_time_seconds > 1800 THEN 1 END) as extreme_delays,
       ROUND((COUNT(CASE WHEN d.transit_time_seconds > 1800 THEN 1 END)::numeric / COUNT(d.delivery_id)) * 100, 2) as extreme_delay_pct
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
JOIN stores s ON o.store_id = s.store_id
GROUP BY 1;

-- Q90: Route Efficiency (Average transit time per Geohash cluster)
-- Explanation: pinpoints delivery issues in specific local neighborhoods.
SELECT s.geohash as store_geohash,
       AVG(d.transit_time_seconds / 60.0)::NUMERIC(10,2) as avg_transit_minutes
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
JOIN stores s ON o.store_id = s.store_id
GROUP BY 1
ORDER BY 2 DESC
LIMIT 20;

-- Q91: Rider Utilization Rate (Deliveries completed per active partner)
-- Explanation: Shows the activity rate of active delivery riders.
SELECT delivery_partner_id,
       COUNT(delivery_id) as deliveries_completed,
       EXTRACT(day from (MAX(completed_at) - MIN(picked_up_at))) as active_tenure_days
FROM deliveries
GROUP BY 1
HAVING EXTRACT(day from (MAX(completed_at) - MIN(picked_up_at))) > 0
ORDER BY 2 DESC
LIMIT 20;

-- Q92: Average Packing Latency (Order placed to Rider Pick Up)
-- Explanation: Measures warehouse packing performance inside dark stores.
SELECT o.store_id,
       s.name as store_name,
       AVG(EXTRACT(epoch FROM (d.picked_up_at - o.created_at)) / 60.0)::NUMERIC(10,2) as avg_packing_minutes
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
JOIN stores s ON o.store_id = s.store_id
WHERE d.picked_up_at IS NOT NULL
GROUP BY 1, 2
ORDER BY 3 DESC;

-- Q93: Delivery Performance on Weekend Dinners (Friday-Sunday 6 PM - 10 PM)
-- Explanation: Isolates SLA metric compliance during the busiest weekly window.
SELECT s.city,
       COUNT(d.delivery_id) as weekend_dinner_deliveries,
       AVG(d.transit_time_seconds / 60.0)::NUMERIC(10,1) as avg_delivery_minutes,
       COUNT(CASE WHEN d.transit_time_seconds <= 1200 THEN 1 END)::numeric / COUNT(d.delivery_id) * 100 as compliance_pct
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
JOIN stores s ON o.store_id = s.store_id
WHERE EXTRACT(ISODOW FROM o.created_at) IN (5, 6, 7)
  AND EXTRACT(HOUR FROM o.created_at) BETWEEN 18 AND 22
GROUP BY 1;

-- Q94: Delivery Delay vs Rating Correlation
-- Explanation: Checks the correlation between delivery delay and customer satisfaction score.
SELECT corr(transit_time_seconds, rating) as correlation_coefficient
FROM deliveries
WHERE rating IS NOT NULL;

-- Q95: Month-on-Month Logistics Compliance Trend
-- Explanation: Highlights scaling patterns of delivery logistics efficiency.
SELECT DATE_TRUNC('month', o.created_at) as order_month,
       AVG(d.transit_time_seconds / 60.0)::NUMERIC(10,2) as avg_delivery_minutes,
       AVG(d.rating)::NUMERIC(10,2) as avg_delivery_rating
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
GROUP BY 1
ORDER BY 1;

-- Q96: Delivery Speed Variance (Standard Deviation of Transit Times)
-- Explanation: Measures consistency in customer experience (lower deviation means more predictable ETAs).
SELECT s.city,
       AVG(d.transit_time_seconds / 60.0)::NUMERIC(10,2) as average_time_mins,
       stddev(d.transit_time_seconds / 60.0)::NUMERIC(10,2) as stddev_time_mins
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
JOIN stores s ON o.store_id = s.store_id
GROUP BY 1;

-- Q97: Cancellation Reasons during Delivery Phase
-- Explanation: Measures failure points during final transit.
SELECT s.name as store_name,
       COUNT(o.order_id) as cancelled_in_transit_orders
FROM orders o
JOIN deliveries d ON o.order_id = d.order_id
JOIN stores s ON o.store_id = s.store_id
WHERE o.status = 'cancelled'
  AND d.picked_up_at IS NOT NULL
GROUP BY 1;

-- Q98: Geohash Delivery Density vs Transit Velocity
-- Explanation: Identifies if densely ordered sectors slow down delivery speeds.
WITH geo_density AS (
    SELECT s.geohash,
           COUNT(*) as orders_count
    FROM orders o
    JOIN stores s ON o.store_id = s.store_id
    GROUP BY 1
)
SELECT gd.geohash,
       gd.orders_count,
       AVG(d.transit_time_seconds / 60.0)::NUMERIC(10,2) as avg_minutes
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
JOIN stores s ON o.store_id = s.store_id
JOIN geo_density gd ON s.geohash = gd.geohash
GROUP BY 1, 2
ORDER BY 2 DESC
LIMIT 20;

-- Q99: Delivery Partner Inactivity Alert
-- Explanation: Identifies riders who haven't completed a delivery in 14 days.
SELECT delivery_partner_id,
       MAX(completed_at) as last_completed_delivery
FROM deliveries
GROUP BY 1
HAVING MAX(completed_at) < NOW() - INTERVAL '14 days'
ORDER BY 2 ASC;

-- Q100: Overall SLA Compliance Scorecard
-- Explanation: Consolidated performance summary across the entire logistics operation.
SELECT COUNT(delivery_id) as total_deliveries_processed,
       AVG(transit_time_seconds / 60.0)::NUMERIC(10,2) as system_avg_delivery_minutes,
       COUNT(CASE WHEN transit_time_seconds <= 1200 THEN 1 END)::numeric / COUNT(delivery_id) * 100 as metrics_sla_compliance_pct,
       AVG(rating)::NUMERIC(10,2) as average_overall_customer_rating
FROM deliveries;
