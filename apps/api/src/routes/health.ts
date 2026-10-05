import { Router } from 'express';
import { prisma } from '@vibethread/database';
import type { ApiHealth } from '@vibethread/shared';
import { redis } from '../lib/redis';

export const healthRouter = Router();

healthRouter.get('/', async (_req, res) => {
  const [database, redisOk] = await Promise.all([
    prisma.$queryRaw`SELECT 1`.then(() => true).catch(() => false),
    redis.ping().then((r) => r === 'PONG').catch(() => false),
  ]);

  const body: ApiHealth = {
    status: database && redisOk ? 'ok' : 'degraded',
    uptimeSec: Math.round(process.uptime()),
    checks: { database, redis: redisOk },
    timestamp: new Date().toISOString(),
  };
  res.status(body.status === 'ok' ? 200 : 503).json(body);
});
