import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireToken } from '../auth.js';
import { ClipFields } from '../schemas.js';
import type { JobStore } from '../services/jobs.js';

export const MAX_FRAMES = 5;
export const MAX_FRAME_BYTES = 2 * 1024 * 1024;

const isJpeg = (b: Buffer) => b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;

export function clipsRoutes(app: FastifyInstance, jobs: JobStore): void {
  app.post('/v1/clips', { preHandler: requireToken(false) }, async (req, reply) => {
    if (!req.isMultipart()) {
      return reply.code(400).send({ error: 'bad_input', message: 'Expected multipart/form-data.' });
    }

    const fields: Record<string, string> = {};
    const frames: Buffer[] = [];
    // Size and count limits are enforced by @fastify/multipart (413 via the error handler).
    for await (const part of req.parts()) {
      if (part.type === 'field') {
        if (typeof part.value === 'string') fields[part.fieldname] = part.value;
        continue;
      }
      const buf = await part.toBuffer();
      if (part.fieldname !== 'frames[]' && part.fieldname !== 'frames') {
        return reply.code(400).send({ error: 'bad_input', message: `Unexpected file field "${part.fieldname}".` });
      }
      if (part.mimetype !== 'image/jpeg' || !isJpeg(buf)) {
        return reply.code(400).send({ error: 'bad_input', message: 'Frames must be JPEG images.' });
      }
      frames.push(buf);
    }

    const parsed = ClipFields.safeParse(fields);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'bad_input', message: z.prettifyError(parsed.error) });
    }
    if (frames.length === 0) {
      return reply.code(400).send({ error: 'bad_input', message: 'At least one frame is required.' });
    }

    const jobId = jobs.create(parsed.data, frames);
    return reply.code(202).send({ jobId, streamUrl: `/v1/stream?jobId=${encodeURIComponent(jobId)}` });
  });
}
