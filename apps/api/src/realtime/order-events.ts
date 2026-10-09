/** Socket event names for orders (user room: customer, staff room: dashboards). */
export const ORDER_EVENTS = {
  /** server -> user:<id> and staff: an order changed status */
  UPDATED: 'order:updated',
  /** server -> staff: a new order was placed */
  NEW: 'order:new',
} as const;
