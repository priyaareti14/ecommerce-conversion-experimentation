-- ============================================================
-- FILE: 13_experiment_unit_baseline.sql
-- ============================================================

-- Purpose: Define a clean user-level experiment population.
-- Each user enters once, at the first eligible shipping-stage session.
-- Verified: 9,552 eligible users | 5,459 payment users | 3,851 purchase users
-- Shipping-to-payment baseline = 57.15%
-- Payment-to-purchase guardrail baseline = 70.54%

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
payment_stage AS (
  SELECT e.user_pseudo_id, e.ga_session_id, MIN(e.event_timestamp) AS payment_ts
  FROM events e
  JOIN eligible_users u
    ON e.user_pseudo_id = u.user_pseudo_id
   AND e.ga_session_id = u.ga_session_id
  WHERE e.event_name = 'add_payment_info'
    AND e.event_timestamp >= u.shipping_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),
purchase_stage AS (
  SELECT e.user_pseudo_id, e.ga_session_id, MIN(e.event_timestamp) AS purchase_ts
  FROM events e
  JOIN payment_stage p
    ON e.user_pseudo_id = p.user_pseudo_id
   AND e.ga_session_id = p.ga_session_id
  WHERE e.event_name = 'purchase'
    AND e.event_timestamp >= p.payment_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
)
SELECT
  COUNT(*) AS eligible_users,
  COUNT(p.ga_session_id) AS payment_users,
  COUNT(pu.ga_session_id) AS purchase_users,
  ROUND(100 * SAFE_DIVIDE(COUNT(p.ga_session_id), COUNT(*)), 2) AS shipping_to_payment_rate,
  ROUND(100 * SAFE_DIVIDE(COUNT(pu.ga_session_id), COUNT(p.ga_session_id)), 2) AS payment_to_purchase_rate
FROM eligible_users u
LEFT JOIN payment_stage p USING (user_pseudo_id, ga_session_id)
LEFT JOIN purchase_stage pu USING (user_pseudo_id, ga_session_id);
