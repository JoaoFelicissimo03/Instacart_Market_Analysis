-- =======================================================================================================================
-- 05_Survival_Matrix.sql
-- Business question: How quickly do users come back after their first order, and how long do they stay active,
-- depending on the size of their first basket?
-- -----------------------------------------------------------------------------------------------------------------------
-- Requires: the user_summary materialized view created in STEP 0 of 03_Hero_Products.sql.
--
-- About the time data (read this first):
--   The dataset has no calendar dates, only days_since_prior_order: the gap in days since the user's previous order.
--   That gap is capped at 30, so a value of 30 means "30 days or more". Two consequences:
--   - A gap below 30 is exact. Everything about the time to the SECOND order is therefore exact below 30 days,
--     and all longer gaps fall into one "30 or more" bucket (QUERY 1).
--   - Adding gaps over several orders gives a LOWER BOUND of the real elapsed time, because every capped gap hides an
--     unknown extra. "The user stayed at least 90 days" is a safe statement (QUERY 2); placing later orders inside
--     exact day windows (for example "active between day 31 and 60") is not, so no such windows are used. A window
--     for the first 30 days would also be 100% by construction: every second order has a gap of at most 30.
--
-- Cohorts are the same first-basket-size groups used in script 02. The first row (all users) is the baseline.
-- Results show association, not causation (see the limitations at the end).
-- =======================================================================================================================


-- =======================================================================================================================
-- QUERY 1: Time to the second order (exact below 30 days)
--   pct_back_within_N_days     : share of users whose second order came N days or less after the first
--   pct_back_after_30_plus     : share whose gap was capped, i.e. 30 days or more
--   median_days_to_second_order: exact as long as the median is below 30
-- =======================================================================================================================
WITH second_orders AS (
    SELECT
        user_id,
        days_since_prior_order AS days_to_second_order
    FROM orders
    WHERE order_number = 2
),

user_cohorts AS (
    SELECT
        s.days_to_second_order,
        CASE
            WHEN u.first_basket_size BETWEEN 1 AND 5   THEN '1. Small (1-5 items)'
            WHEN u.first_basket_size BETWEEN 6 AND 10  THEN '2. Medium (6-10 items)'
            WHEN u.first_basket_size BETWEEN 11 AND 15 THEN '3. Large (11-15 items)'
            ELSE '4. Extra large (16+ items)'
        END AS onboarding_cohort
    FROM second_orders s
    JOIN user_summary u ON s.user_id = u.user_id
)

-- ROLLUP adds one row for all users together (the baseline, which sorts first)
SELECT
    COALESCE(onboarding_cohort, '0. All users (baseline)') AS onboarding_cohort,
    COUNT(*) AS total_users,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second_order <= 7)  / COUNT(*), 2) AS pct_back_within_7_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second_order <= 14) / COUNT(*), 2) AS pct_back_within_14_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second_order <= 21) / COUNT(*), 2) AS pct_back_within_21_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second_order >= 30) / COUNT(*), 2) AS pct_back_after_30_plus,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_second_order)::NUMERIC, 1) AS median_days_to_second_order
FROM user_cohorts
GROUP BY ROLLUP (onboarding_cohort)
ORDER BY onboarding_cohort;


-- =======================================================================================================================
-- QUERY 2: Tenure (survival curve) - how long users are confirmed to have stayed
--   tenure_days = days between the first and the last order, as the sum of the gaps. This is a LOWER BOUND of the
--   real tenure (capped gaps hide extra days), so every percentage below is the share of users CONFIRMED to have
--   stayed at least that long; the real share is equal or higher.
--   Unlike an activity window, this can only fall as the threshold grows, which is what makes it a survival curve.
-- =======================================================================================================================
WITH user_tenure AS (
    SELECT
        user_id,
        SUM(days_since_prior_order)::INTEGER AS tenure_days   -- SUM ignores the NULL gap of the first order
    FROM orders
    GROUP BY user_id
),

user_cohorts AS (
    SELECT
        t.tenure_days,
        CASE
            WHEN u.first_basket_size BETWEEN 1 AND 5   THEN '1. Small (1-5 items)'
            WHEN u.first_basket_size BETWEEN 6 AND 10  THEN '2. Medium (6-10 items)'
            WHEN u.first_basket_size BETWEEN 11 AND 15 THEN '3. Large (11-15 items)'
            ELSE '4. Extra large (16+ items)'
        END AS onboarding_cohort
    FROM user_tenure t
    JOIN user_summary u ON t.user_id = u.user_id
)

SELECT
    COALESCE(onboarding_cohort, '0. All users (baseline)') AS onboarding_cohort,
    COUNT(*) AS total_users,
    ROUND(100.0 * COUNT(*) FILTER (WHERE tenure_days >= 30) / COUNT(*), 2) AS pct_tenure_30plus,
    ROUND(100.0 * COUNT(*) FILTER (WHERE tenure_days >= 60) / COUNT(*), 2) AS pct_tenure_60plus,
    ROUND(100.0 * COUNT(*) FILTER (WHERE tenure_days >= 90) / COUNT(*), 2) AS pct_tenure_90plus,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tenure_days)::NUMERIC, 1) AS median_tenure_days_lower_bound
FROM user_cohorts
GROUP BY ROLLUP (onboarding_cohort)
ORDER BY onboarding_cohort;


-- =======================================================================================================================
-- QUERY 3: How often does the 30-day cap apply?
-- Every gap of exactly 30 hides an unknown number of extra days, which is why QUERY 2 is a lower bound.
-- =======================================================================================================================
SELECT
    COUNT(days_since_prior_order)                                      AS orders_with_a_gap,
    COUNT(*) FILTER (WHERE days_since_prior_order = 30)                AS orders_at_cap,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_since_prior_order = 30)
          / COUNT(days_since_prior_order), 2)                          AS pct_orders_at_cap,
    ROUND(100.0 * COUNT(DISTINCT user_id) FILTER (WHERE days_since_prior_order = 30)
          / COUNT(DISTINCT user_id), 2)                                AS pct_users_with_a_capped_gap
FROM orders;


/* ============================================================================
   EXECUTIVE INSIGHTS
   ============================================================================

   1. The second order is the slow step: 32.58% of users place it within 7
      days, 55.75% within 14 and 68.21% within 21, while 23.20% wait 30 days
      or more (median 13 days). The 30-day cap applies to 23.20% of second-order
      gaps but only to about 10.7% of all later gaps, so coming back for the
      first time takes longer than coming back afterwards.

   2. Small first baskets are the slow cohort: 52.93% of users with 1-5 items
      are back within 14 days (56.52% to 57.22% in the other cohorts) and
      25.64% wait 30 days or more (21.84% to 22.38%). The median is 14 days
      against 12 to 13. With 40,000 to 64,000 users per cohort, these gaps are
      well above sampling noise.

   3. There is no gradient above 5 items: the 6-10, 11-15 and 16+ cohorts are
      within about one point of each other at 14 days and at 30+ days, and in
      the first week the 16+ cohort is slower than the 6-10 cohort (31.07% vs
      34.07%). A possible reading, not tested here, is that users who stock up
      in a large first order need the next one later.

   4. Tenure rises with basket size, but only slightly: the share confirmed to
      stay at least 90 days is 73.55% for 1-5 items and 76.33% for 16+ items
      (median lower bound 140 vs 168 days). At 30 and 60 days the differences
      are under 0.6 points. Tenure grows with the number of orders, so this
      partly restates script 02.

   5. Across scripts 02 to 05: first-basket size is associated with how many
      orders users go on to place, but the link with the speed of coming back
      is mostly "a small first basket is slower", not "a bigger one is
      faster". This is an association, not a cause: basket size probably
      reflects household size or shopping intent. A nudge for users with a
      small first basket (for example a reminder around day 10 to 14) is a
      candidate for an A/B test, not a proven lever.

   LIMITATIONS
   - Time is approximate: gaps are capped at 30 days (11.49% of all gaps, and
     73.72% of users have at least one). The time to the second order is
     exact below 30 days; tenure is a lower bound of the real value.
   - Every user has between 4 and 100 orders, so users who left after one to
     three orders are not in the data. Return times and tenure describe users
     who had already come back several times.
   - Tenure is measured up to each user's last order in the dataset, not up to
     a common end date, so it is not churn at a calendar date.
   - The dataset has no prices, so nothing here says anything about revenue.
   ============================================================================ */
