-- =======================================================================================================================
-- Business Question: Does the size of a user's first basket impact their long-term retention (probability of returning)?
-- =======================================================================================================================

-- STEP 1: Isolate the very first order for every user and calculate its basket size
WITH first_orders AS (
    SELECT 
        o.user_id,
        o.order_id,
        COUNT(opp.product_id) AS first_basket_size
    FROM orders o
    JOIN order_products_prior opp ON o.order_id = opp.order_id
    WHERE o.order_number = 1
    GROUP BY o.user_id, o.order_id
),

-- STEP 2: Segment users into Cohorts based on their first experience 
-- and find the maximum number of orders they eventually placed
user_lifecycle AS (
    SELECT 
        f.user_id,
        CASE 
            WHEN f.first_basket_size <= 5 THEN '1. Small (1-5 items)'
            WHEN f.first_basket_size BETWEEN 6 AND 15 THEN '2. Medium (6-15 items)'
            ELSE '3. Large (16+ items)' 
        END AS onboarding_cohort,
        MAX(o.order_number) AS lifetime_orders
    FROM first_orders f
    JOIN orders o ON f.user_id = o.user_id
    GROUP BY f.user_id, f.first_basket_size
)

-- STEP 3: Calculate the conversion funnel and retention rate per cohort
SELECT 
    onboarding_cohort,
    COUNT(user_id) AS total_acquired_users,
    
    -- Adjusted KPIs to bypass the 4-order dataset minimum
    SUM(CASE WHEN lifetime_orders >= 10 THEN 1 ELSE 0 END) AS loyal_10_orders,
    SUM(CASE WHEN lifetime_orders >= 20 THEN 1 ELSE 0 END) AS loyal_20_orders,
    SUM(CASE WHEN lifetime_orders >= 50 THEN 1 ELSE 0 END) AS power_users_50_orders,
    
    -- Conversion Rates
    ROUND(SUM(CASE WHEN lifetime_orders >= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(user_id), 2) AS retention_10_pct,
    ROUND(SUM(CASE WHEN lifetime_orders >= 20 THEN 1 ELSE 0 END) * 100.0 / COUNT(user_id), 2) AS retention_20_pct,
    ROUND(SUM(CASE WHEN lifetime_orders >= 50 THEN 1 ELSE 0 END) * 100.0 / COUNT(user_id), 2) AS power_user_pct

FROM user_lifecycle
GROUP BY onboarding_cohort
ORDER BY onboarding_cohort;

/* ============================================================================
   EXECUTIVE INSIGHTS
   ============================================================================
   
   1. Realistic B2C Funnel: The retention curve demonstrates a natural drop-off, 
      stabilizing at around 4.5% - 6.5% for true 'Power Users' (50+ orders).
	  
   2. Strategic Validation: The business hypothesis is proven correct. Larger 
      initial baskets (16+ items) consistently yield higher long-term retention 
      at every lifecycle stage (10, 20, and 50 orders) compared to small baskets.
   ============================================================================ */
