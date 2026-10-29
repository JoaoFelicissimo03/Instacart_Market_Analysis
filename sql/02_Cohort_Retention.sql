-- =======================================================================================================================
-- 02_Cohort_Retention.sql
-- Business question: Is the size of a user's first basket associated with how many orders they go on to place
-- (a proxy for long-term engagement)?
-- -----------------------------------------------------------------------------------------------------------------------
-- How to read these metrics:
--   - Cohort: size of the user's FIRST basket (number of products in the order with order_number = 1).
--   - lifetime_orders: the user's highest order_number in the dataset.
--   - The dataset only contains users with 4 to 100 orders, so there are no one-time buyers: every user has already
--     come back at least 3 times. The pct_*plus_orders columns therefore measure how many orders users went on to
--     place (engagement), not the probability of returning after a first purchase.
--   - lift_20plus_vs_baseline: the cohort's share of users with 20+ orders divided by the same share across all
--     users. 1.00 means no difference from the average user.
--   - Results show association, not causation: a big first basket may simply reflect a bigger household.
-- =======================================================================================================================

-- STEP 1: Size of every user's first basket
-- (the first order always belongs to order_products_prior, because every user has at least 4 orders)
WITH first_orders AS (
    SELECT
        o.user_id,
        COUNT(opp.product_id) AS first_basket_size
    FROM orders o
    JOIN order_products_prior opp ON o.order_id = opp.order_id
    WHERE o.order_number = 1
    GROUP BY o.user_id
),

-- STEP 2: Total number of orders per user (a single pass over orders)
user_totals AS (
    SELECT
        user_id,
        MAX(order_number) AS lifetime_orders
    FROM orders
    GROUP BY user_id
),

-- STEP 3: Assign every user to a cohort based on their first basket
user_lifecycle AS (
    SELECT
        f.user_id,
        CASE
            WHEN f.first_basket_size BETWEEN 1 AND 5   THEN '1. Small (1-5 items)'
            WHEN f.first_basket_size BETWEEN 6 AND 10  THEN '2. Medium (6-10 items)'
            WHEN f.first_basket_size BETWEEN 11 AND 15 THEN '3. Large (11-15 items)'
            ELSE '4. Extra large (16+ items)'
        END AS onboarding_cohort,
        t.lifetime_orders
    FROM first_orders f
    JOIN user_totals t ON f.user_id = t.user_id
),

-- STEP 4: Share of users reaching each order-count threshold, per cohort
-- ROLLUP adds one extra row for all users together, which serves as the baseline
-- (its label starts with '0.' so it sorts first).
cohort_metrics AS (
    SELECT
        COALESCE(onboarding_cohort, '0. All users (baseline)') AS cohort,
        COUNT(*) AS total_users,
        ROUND(100.0 * COUNT(*) FILTER (WHERE lifetime_orders >= 10) / COUNT(*), 2) AS pct_10plus_orders,
        ROUND(100.0 * COUNT(*) FILTER (WHERE lifetime_orders >= 20) / COUNT(*), 2) AS pct_20plus_orders,
        ROUND(100.0 * COUNT(*) FILTER (WHERE lifetime_orders >= 50) / COUNT(*), 2) AS pct_50plus_orders,
        ROUND(AVG(lifetime_orders), 1) AS avg_lifetime_orders,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY lifetime_orders)::NUMERIC, 1) AS median_lifetime_orders
    FROM user_lifecycle
    GROUP BY ROLLUP (onboarding_cohort)
)

-- STEP 5: Compare each cohort with the baseline row (the first row of the ordered result)
SELECT
    cohort AS onboarding_cohort,
    total_users,
    pct_10plus_orders,
    pct_20plus_orders,
    pct_50plus_orders,
    ROUND(pct_20plus_orders / FIRST_VALUE(pct_20plus_orders) OVER (ORDER BY cohort), 2) AS lift_20plus_vs_baseline,
    avg_lifetime_orders,
    median_lifetime_orders
FROM cohort_metrics
ORDER BY cohort;

/* ============================================================================
   EXECUTIVE INSIGHTS
   ============================================================================

   1. A consistent gradient: the share of users reaching 10+, 20+ and 50+
      orders rises with every step up in first-basket size. Users who started
      with 16+ items reach 20+ orders at 29.48%, against 22.84% for users who
      started with 1-5 items (lift 1.13 vs 0.87 around a 26.15% baseline).

   2. The clearest signal is at the low end: the biggest jump is between the
      1-5 item cohort and the 6-10 item cohort (+3.6 percentage points at 20+
      orders). Above 10 items each step adds less (+1.3 and +1.8 points), and
      at 50+ orders the 6-10 and 11-15 cohorts are practically the same
      (5.71% vs 5.89%).

   3. A modest effect: median lifetime orders is 10 in the two smaller cohorts
      and 11 in the two larger ones, and averages only range from 15.3 to 17.8
      orders. The gap is mostly in the tails (6.54% of the 16+ cohort reaches
      50+ orders vs 4.59% of the 1-5 cohort). Averages sit well above medians
      (16.6 vs 10 overall), so a minority of heavy users pulls them up.

   4. Association, not proof of a cause: first-basket size probably reflects
      household size or shopping intent, which also drive order frequency.
      This analysis cannot tell whether encouraging bigger first baskets would
      raise loyalty. A first basket of 1-5 items is the weakest segment
      (below baseline at every threshold), which makes it a candidate for an
      onboarding experiment (A/B test) rather than a proven lever.

   LIMITATIONS
   - Every user has between 4 and 100 orders, so users who left after one to
     three orders are not in the data, and the 100-order cap truncates the
     heaviest users.
   - The metric counts orders, not time or revenue (the dataset has neither
     real dates nor prices).
   ============================================================================ */
