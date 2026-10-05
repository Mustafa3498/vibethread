import { io } from './socket';

/** Safe to call from anywhere (jobs, scripts, tests): no-ops if Socket.io isn't running. */
export function emitToRoom(room: string, event: string, payload: unknown) {
  try {
    io?.to(room).emit(event, payload);
  } catch (err) {
    console.error('[emit] failed', event, err);
  }
}
