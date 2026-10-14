-- ===================================================================================================================================================================
-- Business Question: Which specific products act as "Gateways"? What items in a user's FIRST order yield the highest long-term retention rate (20+ lifetime orders)?
-- ===================================================================================================================================================================

-- STEP 1: Define which users became highly loyal (20+ orders)
WITH user_loyalty AS (
    SELECT 
        user_id,
        MAX(order_number) AS total_lifetime_orders,
        CASE WHEN MAX(order_number) >= 20 THEN 1 ELSE 0 END AS is_loyal
    FROM orders
    GROUP BY user_id
),

-- STEP 2: Isolate the products purchased in everyone's VERY FIRST order
first_order_products AS (
    SELECT 
        o.user_id,
        opp.product_id
    FROM orders o
    JOIN order_products_prior opp ON o.order_id = opp.order_id
    WHERE o.order_number = 1
)

-- STEP 3: Join everything to calculate the retention rate per product
SELECT 
    p.product_name,
    d.department,
    COUNT(DISTINCT fop.user_id) AS total_first_time_buyers,
    SUM(ul.is_loyal) AS loyal_users_acquired,
    
    -- Calculate retention rate driven by this specific product
    ROUND(SUM(ul.is_loyal) * 100.0 / COUNT(DISTINCT fop.user_id), 2) AS product_retention_rate_pct

FROM first_order_products fop
JOIN user_loyalty ul ON fop.user_id = ul.user_id
JOIN products p ON fop.product_id = p.product_id
JOIN departments d ON p.department_id = d.department_id

-- Filter out niche products to ensure statistical significance (minimum 1000 first-time buyers)
GROUP BY p.product_id, p.product_name, d.department
HAVING COUNT(DISTINCT fop.user_id) > 1000

-- Rank the highest retaining products at the top
ORDER BY product_retention_rate_pct DESC
LIMIT 25;



-- ==================================================================================================================
-- Business Question: Which product departments in a user's FIRST order generate the most loyal long-term customers?
-- ==================================================================================================================

WITH user_loyalty AS (
    SELECT 
        user_id,
        CASE WHEN MAX(order_number) >= 20 THEN 1 ELSE 0 END AS is_loyal
    FROM orders
    GROUP BY user_id
),

-- Isolate the distinct departments present in everyone's VERY FIRST order
first_order_departments AS (
    SELECT DISTINCT
        o.user_id,
        d.department
    FROM orders o
    JOIN order_products_prior opp ON o.order_id = opp.order_id
    JOIN products p ON opp.product_id = p.product_id
    JOIN departments d ON p.department_id = d.department_id
    WHERE o.order_number = 1
)

SELECT 
    fod.department,
    COUNT(DISTINCT fod.user_id) AS total_first_time_buyers,
    SUM(ul.is_loyal) AS loyal_users_acquired,
    
    -- Calculate retention rate driven by this specific department
    ROUND(SUM(ul.is_loyal) * 100.0 / COUNT(DISTINCT fod.user_id), 2) AS department_retention_rate_pct

FROM first_order_departments fod
JOIN user_loyalty ul ON fod.user_id = ul.user_id

-- Filter to ensure statistical significance
GROUP BY fod.department
HAVING COUNT(DISTINCT fod.user_id) > 1000
ORDER BY department_retention_rate_pct DESC;



/* ============================================================================
   EXECUTIVE INSIGHTS: THE HABIT vs. CONVENIENCE DIVIDE
   ============================================================================
   1. The Organic Trust Factor: At the product level, Organic Produce and 
      Dairy dominate the top 25. First-time buyers trusting the platform with 
      expensive perishables are actively shifting their primary grocery routine.
      
   2. The "New Parent" Anchor: The 'babies' department is the ultimate retention 
      driver (34.92%). Marketing should aggressively target new parents, as 
      their lack of time translates into high-frequency, sticky behavior.
      
   3. The Convenience Trap: 'Alcohol' (20.58%) yields the lowest loyalty. 
      Acquisition campaigns focusing on weekend alcohol delivery attract 
      low-LTV (Lifetime Value) users and should be deprioritized.
   ============================================================================ */
