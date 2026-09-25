-- ============================================================
-- FILE: 14_experiment_population_aa.sql
-- ============================================================

-- Purpose: Build the user-level experiment population and assign each eligible
-- user deterministically to one of two 50/50 A/A groups.
-- Verified:
-- A: 4,772 users | 2,756 payment users | 57.75% payment conversion
-- B: 4,780 users | 2,703 payment users | 56.55% payment conversion

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE event_name IN ('view_item','add_shipping_info','add_payment_info','purchase')
),
view_stage AS (
  SELECT user_pseudo_id, ga_session_id, MIN(event_timestamp) AS view_ts
  FROM events
  WHERE event_name = 'view_item' AND ga_session_id IS NOT NULL
  GROUP BY user_pseudo_id, ga_session_id
),
shipping_stage AS (
  SELECT e.user_pseudo_id, e.ga_session_id, MIN(e.event_timestamp) AS shipping_ts
  FROM events e
  JOIN view_stage v
    ON e.user_pseudo_id = v.user_pseudo_id
   AND e.ga_session_id = v.ga_session_id
  WHERE e.event_name = 'add_shipping_info'
    AND e.event_timestamp >= v.view_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),
ranked_eligibility AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    shipping_ts,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY shipping_ts, ga_session_id
    ) AS eligibility_rank
  FROM shipping_stage
),
eligible_users AS (
  SELECT user_pseudo_id, ga_session_id, shipping_ts
  FROM ranked_eligibility
  WHERE eligibility_rank = 1
),
experiment_population AS (
  SELECT
    u.user_pseudo_id,
    u.ga_session_id,
    CASE
      WHEN MOD(ABS(FARM_FINGERPRINT(u.user_pseudo_id)), 2) = 0 THEN 'A'
      ELSE 'B'
    END AS aa_group,
    MAX(IF(e.event_name = 'add_payment_info' AND e.event_timestamp >= u.shipping_ts, 1, 0)) AS payment_conversion,
    MAX(IF(e.event_name = 'purchase' AND e.event_timestamp >= u.shipping_ts, 1, 0)) AS purchase_conversion
  FROM eligible_users u
  LEFT JOIN events e
    ON u.user_pseudo_id = e.user_pseudo_id
   AND u.ga_session_id = e.ga_session_id
  GROUP BY u.user_pseudo_id, u.ga_session_id
)
SELECT
  aa_group,
  COUNT(*) AS users,
  SUM(payment_conversion) AS payment_users,
  ROUND(100 * AVG(payment_conversion), 2) AS payment_conversion_rate,
  SUM(purchase_conversion) AS purchase_users,
  ROUND(100 * AVG(purchase_conversion), 2) AS purchase_conversion_rate
FROM experiment_population
GROUP BY aa_group
ORDER BY aa_group;
