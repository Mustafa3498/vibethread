/** Socket event names for behavior analytics (staff room only). */
export const ANALYTICS_EVENTS = {
  /** server -> staff: a batch of customer events just arrived (compact summary) */
  EVENTS: 'analytics:events',
} as const;
