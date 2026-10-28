-- =======================================================================================================================
-- 04_Cross_Selling_Pairs.sql
-- Business question: In first orders that include a baby product, which product pairs (with at least one baby
-- product in the pair) are associated with the highest long-term loyalty (20+ lifetime orders)?
-- -----------------------------------------------------------------------------------------------------------------------
-- Requires: the user_summary materialized view created in STEP 0 of 03_Hero_Products.sql.
--
-- How to read these metrics:
--   - Pair: two different products bought together in a user's first order, at least one of them from the
--     'babies' department.

--   - loyalty_rate_pct: share of the users who bought the pair in their first order that are loyal.

--   - expected_rate_pct: the share we would expect if those users behaved like the average user with the same
--     first-basket size (script 03 explains why this matters).

--   - adjusted_lift: loyalty_rate_pct / expected_rate_pct. 1.00 = no effect beyond first-basket size.

--   - adjusted_lift_conservative: the same ratio, but using the lower end of a 95% confidence interval (Wilson)
--     for the loyalty rate. Pairs are ranked by this column, so a pair only ranks high if it is both high and well
--     supported by data. Ranking by the plain rate would reward pairs that are high by chance, because only about
--     9,000 users have a baby product in their first order and each pair is bought by a small share of them.

--   - Results show association, not causation (see the limitations at the end).
-- =======================================================================================================================
 
-- STEP 1: First orders that contain at least one product from the 'babies' department
WITH baby_first_orders AS (
    SELECT DISTINCT
        u.first_order_id
    FROM user_summary u
    JOIN order_products_prior opp ON opp.order_id = u.first_order_id
    JOIN products p               ON opp.product_id = p.product_id
    JOIN departments d            ON p.department_id = d.department_id
    WHERE d.department = 'babies'
),
 
-- STEP 2: Every product inside those baskets, with the loyalty flags of the user who placed the order
basket_items AS (
    SELECT
        u.first_order_id AS order_id,
        p.product_id,
        p.product_name,
        d.department,
        u.is_loyal,
        u.expected_loyal
    FROM baby_first_orders b
    JOIN user_summary u           ON u.first_order_id = b.first_order_id
    JOIN order_products_prior opp ON opp.order_id = b.first_order_id
    JOIN products p               ON opp.product_id = p.product_id
    JOIN departments d            ON p.department_id = d.department_id
),
 
-- STEP 3: Self-join to build the pairs. product_id < product_id counts each pair once (A+B, not also B+A).
-- Only pairs with at least one baby product are kept, and at least 50 first orders are required.
pair_stats AS (
    SELECT
        i1.product_name AS product_a,
        i1.department   AS department_a,
        i2.product_name AS product_b,
        i2.department   AS department_b,
        COUNT(*)                 AS pair_orders,
        SUM(i1.is_loyal)         AS loyal_users,
        SUM(i1.expected_loyal)   AS expected_loyal_users
    FROM basket_items i1
    JOIN basket_items i2
        ON i1.order_id = i2.order_id
       AND i1.product_id < i2.product_id
    WHERE i1.department = 'babies' OR i2.department = 'babies'
    GROUP BY i1.product_id, i1.product_name, i1.department,
             i2.product_id, i2.product_name, i2.department
    HAVING COUNT(*) >= 50
),
 
-- STEP 4: Observed rate, expected rate and the lower end of the 95% Wilson interval (z = 1.96)
pair_rates AS (
    SELECT
        *,
        loyal_users::NUMERIC / pair_orders       AS rate,
        expected_loyal_users / pair_orders       AS expected_rate,
        (loyal_users::NUMERIC / pair_orders + 1.9208 / pair_orders
            - 1.96 * SQRT((loyal_users::NUMERIC / pair_orders) * (1 - loyal_users::NUMERIC / pair_orders) / pair_orders
                          + 0.9604 / (pair_orders * pair_orders)::NUMERIC))
            / (1 + 3.8416 / pair_orders)         AS rate_lower_bound
    FROM pair_stats
)
 
-- STEP 5: Rank the pairs by the conservative adjusted lift
SELECT
    product_a,
    department_a,
    product_b,
    department_b,
    pair_orders                                  AS first_orders_with_pair,
    loyal_users,
    ROUND(100 * rate, 2)                         AS loyalty_rate_pct,
    ROUND(100 * expected_rate, 2)                AS expected_rate_pct,
    ROUND(rate / expected_rate, 2)               AS adjusted_lift,
    ROUND(rate_lower_bound / expected_rate, 2)   AS adjusted_lift_conservative
FROM pair_rates
ORDER BY adjusted_lift_conservative DESC, pair_orders DESC
LIMIT 15;


/* ============================================================================
   EXECUTIVE INSIGHTS
   ============================================================================
 
   1. Starting point: users with a baby product in their first order reach
      20+ orders at 34.92% (9,199 users, adjusted lift 1.25 in script 03),
      against 26.15% for all users. The 15 pairs below reach 47.37% to 64.71%,
      with an adjusted lift of 1.62 to 2.17 (1.20 to 1.71 on the conservative
      measure). Every pair stays above 1.00 even on the conservative measure.
 
   2. What the pairs have in common: 14 of the 15 combine a baby product with
      one of four everyday items: strawberries (5 pairs), avocado (4, including
      Organic Hass Avocado), banana (4, including Bag of Organic Bananas) and
      organic whole milk (1). The remaining pair combines two baby products.
      Three baby foods recur: Stage 1 Apples Sweet Potatoes Pumpkin &
      Blueberries (5 pairs), Stage 2 Blueberry Pear & Purple Carrot (4) and
      Organic Pears, Peas and Broccoli Puree Stage 1 (3).
 
   3. The highest pair: Stage 1 Apples Sweet Potatoes Pumpkin & Blueberries
      with Organic Avocado, where 33 of 51 users became loyal (64.71%,
      adjusted lift 2.17). With 51 first orders, the 95% interval for that
      rate runs from about 51% to 76%, so the exact value is uncertain.
 
   4. Read with caution:
      - Small groups: every pair comes from 50 to 104 first orders.
      - The pairs overlap: the same baskets appear in several pairs, so the 15
        rows are not 15 independent findings. The robust pattern is "baby food
        together with strawberries, avocado or banana", not the order of the
        list.
      - Ranking many pairs by a ratio favours some lucky ones, even with the
        conservative measure.
      - Part of each lift is the babies effect itself, since every basket here
        has a baby product. Compared with the 34.92% of all baby baskets, the
        pairs are 1.36 to 1.85 times higher, not 1.62 to 2.17.
 
   5. Not proven as a cause: strawberries, avocado, banana and whole milk are
      everyday staples, so these pairs may simply signal a household doing its
      regular grocery shop through the app. Whether suggesting one of these
      items at checkout would raise loyalty can only be answered with an
      experiment (A/B test).
 
   LIMITATIONS
   - Only about 9,000 users have a baby product in their first order, so every
     pair is bought by a small group.
   - Every user has between 4 and 100 orders, so users who left after one to
     three orders are not in the data.
   - adjusted_lift only accounts for first-basket size.
   - The dataset has no prices, so "premium" or "high-value" cannot be
     assessed, and loyalty here means order count.
   ============================================================================ */
