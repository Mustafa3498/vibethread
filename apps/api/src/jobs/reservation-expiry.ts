import { redis } from '../lib/redis';
import { expireStaleReservations } from '../services/inventory.service';

const LOCK_KEY = 'lock:job:reservation-expiry';

/**
 * Releases stock held by abandoned checkouts. A Redis lock makes sure only one API
 * instance does the work per tick (the DB claim is atomic anyway — this just avoids wasted queries).
 */
export function startReservationExpiryJob(intervalMs = 60_000) {
  const tick = async () => {
    try {
      const got = await redis.set(LOCK_KEY, '1', 'EX', Math.max(Math.floor(intervalMs / 1000) - 5, 5), 'NX');
      if (!got) return;
      const released = await expireStaleReservations();
      if (released > 0) console.log(`[jobs] released ${released} expired stock hold(s)`);
    } catch (err) {
      console.error('[jobs] reservation expiry failed:', err);
    }
  };
  const timer = setInterval(tick, intervalMs);
  timer.unref();
  return () => clearInterval(timer);
}
