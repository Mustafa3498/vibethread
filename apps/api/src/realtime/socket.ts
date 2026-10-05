import { randomUUID } from 'node:crypto';
import type { Server as HttpServer } from 'node:http';
import { Role } from '@vibethread/database';
import { SOCKET_EVENTS, SOCKET_ROOMS } from '@vibethread/shared';
import { createAdapter } from '@socket.io/redis-adapter';
import { Server, type Socket } from 'socket.io';
import { env } from '../config/env';
import { AppError } from '../lib/errors';
import { redisPub, redisSub } from '../lib/redis';
import { type AuthContext, verifyAccessToken } from '../lib/tokens';

export let io: Server;

interface SocketData {
  auth?: AuthContext;
  anonymousId?: string;
  expiryTimer?: NodeJS.Timeout;
}
type VtSocket = Socket<any, any, any, SocketData>;

/** Handshake errors reach the client as `connect_error` with err.message + err.data.code. */
function handshakeError(err: unknown) {
  const code = err instanceof AppError ? err.code : 'UNAUTHORIZED';
  const e = new Error(code) as Error & { data?: unknown };
  e.data = { code };
  return e;
}

function roomsFor(data: SocketData): string[] {
  if (data.auth) {
    const rooms = [SOCKET_ROOMS.user(data.auth.userId)];
    if (data.auth.role === Role.SHOPKEEPER || data.auth.role === Role.ADMIN) {
      rooms.push(SOCKET_ROOMS.STAFF);
    }
    if (data.auth.role === Role.ADMIN) rooms.push(SOCKET_ROOMS.ADMIN);
    return rooms;
  }
  return data.anonymousId ? [SOCKET_ROOMS.guest(data.anonymousId)] : [];
}

function leaveManagedRooms(socket: VtSocket) {
  for (const room of socket.rooms) {
    if (room === socket.id) continue; // Socket.io's private room
    if (room.startsWith('user:') || room.startsWith('guest:') || room === 'staff' || room === 'admin') {
      socket.leave(room);
    }
  }
}

function applyIdentity(socket: VtSocket) {
  leaveManagedRooms(socket);
  roomsFor(socket.data).forEach((r) => socket.join(r));
  scheduleExpiry(socket);
}

// A socket outlives its 15-min access token, so we strip privileges when it expires.
// The client reacts to `auth:expired` by calling /api/auth/refresh and emitting `auth:renew`.
function scheduleExpiry(socket: VtSocket) {
  if (socket.data.expiryTimer) clearTimeout(socket.data.expiryTimer);
  if (!socket.data.auth) return;

  const ms = Math.min(socket.data.auth.exp * 1000 - Date.now(), 2 ** 31 - 1);
  socket.data.expiryTimer = setTimeout(() => {
    socket.data.auth = undefined;
    socket.data.anonymousId ??= randomUUID();
    leaveManagedRooms(socket);
    roomsFor(socket.data).forEach((r) => socket.join(r));
    socket.emit(SOCKET_EVENTS.AUTH_EXPIRED);
  }, Math.max(ms, 0));
}

export function initSocket(httpServer: HttpServer) {
  io = new Server(httpServer, {
    cors: { origin: env.corsOrigins, credentials: true },
  });

  // Redis adapter → events reach clients on ANY API instance.
  io.adapter(createAdapter(redisPub, redisSub));

  // ── Handshake: client connects with { auth: { token?, anonymousId? } } ──
  //   token present  → must be a valid access token, else connect_error (TOKEN_EXPIRED / INVALID_TOKEN)
  //   token absent   → guest (storefront visitors: cart sync + behavioral tracking)
  io.use((socket, next) => {
    const { token, anonymousId } = (socket.handshake.auth ?? {}) as {
      token?: unknown;
      anonymousId?: unknown;
    };
    const data = socket.data as SocketData;

    if (typeof token === 'string' && token) {
      try {
        data.auth = verifyAccessToken(token);
      } catch (err) {
        return next(handshakeError(err));
      }
    } else {
      data.anonymousId =
        typeof anonymousId === 'string' && /^[\w-]{8,64}$/.test(anonymousId)
          ? anonymousId
          : randomUUID();
    }
    next();
  });

  io.on('connection', (socket: VtSocket) => {
    applyIdentity(socket);
    console.log(
      `[socket] ${socket.id} connected as ${
        socket.data.auth ? `${socket.data.auth.role}:${socket.data.auth.userId}` : 'guest'
      }`,
    );

    // Client got a fresh access token (after refresh or after login) → upgrade this socket.
    socket.on(SOCKET_EVENTS.AUTH_RENEW, (token: unknown, ack?: (res: unknown) => void) => {
      try {
        if (typeof token !== 'string') throw new AppError(401, 'INVALID_TOKEN', 'Missing token');
        const next = verifyAccessToken(token);
        const current = socket.data.auth;
        if (current && current.userId !== next.userId) {
          throw new AppError(403, 'FORBIDDEN', 'Token belongs to a different user');
        }
        socket.data.auth = next;
        socket.data.anonymousId = undefined;
        applyIdentity(socket);
        ack?.({ ok: true, role: next.role });
      } catch (err) {
        const code = err instanceof AppError ? err.code : 'UNAUTHORIZED';
        ack?.({ ok: false, code });
      }
    });

    // Storefront: product page opened → receive live stock / price updates for that product.
    socket.on(SOCKET_EVENTS.PRODUCT_WATCH, (productId: unknown, ack?: (res: unknown) => void) => {
      if (typeof productId !== 'string' || !/^[\w-]{8,64}$/.test(productId)) return ack?.({ ok: false, code: 'BAD_ID' });
      const watching = [...socket.rooms].filter((r) => r.startsWith('product:')).length;
      if (watching >= 20) return ack?.({ ok: false, code: 'TOO_MANY' });
      socket.join(SOCKET_ROOMS.product(productId));
      ack?.({ ok: true });
    });
    socket.on(SOCKET_EVENTS.PRODUCT_UNWATCH, (productId: unknown) => {
      if (typeof productId === 'string') socket.leave(SOCKET_ROOMS.product(productId));
    });

    // Handy for debugging + the smoke test.
    socket.on(SOCKET_EVENTS.WHOAMI, (ack?: (res: unknown) => void) => {
      ack?.({
        kind: socket.data.auth ? 'user' : 'guest',
        userId: socket.data.auth?.userId ?? null,
        role: socket.data.auth?.role ?? null,
        rooms: [...socket.rooms].filter((r) => r !== socket.id).sort(),
      });
    });

    socket.on('disconnect', () => {
      if (socket.data.expiryTimer) clearTimeout(socket.data.expiryTimer);
      console.log(`[socket] ${socket.id} disconnected`);
    });
  });

  // Cart rooms, stock broadcasts and tracking handlers arrive in Steps 6–8.
  return io;
}
