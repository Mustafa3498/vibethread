import type { NextFunction, Request, Response } from 'express';
import type { ZodTypeAny } from 'zod';

type Source = 'body' | 'query' | 'params';

/** Parses + replaces req[source] with the validated (and transformed) data. */
export const validate =
  (schema: ZodTypeAny, source: Source = 'body') =>
  (req: Request, _res: Response, next: NextFunction) => {
    const result = schema.safeParse(req[source]);
    if (!result.success) return next(result.error); // handled in the error middleware
    (req as unknown as Record<Source, unknown>)[source] = result.data;
    next();
  };
