import Anthropic from '@anthropic-ai/sdk';
import multipart from '@fastify/multipart';
import websocket from '@fastify/websocket';
import Fastify, { type FastifyError, type FastifyInstance } from 'fastify';
import { type Config, loadConfig } from './config.js';
import { MAX_FRAME_BYTES, MAX_FRAMES, clipsRoutes } from './routes/clips.js';
import { streamRoutes } from './routes/stream.js';
import { JobStore } from './services/jobs.js';
import { type VisionService, createClaudeVision } from './services/vision.js';

const redactToken = (url: string) => url.replace(/([?&]token=)[^&]*/, '$1[redacted]');

export function buildServer(config: Config, deps: { vision?: VisionService } = {}): FastifyInstance {
  const app = Fastify({
    logger: process.env.NODE_ENV !== 'test' && {
      // WebSocket clients may authenticate with ?token=; keep it out of the logs.
      serializers: { req: (req: { method: string; url: string }) => ({ method: req.method, url: redactToken(req.url) }) },
    },
  });
  app.decorate('config', config);

  const vision =
    deps.vision ??
    createClaudeVision(new Anthropic({ apiKey: config.ANTHROPIC_API_KEY, timeout: 60_000, maxRetries: 2 }), app.log);
  const jobs = new JobStore(vision, app.log);
  app.addHook('onClose', async () => jobs.close());

  app.register(multipart, {
    limits: { files: MAX_FRAMES, fileSize: MAX_FRAME_BYTES, fields: 10, fieldSize: 1024, parts: MAX_FRAMES + 10 },
  });
  app.register(websocket);

  app.setErrorHandler((err: FastifyError, req, reply) => {
    const status = err.statusCode ?? 500;
    if (status >= 500) {
      req.log.error({ err }, 'request failed');
      return reply.code(500).send({ error: 'internal', message: 'Internal error.' });
    }
    // Multipart limit errors are 413; everything else client-side maps to 400 per WS_PROTOCOL.md.
    return reply.code(status === 413 ? 413 : 400).send({ error: 'bad_input', message: err.message });
  });

  app.get('/health', async () => ({ status: 'ok' }));
  app.register(async (scoped) => {
    clipsRoutes(scoped, jobs);
    streamRoutes(scoped, jobs);
  });

  return app;
}

declare module 'fastify' {
  interface FastifyInstance {
    config: Config;
  }
}

if (import.meta.main) {
  const config = loadConfig();
  const app = buildServer(config);
  await app.listen({ port: config.PORT, host: '0.0.0.0' });
}
