#!/usr/bin/env python3
"""Adds the Step B (tracking + analytics) routes to apps/api/src/app.ts (safe to run twice)."""
import sys

PATH = "apps/api/src/app.ts"
src = open(PATH, encoding="utf-8", newline="").read()
if "trackRouter" in src:
    print("app.ts already patched, nothing to do")
    sys.exit(0)

imp_anchor = "import { staffOrdersRouter } from './routes/staff-orders';"
mount_anchor = "  app.use('/api/orders', ordersRouter);"
for a in (imp_anchor, mount_anchor):
    if a not in src:
        print("Could not find this line in app.ts:\n  " + a)
        sys.exit(1)

src = src.replace(
    imp_anchor,
    imp_anchor
    + "\nimport { analyticsRouter, trackRouter } from './routes/track';"
    + "\nimport { startAnalyticsRollup } from './services/analytics.service';",
    1,
)
src = src.replace(
    mount_anchor,
    mount_anchor
    + "\n  app.use('/api/track', trackRouter);"
    + "\n  app.use('/api/manage/analytics', analyticsRouter); // SHOPKEEPER + ADMIN"
    + "\n  startAnalyticsRollup();",
    1,
)
open(PATH, "w", encoding="utf-8", newline="").write(src)
print("app.ts patched: /api/track, /api/manage/analytics + rollup job")
