import type { FastifyInstance } from 'fastify';
import type { WebSocket } from 'ws';
import { requireToken } from '../auth.js';
import { type ServerMessage, StreamQuery } from '../schemas.js';
import type { JobStore } from '../services/jobs.js';

export function streamRoutes(app: FastifyInstance, jobs: JobStore): void {
  // preValidation runs before the upgrade, so a 401 rejects the handshake.
  app.get('/v1/stream', { websocket: true, preValidation: requireToken(true) }, (socket: WebSocket, req) => {
    const send = (msg: ServerMessage) => {
      if (socket.readyState !== socket.OPEN) return;
      socket.send(JSON.stringify(msg));
      if (msg.type === 'done') socket.close(1000);
    };

    const query = StreamQuery.safeParse(req.query);
    const jobId = query.success ? query.data.jobId : '';
    const detach = query.success ? jobs.attach(jobId, send) : undefined;
    if (!detach) {
      send({ type: 'error', jobId, code: 'bad_input', message: 'Unknown or expired jobId. Re-post the clip.' });
      send({ type: 'done', jobId });
      return;
    }
    socket.on('close', detach);
  });
}
