import { afterEach, describe, expect, it } from 'vitest';
import { ServerMessage } from '../src/schemas.js';
import { AUTH, TOKEN, collect, jpeg, listen, makeApp, mockVision, multipart, sampleInsight } from './helpers.js';

let app: ReturnType<typeof makeApp> | undefined;
afterEach(async () => {
  await app?.close();
  app = undefined;
});

async function setup(vision = mockVision()) {
  app = makeApp(vision);
  const body = await multipart({ clipId: crypto.randomUUID(), petType: 'cat' }, [{ data: jpeg() }]);
  const res = await app.inject({ method: 'POST', url: '/v1/clips', payload: body.payload, headers: { ...body.headers, ...AUTH } });
  const base = await listen(app);
  return { base, streamUrl: res.json().streamUrl as string, jobId: res.json().jobId as string, vision };
}

describe('GET /v1/stream', () => {
  it('streams status -> delta* -> insight -> done, then closes with 1000', async () => {
    const { base, streamUrl, jobId } = await setup();
    const { messages, code } = await collect(base + streamUrl, AUTH);
    expect(messages.map((m) => m.type)).toEqual(['status', 'delta', 'delta', 'insight', 'done']);
    expect(messages[0]).toEqual({ type: 'status', jobId, status: 'analyzing' });
    expect(messages[3]).toEqual({ type: 'insight', jobId, insight: sampleInsight });
    for (const m of messages) expect(ServerMessage.safeParse(m).success).toBe(true);
    expect(code).toBe(1000);
  });

  it('forwards vision errors (e.g. refused) then done', async () => {
    const { base, streamUrl } = await setup(mockVision([{ type: 'error', code: 'refused', message: 'declined' }]));
    const { messages } = await collect(base + streamUrl, AUTH);
    expect(messages.map((m) => [m.type, m.code])).toEqual([
      ['status', undefined],
      ['error', 'refused'],
      ['done', undefined],
    ]);
  });

  it('replays the final result after the job finished, without calling the model again', async () => {
    const { base, streamUrl, vision } = await setup();
    await collect(base + streamUrl, AUTH);
    const { messages } = await collect(base + streamUrl, AUTH);
    expect(messages.map((m) => m.type)).toEqual(['insight', 'done']);
    expect(vision.calls).toBe(1);
  });

  it('accepts ?token= and rejects bad tokens; the header wins over the query', async () => {
    const { base, streamUrl } = await setup();
    await expect(collect(base + streamUrl)).rejects.toThrow('HTTP 401');
    await expect(collect(`${base}${streamUrl}&token=wrong`)).rejects.toThrow('HTTP 401');
    await expect(collect(`${base}${streamUrl}&token=${TOKEN}`, { authorization: 'Bearer wrong' })).rejects.toThrow(
      'HTTP 401',
    );
    const { messages } = await collect(`${base}${streamUrl}&token=${TOKEN}`);
    expect(messages.at(-1)?.type).toBe('done');
  });

  it('sends bad_input + done for an unknown jobId', async () => {
    const { base } = await setup();
    const { messages } = await collect(`${base}/v1/stream?jobId=nope`, AUTH);
    expect(messages).toEqual([
      { type: 'error', jobId: 'nope', code: 'bad_input', message: expect.any(String) },
      { type: 'done', jobId: 'nope' },
    ]);
  });
});
