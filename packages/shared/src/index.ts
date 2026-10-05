// Constants + types shared by the API, dashboards and storefront.

export const ROLES = ['CUSTOMER', 'SHOPKEEPER', 'ADMIN'] as const;
export type RoleName = (typeof ROLES)[number];

export const TRACKING_EVENT_TYPES = [
  'PAGE_VIEW',
  'PRODUCT_VIEW',
  'IMAGE_HOVER',
  'IMAGE_ZOOM',
  'COLOR_SELECT',
  'COLOR_HOVER',
  'SIZE_SELECT',
  'SIZE_CHART_OPEN',
  'SIZE_TOGGLE',
  'ADD_TO_CART_HOVER',
  'ADD_TO_CART',
  'REMOVE_FROM_CART',
  'CHECKOUT_START',
  'CHECKOUT_COMPLETE',
  'SEARCH',
  'FILTER_APPLY',
  'SESSION_END',
] as const;
export type TrackingEventTypeName = (typeof TRACKING_EVENT_TYPES)[number];

// Socket.io event names — one place so client & server never drift.
export const SOCKET_EVENTS = {
  STOCK_UPDATED: 'stock:updated',
  CART_SYNC: 'cart:sync',
  TRACK_BATCH: 'track:batch',
  ADMIN_PULSE: 'admin:pulse',
  // auth handshake
  AUTH_RENEW: 'auth:renew', // client → server: send a fresh access token
  AUTH_EXPIRED: 'auth:expired', // server → client: token expired, refresh + renew
  WHOAMI: 'whoami', // client → server (ack): who does the server think I am?
  // catalog / inventory
  PRODUCT_WATCH: 'product:watch', // client → server: start receiving live updates for a product
  PRODUCT_UNWATCH: 'product:unwatch',
  PRODUCT_UPDATED: 'product:updated', // server → product room: price/promo/status changed
  INVENTORY_ALERT: 'inventory:alert', // server → staff room: low stock / out of stock / fast moving
} as const;

// Socket.io rooms — one place so emitters and joiners agree.
export const SOCKET_ROOMS = {
  user: (userId: string) => `user:${userId}`,
  guest: (anonymousId: string) => `guest:${anonymousId}`,
  product: (productId: string) => `product:${productId}`,
  STAFF: 'staff', // SHOPKEEPER + ADMIN
  ADMIN: 'admin', // ADMIN only (live pulse, financials)
} as const;

// ── Realtime payloads ──
/** Sent to `product:<id>` rooms (public) — safe to show on the storefront. */
export interface StockUpdatePublic {
  productId: string;
  variantId: string;
  available: number;
  lowStock: boolean;
}
/** Sent to the `staff` room — adds the operational numbers. */
export interface StockUpdateStaff extends StockUpdatePublic {
  sku: string;
  color: string;
  size: string;
  quantity: number;
  reserved: number;
  lowStockThreshold: number;
}
export interface InventoryAlertPayload {
  id: string;
  type: 'LOW_STOCK' | 'OUT_OF_STOCK' | 'FAST_MOVING';
  variantId: string;
  productId: string;
  productName: string;
  sku: string;
  message: string;
  createdAt: string;
}
export interface ProductUpdatedPayload {
  productId: string;
  basePrice: number;
  salePrice: number | null;
  promoTag: string | null;
  status: 'DRAFT' | 'ACTIVE' | 'ARCHIVED';
}

// ── Auth DTOs ──
export interface AuthUser {
  id: string;
  email: string;
  fullName: string;
  phone: string | null;
  role: RoleName;
  isActive: boolean;
  createdAt: string;
}

export interface AuthResponse {
  user: AuthUser;
  accessToken: string;
}

export interface ApiErrorBody {
  error: { code: string; message: string; details?: unknown };
}

export interface ApiHealth {
  status: 'ok' | 'degraded';
  uptimeSec: number;
  checks: { database: boolean; redis: boolean };
  timestamp: string;
}
