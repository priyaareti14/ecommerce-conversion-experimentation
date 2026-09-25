-- ============================================================
-- GA4 E-COMMERCE FUNNEL OPTIMIZATION
-- MASTER SQL FILE — UPDATED THROUGH QUERY 12
-- Dataset: bigquery-public-data.ga4_obfuscated_sample_ecommerce
-- Run ONE numbered section at a time in BigQuery Studio.
-- ============================================================

-- ============================================================
-- FILE: 01_dataset_overview.sql
-- ============================================================

-- 01_dataset_overview.sql
-- Purpose: Confirm overall dataset scale.
-- Verified result:
-- 4,295,584 events | 270,154 users | 92 days

SELECT
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS user_count,
  COUNT(DISTINCT event_date) AS day_count
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`;

-- ============================================================
-- FILE: 02_event_distribution.sql
-- ============================================================

-- 02_event_distribution.sql
-- Purpose: Inspect all GA4 event types and their frequency.

SELECT
  event_name,
  COUNT(*) AS event_count
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
GROUP BY
  event_name
ORDER BY
  event_count DESC;

-- ============================================================
-- FILE: 03_funnel_unique_users.sql
-- ============================================================

-- 03_funnel_unique_users.sql
-- Purpose: Compare raw event counts with distinct users at each funnel stage.
-- Verified purchase result:
-- 5,692 purchase events | 4,419 unique users

SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE event_name IN (
  'session_start',
  'view_item',
  'add_to_cart',
  'begin_checkout',
  'add_shipping_info',
  'add_payment_info',
  'purchase'
)
GROUP BY
  event_name
ORDER BY
  CASE event_name
    WHEN 'session_start' THEN 1
    WHEN 'view_item' THEN 2
    WHEN 'add_to_cart' THEN 3
    WHEN 'begin_checkout' THEN 4
    WHEN 'add_shipping_info' THEN 5
    WHEN 'add_payment_info' THEN 6
    WHEN 'purchase' THEN 7
  END;

-- ============================================================
-- FILE: 04_extract_session_id.sql
-- ============================================================

-- 04_extract_session_id.sql
-- Purpose: Extract GA4's nested ga_session_id from event_params using UNNEST().

SELECT
  event_name,
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE event_name IN (
  'view_item',
  'add_to_cart',
  'begin_checkout',
  'add_shipping_info',
  'add_payment_info',
  'purchase'
)
LIMIT 20;

-- ============================================================
-- FILE: 05_session_funnel_flags.sql
-- ============================================================

-- 05_session_funnel_flags.sql
-- Purpose: Collapse raw event-level data into one row per user-session
-- and create yes/no funnel-stage flags.
-- Note: This is an exploratory session view, not the final business funnel.

WITH event_data AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE event_name IN (
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'add_shipping_info',
    'add_payment_info',
    'purchase'
  )
),

session_funnel AS (
  SELECT
    user_pseudo_id,
    ga_session_id,

    MIN(IF(event_name = 'view_item',
           event_timestamp, NULL)) AS view_item_ts,

    MIN(IF(event_name = 'add_to_cart',
           event_timestamp, NULL)) AS add_to_cart_ts,

    MIN(IF(event_name = 'begin_checkout',
           event_timestamp, NULL)) AS begin_checkout_ts,

    MIN(IF(event_name = 'add_shipping_info',
           event_timestamp, NULL)) AS shipping_ts,

    MIN(IF(event_name = 'add_payment_info',
           event_timestamp, NULL)) AS payment_ts,

    MIN(IF(event_name = 'purchase',
           event_timestamp, NULL)) AS purchase_ts

  FROM event_data
  WHERE ga_session_id IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
)

SELECT
  CONCAT(
    user_pseudo_id,
    '-',
    CAST(ga_session_id AS STRING)
  ) AS session_key,

  IF(view_item_ts IS NOT NULL, 1, 0) AS viewed_product,
  IF(add_to_cart_ts IS NOT NULL, 1, 0) AS added_to_cart,
  IF(begin_checkout_ts IS NOT NULL, 1, 0) AS began_checkout,
  IF(shipping_ts IS NOT NULL, 1, 0) AS added_shipping,
  IF(payment_ts IS NOT NULL, 1, 0) AS added_payment,
  IF(purchase_ts IS NOT NULL, 1, 0) AS purchased

FROM session_funnel
LIMIT 20;

-- ============================================================
-- FILE: 06_strict_ordered_funnel.sql
-- ============================================================

-- 06_strict_ordered_funnel.sql
-- Purpose: Build a strict timestamp-gated session funnel requiring the full path:
-- view_item -> add_to_cart -> begin_checkout -> add_shipping_info
-- -> add_payment_info -> purchase.
-- Verified result:
-- 77,020 -> 15,167 -> 5,416 -> 3,119 -> 2,438 -> 1,792
-- Strict view-to-purchase = approximately 2.33%.
-- Important: Later validation showed this logic materially undercounts
-- legitimate downstream sessions, so this is retained as a data-quality check,
-- not as the final business KPI funnel.

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE event_name IN (
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'add_shipping_info',
    'add_payment_info',
    'purchase'
  )
),

view_stage AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MIN(event_timestamp) AS view_ts
  FROM events
  WHERE event_name = 'view_item'
    AND ga_session_id IS NOT NULL
  GROUP BY user_pseudo_id, ga_session_id
),

cart_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS cart_ts
  FROM events e
  JOIN view_stage v
    ON e.user_pseudo_id = v.user_pseudo_id
   AND e.ga_session_id = v.ga_session_id
  WHERE e.event_name = 'add_to_cart'
    AND e.event_timestamp >= v.view_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

checkout_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS checkout_ts
  FROM events e
  JOIN cart_stage c
    ON e.user_pseudo_id = c.user_pseudo_id
   AND e.ga_session_id = c.ga_session_id
  WHERE e.event_name = 'begin_checkout'
    AND e.event_timestamp >= c.cart_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

shipping_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS shipping_ts
  FROM events e
  JOIN checkout_stage c
    ON e.user_pseudo_id = c.user_pseudo_id
   AND e.ga_session_id = c.ga_session_id
  WHERE e.event_name = 'add_shipping_info'
    AND e.event_timestamp >= c.checkout_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

payment_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS payment_ts
  FROM events e
  JOIN shipping_stage s
    ON e.user_pseudo_id = s.user_pseudo_id
   AND e.ga_session_id = s.ga_session_id
  WHERE e.event_name = 'add_payment_info'
    AND e.event_timestamp >= s.shipping_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

purchase_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS purchase_ts
  FROM events e
  JOIN payment_stage p
    ON e.user_pseudo_id = p.user_pseudo_id
   AND e.ga_session_id = p.ga_session_id
  WHERE e.event_name = 'purchase'
    AND e.event_timestamp >= p.payment_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
)

SELECT
  (SELECT COUNT(*) FROM view_stage) AS viewed_product_sessions,
  (SELECT COUNT(*) FROM cart_stage) AS added_to_cart_sessions,
  (SELECT COUNT(*) FROM checkout_stage) AS checkout_sessions,
  (SELECT COUNT(*) FROM shipping_stage) AS shipping_sessions,
  (SELECT COUNT(*) FROM payment_stage) AS payment_sessions,
  (SELECT COUNT(*) FROM purchase_stage) AS purchase_sessions;

-- ============================================================
-- FILE: 07_device_segmentation.sql
-- ============================================================

-- 07_device_segmentation.sql
-- Purpose: Segment the strict ordered funnel by device category.
-- Device is taken deterministically from the first view_item event in the session.
-- Verified key results:
-- Desktop: view->cart 19.58%, cart->checkout 35.43%, view->purchase 2.27%
-- Mobile:  view->cart 19.90%, cart->checkout 36.14%, view->purchase 2.42%
-- Interpretation: strict-funnel behavior is broadly similar by device.

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    device.category AS device_category,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE event_name IN (
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'add_shipping_info',
    'add_payment_info',
    'purchase'
  )
),

view_stage AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    ARRAY_AGG(device_category ORDER BY event_timestamp LIMIT 1)[OFFSET(0)] AS device_category,
    MIN(event_timestamp) AS view_ts
  FROM events
  WHERE event_name = 'view_item'
    AND ga_session_id IS NOT NULL
  GROUP BY user_pseudo_id, ga_session_id
),

cart_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS cart_ts
  FROM events e
  JOIN view_stage v
    ON e.user_pseudo_id = v.user_pseudo_id
   AND e.ga_session_id = v.ga_session_id
  WHERE e.event_name = 'add_to_cart'
    AND e.event_timestamp >= v.view_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

checkout_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS checkout_ts
  FROM events e
  JOIN cart_stage c
    ON e.user_pseudo_id = c.user_pseudo_id
   AND e.ga_session_id = c.ga_session_id
  WHERE e.event_name = 'begin_checkout'
    AND e.event_timestamp >= c.cart_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

shipping_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS shipping_ts
  FROM events e
  JOIN checkout_stage c
    ON e.user_pseudo_id = c.user_pseudo_id
   AND e.ga_session_id = c.ga_session_id
  WHERE e.event_name = 'add_shipping_info'
    AND e.event_timestamp >= c.checkout_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

payment_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS payment_ts
  FROM events e
  JOIN shipping_stage s
    ON e.user_pseudo_id = s.user_pseudo_id
   AND e.ga_session_id = s.ga_session_id
  WHERE e.event_name = 'add_payment_info'
    AND e.event_timestamp >= s.shipping_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

purchase_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS purchase_ts
  FROM events e
  JOIN payment_stage p
    ON e.user_pseudo_id = p.user_pseudo_id
   AND e.ga_session_id = p.ga_session_id
  WHERE e.event_name = 'purchase'
    AND e.event_timestamp >= p.payment_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
)

SELECT
  v.device_category,
  COUNT(*) AS viewed_sessions,
  COUNT(c.ga_session_id) AS cart_sessions,
  COUNT(ch.ga_session_id) AS checkout_sessions,
  COUNT(s.ga_session_id) AS shipping_sessions,
  COUNT(p.ga_session_id) AS payment_sessions,
  COUNT(pu.ga_session_id) AS purchase_sessions,

  ROUND(
    100 * SAFE_DIVIDE(COUNT(c.ga_session_id), COUNT(*)),
    2
  ) AS view_to_cart_rate,

  ROUND(
    100 * SAFE_DIVIDE(COUNT(ch.ga_session_id), COUNT(c.ga_session_id)),
    2
  ) AS cart_to_checkout_rate,

  ROUND(
    100 * SAFE_DIVIDE(COUNT(pu.ga_session_id), COUNT(*)),
    2
  ) AS view_to_purchase_rate

FROM view_stage v

LEFT JOIN cart_stage c
  USING (user_pseudo_id, ga_session_id)

LEFT JOIN checkout_stage ch
  USING (user_pseudo_id, ga_session_id)

LEFT JOIN shipping_stage s
  USING (user_pseudo_id, ga_session_id)

LEFT JOIN payment_stage p
  USING (user_pseudo_id, ga_session_id)

LEFT JOIN purchase_stage pu
  USING (user_pseudo_id, ga_session_id)

GROUP BY v.device_category
ORDER BY viewed_sessions DESC;

-- ============================================================
-- FILE: 08_strict_vs_unordered_funnel.sql
-- ============================================================

-- 08_strict_vs_unordered_funnel.sql
-- Purpose: Compare unordered session-stage counts with the strict timestamp-gated funnel.
-- This identifies sessions that contain a funnel event but do not follow the full expected sequence,
-- helping quantify tracking gaps, skipped stages, or non-standard user paths.
-- Verified examples:
-- begin_checkout: 11,106 unordered vs 5,416 strict
-- purchase: 4,848 unordered vs 1,792 strict

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE event_name IN (
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'add_shipping_info',
    'add_payment_info',
    'purchase'
  )
),

unordered_sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(IF(event_name = 'view_item', 1, 0)) AS viewed,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS carted,
    MAX(IF(event_name = 'begin_checkout', 1, 0)) AS checkout,
    MAX(IF(event_name = 'add_shipping_info', 1, 0)) AS shipping,
    MAX(IF(event_name = 'add_payment_info', 1, 0)) AS payment,
    MAX(IF(event_name = 'purchase', 1, 0)) AS purchased
  FROM events
  WHERE ga_session_id IS NOT NULL
  GROUP BY user_pseudo_id, ga_session_id
),

view_stage AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MIN(event_timestamp) AS view_ts
  FROM events
  WHERE event_name = 'view_item'
    AND ga_session_id IS NOT NULL
  GROUP BY user_pseudo_id, ga_session_id
),

cart_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS cart_ts
  FROM events e
  JOIN view_stage v
    USING (user_pseudo_id, ga_session_id)
  WHERE e.event_name = 'add_to_cart'
    AND e.event_timestamp >= v.view_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

checkout_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS checkout_ts
  FROM events e
  JOIN cart_stage c
    USING (user_pseudo_id, ga_session_id)
  WHERE e.event_name = 'begin_checkout'
    AND e.event_timestamp >= c.cart_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

shipping_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS shipping_ts
  FROM events e
  JOIN checkout_stage c
    USING (user_pseudo_id, ga_session_id)
  WHERE e.event_name = 'add_shipping_info'
    AND e.event_timestamp >= c.checkout_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

payment_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS payment_ts
  FROM events e
  JOIN shipping_stage s
    USING (user_pseudo_id, ga_session_id)
  WHERE e.event_name = 'add_payment_info'
    AND e.event_timestamp >= s.shipping_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
),

purchase_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS purchase_ts
  FROM events e
  JOIN payment_stage p
    USING (user_pseudo_id, ga_session_id)
  WHERE e.event_name = 'purchase'
    AND e.event_timestamp >= p.payment_ts
  GROUP BY e.user_pseudo_id, e.ga_session_id
)

SELECT
  'view_item' AS stage,
  SUM(viewed) AS unordered_sessions,
  (SELECT COUNT(*) FROM view_stage) AS strict_sessions
FROM unordered_sessions

UNION ALL

SELECT
  'add_to_cart',
  SUM(carted),
  (SELECT COUNT(*) FROM cart_stage)
FROM unordered_sessions

UNION ALL

SELECT
  'begin_checkout',
  SUM(checkout),
  (SELECT COUNT(*) FROM checkout_stage)
FROM unordered_sessions

UNION ALL

SELECT
  'add_shipping_info',
  SUM(shipping),
  (SELECT COUNT(*) FROM shipping_stage)
FROM unordered_sessions

UNION ALL

SELECT
  'add_payment_info',
  SUM(payment),
  (SELECT COUNT(*) FROM payment_stage)
FROM unordered_sessions

UNION ALL

SELECT
  'purchase',
  SUM(purchased),
  (SELECT COUNT(*) FROM purchase_stage)
FROM unordered_sessions;

-- ============================================================
-- FILE: 09_primary_session_funnel.sql
-- ============================================================

-- 09_primary_session_funnel.sql
-- Purpose: Build the primary business funnel using sessions that contain a product view,
-- then measure whether each later funnel event occurs in the same session after that view.
-- Unlike the strict funnel, intermediate stages are not required, so legitimate sessions
-- are not discarded simply because a GA4 event is missing or a user skips a tracked step.
-- Verified result:
-- 77,020 viewed | 15,167 cart | 10,807 checkout | 10,806 shipping
-- 6,592 payment | 4,688 purchase
-- View-to-purchase = 6.09%

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE event_name IN (
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'add_shipping_info',
    'add_payment_info',
    'purchase'
  )
),

view_stage AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MIN(event_timestamp) AS view_ts
  FROM events
  WHERE event_name = 'view_item'
    AND ga_session_id IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
),

session_funnel AS (
  SELECT
    v.user_pseudo_id,
    v.ga_session_id,

    MAX(
      IF(
        e.event_name = 'add_to_cart'
        AND e.event_timestamp >= v.view_ts,
        1,
        0
      )
    ) AS added_to_cart,

    MAX(
      IF(
        e.event_name = 'begin_checkout'
        AND e.event_timestamp >= v.view_ts,
        1,
        0
      )
    ) AS began_checkout,

    MAX(
      IF(
        e.event_name = 'add_shipping_info'
        AND e.event_timestamp >= v.view_ts,
        1,
        0
      )
    ) AS added_shipping,

    MAX(
      IF(
        e.event_name = 'add_payment_info'
        AND e.event_timestamp >= v.view_ts,
        1,
        0
      )
    ) AS added_payment,

    MAX(
      IF(
        e.event_name = 'purchase'
        AND e.event_timestamp >= v.view_ts,
        1,
        0
      )
    ) AS purchased

  FROM view_stage v

  LEFT JOIN events e
    ON v.user_pseudo_id = e.user_pseudo_id
   AND v.ga_session_id = e.ga_session_id

  GROUP BY
    v.user_pseudo_id,
    v.ga_session_id
)

SELECT
  COUNT(*) AS viewed_product_sessions,

  SUM(added_to_cart) AS add_to_cart_sessions,

  SUM(began_checkout) AS checkout_sessions,

  SUM(added_shipping) AS shipping_sessions,

  SUM(added_payment) AS payment_sessions,

  SUM(purchased) AS purchase_sessions,

  ROUND(
    100 * SAFE_DIVIDE(SUM(added_to_cart), COUNT(*)),
    2
  ) AS view_to_cart_rate,

  ROUND(
    100 * SAFE_DIVIDE(SUM(began_checkout), COUNT(*)),
    2
  ) AS view_to_checkout_rate,

  ROUND(
    100 * SAFE_DIVIDE(SUM(added_shipping), COUNT(*)),
    2
  ) AS view_to_shipping_rate,

  ROUND(
    100 * SAFE_DIVIDE(SUM(added_payment), COUNT(*)),
    2
  ) AS view_to_payment_rate,

  ROUND(
    100 * SAFE_DIVIDE(SUM(purchased), COUNT(*)),
    2
  ) AS view_to_purchase_rate

FROM session_funnel;

-- ============================================================
-- FILE: 10_funnel_path_overlap.sql
-- ============================================================

-- 10_funnel_path_overlap.sql
-- Purpose: Measure overlap between funnel stages within product-view sessions.
-- This identifies skipped or missing intermediate events and determines how
-- closely observed GA4 user paths follow the expected ecommerce funnel.
-- Verified key finding:
-- 4,855 of 10,807 checkout sessions had no recorded add_to_cart event,
-- while downstream checkout -> shipping -> payment -> purchase links were nearly complete.

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE event_name IN (
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'add_shipping_info',
    'add_payment_info',
    'purchase'
  )
),

view_stage AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MIN(event_timestamp) AS view_ts
  FROM events
  WHERE event_name = 'view_item'
    AND ga_session_id IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
),

session_flags AS (
  SELECT
    v.user_pseudo_id,
    v.ga_session_id,

    MAX(IF(
      e.event_name = 'add_to_cart'
      AND e.event_timestamp >= v.view_ts, 1, 0
    )) AS cart,

    MAX(IF(
      e.event_name = 'begin_checkout'
      AND e.event_timestamp >= v.view_ts, 1, 0
    )) AS checkout,

    MAX(IF(
      e.event_name = 'add_shipping_info'
      AND e.event_timestamp >= v.view_ts, 1, 0
    )) AS shipping,

    MAX(IF(
      e.event_name = 'add_payment_info'
      AND e.event_timestamp >= v.view_ts, 1, 0
    )) AS payment,

    MAX(IF(
      e.event_name = 'purchase'
      AND e.event_timestamp >= v.view_ts, 1, 0
    )) AS purchase

  FROM view_stage v

  LEFT JOIN events e
    ON v.user_pseudo_id = e.user_pseudo_id
   AND v.ga_session_id = e.ga_session_id

  GROUP BY
    v.user_pseudo_id,
    v.ga_session_id
)

SELECT
  COUNTIF(checkout = 1) AS checkout_sessions,
  COUNTIF(checkout = 1 AND cart = 1) AS checkout_with_cart,
  COUNTIF(checkout = 1 AND cart = 0) AS checkout_without_cart,

  COUNTIF(shipping = 1) AS shipping_sessions,
  COUNTIF(shipping = 1 AND checkout = 1) AS shipping_with_checkout,
  COUNTIF(shipping = 1 AND checkout = 0) AS shipping_without_checkout,

  COUNTIF(payment = 1) AS payment_sessions,
  COUNTIF(payment = 1 AND shipping = 1) AS payment_with_shipping,
  COUNTIF(payment = 1 AND shipping = 0) AS payment_without_shipping,

  COUNTIF(purchase = 1) AS purchase_sessions,
  COUNTIF(purchase = 1 AND payment = 1) AS purchase_with_payment,
  COUNTIF(purchase = 1 AND payment = 0) AS purchase_without_payment

FROM session_flags;

-- ============================================================
-- FILE: 11_traffic_source_segmentation.sql
-- ============================================================

-- 11_traffic_source_segmentation.sql
-- Purpose: Compare product-view, checkout, payment, and purchase behavior
-- across acquisition source/medium segments.
-- Traffic source is taken deterministically from the first view_item event
-- in each product-view session.
-- Note: GA4 traffic_source fields describe user acquisition source/medium,
-- not necessarily session-level attribution.
-- This query is retained as supporting diagnostic work, not as the project's main objective.

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,

    traffic_source.source AS traffic_source,
    traffic_source.medium AS traffic_medium,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id

  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'add_shipping_info',
    'add_payment_info',
    'purchase'
  )
),

view_stage AS (
  SELECT
    user_pseudo_id,
    ga_session_id,

    ARRAY_AGG(
      COALESCE(traffic_source, '(unknown)')
      ORDER BY event_timestamp
      LIMIT 1
    )[OFFSET(0)] AS traffic_source,

    ARRAY_AGG(
      COALESCE(traffic_medium, '(unknown)')
      ORDER BY event_timestamp
      LIMIT 1
    )[OFFSET(0)] AS traffic_medium,

    MIN(event_timestamp) AS view_ts

  FROM events

  WHERE event_name = 'view_item'
    AND ga_session_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    ga_session_id
),

session_funnel AS (
  SELECT
    v.user_pseudo_id,
    v.ga_session_id,
    v.traffic_source,
    v.traffic_medium,

    MAX(
      IF(
        e.event_name = 'add_to_cart'
        AND e.event_timestamp >= v.view_ts,
        1,
        0
      )
    ) AS cart,

    MAX(
      IF(
        e.event_name = 'begin_checkout'
        AND e.event_timestamp >= v.view_ts,
        1,
        0
      )
    ) AS checkout,

    MAX(
      IF(
        e.event_name = 'add_payment_info'
        AND e.event_timestamp >= v.view_ts,
        1,
        0
      )
    ) AS payment,

    MAX(
      IF(
        e.event_name = 'purchase'
        AND e.event_timestamp >= v.view_ts,
        1,
        0
      )
    ) AS purchase

  FROM view_stage v

  LEFT JOIN events e
    ON v.user_pseudo_id = e.user_pseudo_id
   AND v.ga_session_id = e.ga_session_id

  GROUP BY
    v.user_pseudo_id,
    v.ga_session_id,
    v.traffic_source,
    v.traffic_medium
)

SELECT
  traffic_source,
  traffic_medium,

  COUNT(*) AS viewed_sessions,

  SUM(cart) AS cart_sessions,

  SUM(checkout) AS checkout_sessions,

  SUM(payment) AS payment_sessions,

  SUM(purchase) AS purchase_sessions,

  ROUND(
    100 * SAFE_DIVIDE(SUM(cart), COUNT(*)),
    2
  ) AS view_to_cart_rate,

  ROUND(
    100 * SAFE_DIVIDE(SUM(checkout), COUNT(*)),
    2
  ) AS view_to_checkout_rate,

  ROUND(
    100 * SAFE_DIVIDE(SUM(payment), COUNT(*)),
    2
  ) AS view_to_payment_rate,

  ROUND(
    100 * SAFE_DIVIDE(SUM(purchase), COUNT(*)),
    2
  ) AS view_to_purchase_rate

FROM session_funnel

GROUP BY
  traffic_source,
  traffic_medium

ORDER BY
  viewed_sessions DESC;

-- ============================================================
-- FILE: 12_bottleneck_by_device.sql
-- ============================================================

-- 12_bottleneck_by_device.sql
-- Purpose: Test whether the identified shipping-to-payment bottleneck
-- differs by device category.
-- Device is taken from the first product-view event in each session.
-- Only sessions that reach shipping after a product view are included,
-- and payment must occur after shipping to count as progression.
-- Verified key results:
-- Desktop: 6,226 shipping -> 3,769 payment -> 2,665 purchase
--          shipping->payment 60.54% | drop-off 39.46% | payment->purchase 70.71%
-- Mobile:  4,345 shipping -> 2,674 payment -> 1,922 purchase
--          shipping->payment 61.54% | drop-off 38.46% | payment->purchase 71.88%
-- Interpretation: the bottleneck is broad, not clearly device-specific.

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    device.category AS device_category,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id

  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'view_item',
    'add_shipping_info',
    'add_payment_info',
    'purchase'
  )
),

view_stage AS (
  SELECT
    user_pseudo_id,
    ga_session_id,

    ARRAY_AGG(
      device_category
      ORDER BY event_timestamp
      LIMIT 1
    )[OFFSET(0)] AS device_category,

    MIN(event_timestamp) AS view_ts

  FROM events

  WHERE event_name = 'view_item'
    AND ga_session_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    ga_session_id
),

shipping_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    v.device_category,
    MIN(e.event_timestamp) AS shipping_ts

  FROM events e

  JOIN view_stage v
    ON e.user_pseudo_id = v.user_pseudo_id
   AND e.ga_session_id = v.ga_session_id

  WHERE e.event_name = 'add_shipping_info'
    AND e.event_timestamp >= v.view_ts

  GROUP BY
    e.user_pseudo_id,
    e.ga_session_id,
    v.device_category
),

payment_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS payment_ts

  FROM events e

  JOIN shipping_stage s
    ON e.user_pseudo_id = s.user_pseudo_id
   AND e.ga_session_id = s.ga_session_id

  WHERE e.event_name = 'add_payment_info'
    AND e.event_timestamp >= s.shipping_ts

  GROUP BY
    e.user_pseudo_id,
    e.ga_session_id
),

purchase_stage AS (
  SELECT
    e.user_pseudo_id,
    e.ga_session_id,
    MIN(e.event_timestamp) AS purchase_ts

  FROM events e

  JOIN payment_stage p
    ON e.user_pseudo_id = p.user_pseudo_id
   AND e.ga_session_id = p.ga_session_id

  WHERE e.event_name = 'purchase'
    AND e.event_timestamp >= p.payment_ts

  GROUP BY
    e.user_pseudo_id,
    e.ga_session_id
)

SELECT
  s.device_category,

  COUNT(*) AS shipping_sessions,

  COUNT(p.ga_session_id) AS payment_sessions,

  COUNT(pu.ga_session_id) AS purchase_sessions,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNT(p.ga_session_id),
      COUNT(*)
    ),
    2
  ) AS shipping_to_payment_rate,

  ROUND(
    100 * (
      1 - SAFE_DIVIDE(
        COUNT(p.ga_session_id),
        COUNT(*)
      )
    ),
    2
  ) AS shipping_to_payment_dropoff_rate,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNT(pu.ga_session_id),
      COUNT(p.ga_session_id)
    ),
    2
  ) AS payment_to_purchase_rate

FROM shipping_stage s

LEFT JOIN payment_stage p
  USING (user_pseudo_id, ga_session_id)

LEFT JOIN purchase_stage pu
  USING (user_pseudo_id, ga_session_id)

GROUP BY
  s.device_category

ORDER BY
  shipping_sessions DESC;

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
