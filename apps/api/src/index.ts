import http from 'node:http';
import { prisma } from '@vibethread/database';
import { createApp } from './app';
import { env } from './config/env';
import { redis } from './lib/redis';
import { startReservationExpiryJob } from './jobs/reservation-expiry';
import { initSocket } from './realtime/socket';

const app = createApp();
const server = http.createServer(app);
initSocket(server);
const stopExpiryJob = startReservationExpiryJob();

server.listen(env.API_PORT, () => {
  console.log(`🚀 VibeThread API → http://localhost:${env.API_PORT}/api/health`);
});

async function shutdown(signal: string) {
  console.log(`\n${signal} received, shutting down...`);
  stopExpiryJob();
  server.close();
  await Promise.allSettled([prisma.$disconnect(), redis.quit()]);
  process.exit(0);
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
