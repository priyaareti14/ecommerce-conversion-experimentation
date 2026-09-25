# Executive Summary

**Business question:** Where is the most reliable conversion bottleneck, and what experiment should the product team run?

A strict funnel initially reported **2.33% view-to-purchase conversion**, but validation showed that strict event ordering excluded legitimate GA4 paths. After correcting the metric definition, validated conversion was **6.09%**: **77,020 product-view sessions → 10,807 checkout → 10,806 shipping → 6,592 payment → 4,688 purchase**.

The most reliable downstream loss was **shipping → payment (~39% drop-off)**. Desktop (**60.54%**) and mobile (**61.54%**) were similar, so the evidence did not support a device-specific solution.

For experimentation, users entered once at their first eligible shipping-stage session, producing a **57.15% user-level baseline**. A +3 pp MDE at 80% power and 5% significance required **4,229 users per arm**. A/A, SRM, and 10,000-run Monte Carlo checks validated the design.

A clearly labeled simulated treatment scenario produced **57.89% control vs 60.94% treatment**, a **+3.05 pp lift** (95% CI **0.96–5.14 pp**, **p=0.0043**) while passing the predefined downstream guardrail.

**Recommendation:** test a broad shipping-to-payment checkout intervention in a live experiment. The observational GA4 data identifies the bottleneck, but not its cause.
