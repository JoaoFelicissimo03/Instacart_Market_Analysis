-- =======================================================================================================================
-- 03_Hero_Products.sql
-- Business question: Which products and departments in a user's FIRST order are associated with the highest
-- long-term loyalty (20+ lifetime orders)?
-- -----------------------------------------------------------------------------------------------------------------------
-- How to read these metrics:
--   - Loyal user: a user with 20 or more orders in the dataset (is_loyal = 1).

--   - loyalty_rate_pct: share of a product's (or department's) first-time buyers who are loyal.

--   - lift_vs_baseline: that share divided by the share across all users. 1.00 = same as the average user.

--   - adjusted_lift: loyal users observed, divided by the loyal users we would expect if those buyers behaved like
--     the average user with the same first-basket size. Script 02 showed that bigger first baskets go with higher
--     loyalty, so a product found mostly in big baskets would look good just because of that.
--     1.00 = no effect beyond first-basket size.

--   - Results show association, not causation (see the limitations at the end).

--   - In pgAdmin only the last result of a script is displayed, so each SELECT is best run on its own.
-- =======================================================================================================================


-- =======================================================================================================================
-- STEP 0: Analytical base table - one row per user (reused by the scripts that follow)
--   first_order_id      : the user's order with order_number = 1

--   first_basket_size   : number of products in that order

--   lifetime_orders     : highest order_number of the user

--   is_loyal            : 1 if lifetime_orders >= 20, else 0

--   expected_loyal      : share of loyal users among all users with the same first-basket size (capped at 30 items).
--                         This is the loyalty an "average" user with that basket size would have.

-- =======================================================================================================================
DROP MATERIALIZED VIEW IF EXISTS user_summary;

CREATE MATERIALIZED VIEW user_summary AS
WITH first_baskets AS (
    SELECT
        o.user_id,
        o.order_id AS first_order_id,
        COUNT(*)   AS first_basket_size
    FROM orders o
    JOIN order_products_prior opp ON opp.order_id = o.order_id
    WHERE o.order_number = 1
    GROUP BY o.user_id, o.order_id
),

user_totals AS (
    SELECT
        user_id,
        MAX(order_number) AS lifetime_orders
    FROM orders
    GROUP BY user_id
),

users AS (
    SELECT
        fb.user_id,
        fb.first_order_id,
        fb.first_basket_size,
        ut.lifetime_orders,
        CASE WHEN ut.lifetime_orders >= 20 THEN 1 ELSE 0 END AS is_loyal
    FROM first_baskets fb
    JOIN user_totals ut ON fb.user_id = ut.user_id
)

SELECT
    user_id,
    first_order_id,
    first_basket_size,
    lifetime_orders,
    is_loyal,
    AVG(is_loyal) OVER (PARTITION BY LEAST(first_basket_size, 30)) AS expected_loyal
FROM users;

CREATE UNIQUE INDEX idx_user_summary_user_id     ON user_summary (user_id);
CREATE UNIQUE INDEX idx_user_summary_first_order ON user_summary (first_order_id);
ANALYZE user_summary;


-- =======================================================================================================================
-- QUERY 1: Which products in the first order are associated with the highest loyalty?
-- Only products bought by more than 1,000 first-time buyers are kept: at that size the 95% margin of error on a
-- rate around 26% is about +/- 2.7 percentage points. 'missing' and 'other' are catch-all departments, not real
-- product categories, so they are excluded.
-- Ranked by adjusted_lift, so that products that merely travel in big baskets do not dominate the list.
-- =======================================================================================================================
SELECT
    p.product_name,
    d.department,
    COUNT(*)                                                          AS first_time_buyers,
    SUM(u.is_loyal)                                                   AS loyal_users,
    ROUND(100.0 * SUM(u.is_loyal) / COUNT(*), 2)                      AS loyalty_rate_pct,
    ROUND(AVG(u.is_loyal) / (SELECT AVG(is_loyal) FROM user_summary), 2) AS lift_vs_baseline,
    ROUND(SUM(u.is_loyal) / SUM(u.expected_loyal), 2)                 AS adjusted_lift,
    ROUND(AVG(u.first_basket_size), 1)                                AS avg_first_basket_size
FROM order_products_prior opp
JOIN user_summary u ON opp.order_id = u.first_order_id      -- keeps only the lines of each user's first order
JOIN products p     ON opp.product_id = p.product_id
JOIN departments d  ON p.department_id = d.department_id
WHERE d.department NOT IN ('missing', 'other')
GROUP BY p.product_id, p.product_name, d.department
HAVING COUNT(*) > 1000
ORDER BY adjusted_lift DESC
LIMIT 25;


-- =======================================================================================================================
-- QUERY 2: Which departments in the first order are associated with the highest loyalty?
-- A department counts once per user, however many of its products are in the first basket.
-- =======================================================================================================================
WITH first_order_departments AS (
    SELECT DISTINCT
        u.user_id,
        d.department
    FROM user_summary u
    JOIN order_products_prior opp ON opp.order_id = u.first_order_id
    JOIN products p               ON opp.product_id = p.product_id
    JOIN departments d            ON p.department_id = d.department_id
    WHERE d.department NOT IN ('missing', 'other')
)

SELECT
    fod.department,
    COUNT(*)                                                          AS first_time_buyers,
    SUM(u.is_loyal)                                                   AS loyal_users,
    ROUND(100.0 * SUM(u.is_loyal) / COUNT(*), 2)                      AS loyalty_rate_pct,
    ROUND(AVG(u.is_loyal) / (SELECT AVG(is_loyal) FROM user_summary), 2) AS lift_vs_baseline,
    ROUND(SUM(u.is_loyal) / SUM(u.expected_loyal), 2)                 AS adjusted_lift,
    ROUND(AVG(u.first_basket_size), 1)                                AS avg_first_basket_size
FROM first_order_departments fod
JOIN user_summary u ON fod.user_id = u.user_id
GROUP BY fod.department
HAVING COUNT(*) > 1000
ORDER BY adjusted_lift DESC;


/* ============================================================================
   EXECUTIVE INSIGHTS: PRODUCTS
   ============================================================================
 
   1. A clear pattern: 23 of the top 25 products come from produce (13) or
      dairy eggs (10), and 18 of the 25 are organic. Five are organic milk
      variants.
 
   2. It survives the basket-size adjustment: adjusted_lift ranges from 1.25
      to 1.55 (raw lift 1.33 to 1.68). First-basket size explains a small
      part of the gap, since these buyers start with 14 to 18 items against
      11.8 for produce buyers overall, but not most of it. The highest are
      Organic Large Green Asparagus (1.55, 1,561 buyers), Organic Milk (1.51,
      1,313) and Organic Bartlett Pear (1.49, 2,039). The best supported by
      volume are Organic Strawberries (1.36, 16,464 buyers), Organic Whole
      Milk (1.30, 7,223) and Organic Blueberries (1.25, 7,102).
 
   3. The signal sits in specific products, not in whole departments: produce
      and dairy eggs as departments have an adjusted_lift of only 1.03, while
      individual organic items reach 1.25 to 1.55.
 
   4. One product breaks the pattern: Sparkling Mineral Water has small first
      baskets (9.7 items) and still an adjusted_lift of 1.26, so basket size
      does not explain it. With 1,101 buyers it deserves caution.
 
   ============================================================================
   EXECUTIVE INSIGHTS: DEPARTMENTS
   ============================================================================
 
   5. Only two departments stand clearly above the average user: 'babies'
      (34.92%, lift 1.34, adjusted 1.25) and 'bulk' (34.25%, lift 1.31,
      adjusted 1.23). About a quarter of each gap is explained by larger
      first baskets (16.3 and 15.0 items). 'bulk' has only 1,714 buyers, so
      its rate is noisier.
 
   6. Once basket size is accounted for, 15 of the 19 departments sit within
      10% of the average user (adjusted_lift between 0.90 and 1.03). The
      first-basket department separates users much less than the product.
 
   7. 'alcohol' is the lowest (20.58%, lift 0.79, adjusted 0.79). Its first
      baskets are small (9.4 items), but basket size does not explain the
      gap, since the adjusted value equals the raw one. This is not a verdict
      on the segment's value: the dataset has no prices or revenue.
 
   READING THE RESULTS
   - Association, not causation. A plausible reading is that fresh,
     perishable items in a first order signal someone using the service for
     their regular grocery shop (and that 'babies' reflects recurring needs
     such as formula and diapers), but the data cannot confirm why.
   - The exact order within the top 25 should not be over-read: ranking many
     products by a ratio favours some lucky ones, and the smallest groups have
     about 1,100 buyers. The overall pattern matters more than the position.
 
   LIMITATIONS
   - Every user has between 4 and 100 orders, so users who left after one to
     three orders are not in the data.
   - adjusted_lift only accounts for first-basket size. Household size,
     income and other factors can still explain part of the differences.
   - The 1,000-buyer threshold limits noise but is a judgement call.
   ============================================================================ */
