import { createHash, timingSafeEqual } from 'node:crypto';
import type { FastifyReply, FastifyRequest } from 'fastify';

const digest = (s: string) => createHash('sha256').update(s).digest();

/**
 * preHandler/preValidation hook: `Authorization: Bearer <API_TOKEN>`.
 * With allowQuery (WebSocket upgrades), `?token=` is accepted when no header is sent; the header wins.
 */
export function requireToken(allowQuery: boolean) {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    const header = req.headers.authorization;
    let token: string | undefined;
    if (header !== undefined) {
      token = /^Bearer (.+)$/.exec(header)?.[1];
    } else if (allowQuery) {
      const q = (req.query as Record<string, unknown>).token;
      token = typeof q === 'string' ? q : undefined;
    }
    if (token === undefined || !timingSafeEqual(digest(token), digest(req.server.config.API_TOKEN))) {
      return reply.code(401).send({ error: 'unauthorized' });
    }
  };
}
