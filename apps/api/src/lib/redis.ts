import Redis from 'ioredis';
import { env } from '../config/env';

// Main client for commands; Socket.io adapter needs its own pub/sub pair.
export const redis = new Redis(env.REDIS_URL, { maxRetriesPerRequest: 3 });
export const redisPub = redis.duplicate();
export const redisSub = redis.duplicate();

redis.on('error', (err) => console.error('[redis] error:', err.message));
