import cookieParser from 'cookie-parser';
import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import { ZodError } from 'zod';
import { env } from './config/env';
import { AppError } from './lib/errors';
import { adminRouter } from './routes/admin';
import { authRouter } from './routes/auth';
import { categoriesRouter } from './routes/categories';
import { healthRouter } from './routes/health';
import { manageRouter } from './routes/manage';
import { productsRouter } from './routes/products';
import { addressesRouter } from './routes/addresses';
import { cartRouter } from './routes/cart';
import { checkoutRouter, ordersRouter } from './routes/orders';
import { staffOrdersRouter } from './routes/staff-orders';
import { analyticsRouter, trackRouter } from './routes/track';
import { startAnalyticsRollup } from './services/analytics.service';

export function createApp() {
  const app = express();

  // Behind Cloud Run / a load balancer, req.ip must come from X-Forwarded-For (rate limiting).
  if (env.NODE_ENV === 'production') app.set('trust proxy', 1);

  app.use(helmet());
  app.use(cors({ origin: env.corsOrigins, credentials: true }));
  app.use(express.json({ limit: '1mb' }));
  app.use(cookieParser());

  app.use('/api/health', healthRouter);
  app.use('/api/auth', authRouter);
  app.use('/api/admin', adminRouter);
  app.use('/api/categories', categoriesRouter); // public
  app.use('/api/products', productsRouter); // public
  app.use('/api/manage', manageRouter); // SHOPKEEPER + ADMIN
  app.use('/api/manage/orders', staffOrdersRouter); // SHOPKEEPER + ADMIN
  app.use('/api/cart', cartRouter);
  app.use('/api/addresses', addressesRouter);
  app.use('/api/checkout', checkoutRouter);
  app.use('/api/orders', ordersRouter);
  app.use('/api/track', trackRouter);
  app.use('/api/manage/analytics', analyticsRouter); // SHOPKEEPER + ADMIN
  startAnalyticsRollup();

  app.use((_req, res) =>
    res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Route not found' } }),
  );

  app.use(
    (err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
      if (err instanceof ZodError) {
        res.status(400).json({
          error: {
            code: 'VALIDATION_ERROR',
            message: 'Invalid input',
            details: err.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
          },
        });
        return;
      }
      if (err instanceof AppError) {
        res.status(err.status).json({
          error: { code: err.code, message: err.message, details: err.details },
        });
        return;
      }
      if ((err as { type?: string })?.type === 'entity.parse.failed') {
        res.status(400).json({ error: { code: 'BAD_JSON', message: 'Malformed JSON body' } });
        return;
      }
      console.error(err);
      res.status(500).json({ error: { code: 'INTERNAL', message: 'Internal server error' } });
    },
  );

  return app;
}
