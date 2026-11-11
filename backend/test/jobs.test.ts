import { describe, expect, it } from 'vitest';
import type { ServerMessage } from '../src/schemas.js';
import { JobStore, RESULT_TTL_MS } from '../src/services/jobs.js';
import { mockVision } from './helpers.js';

const silent = { info() {}, warn() {}, error() {} } as never;

describe('JobStore', () => {
  it('drops finished results after 15 minutes and lets the clip be re-posted', async () => {
    let now = 0;
    const store = new JobStore(mockVision(), silent, () => now);
    const clip = { clipId: crypto.randomUUID(), petType: 'dog' as const };
    const jobId = store.create(clip, []);

    const seen: ServerMessage[] = [];
    await new Promise<void>((done) => store.attach(jobId, (m) => (seen.push(m), m.type === 'done' && done())));
    expect(seen.at(-2)?.type).toBe('insight');

    now += RESULT_TTL_MS - 1;
    expect(store.attach(jobId, () => {})).toBeDefined();
    now += 1;
    expect(store.attach(jobId, () => {})).toBeUndefined();
    expect(store.create(clip, [])).not.toBe(jobId);
    store.close();
  });

  it('starts a new job when a clip is re-posted after its job failed', async () => {
    const vision = mockVision([{ type: 'error', code: 'timeout', message: 'slow' }]);
    const store = new JobStore(vision, silent);
    const clip = { clipId: crypto.randomUUID(), petType: 'cat' as const };
    const run = (id: string) => {
      const seen: ServerMessage[] = [];
      return new Promise<ServerMessage[]>((done) =>
        store.attach(id, (m) => (seen.push(m), m.type === 'done' && done(seen))),
      );
    };

    const first = store.create(clip, []);
    expect(store.create(clip, [])).toBe(first); // pending: same job
    expect((await run(first)).at(-2)?.type).toBe('error');

    const retry = store.create(clip, []);
    expect(retry).not.toBe(first);
    expect(store.create(clip, [])).toBe(retry);
    await run(retry);
    expect(vision.calls).toBe(2);
    store.close();
  });
});
