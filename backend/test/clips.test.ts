import { afterEach, describe, expect, it } from 'vitest';
import { AUTH, jpeg, makeApp, multipart } from './helpers.js';

const fields = () => ({ clipId: crypto.randomUUID(), petType: 'dog' });
let app: ReturnType<typeof makeApp> | undefined;
afterEach(async () => {
  await app?.close();
  app = undefined;
});

async function post(body: Awaited<ReturnType<typeof multipart>>, headers: Record<string, string> = AUTH) {
  app ??= makeApp();
  return app.inject({ method: 'POST', url: '/v1/clips', payload: body.payload, headers: { ...body.headers, ...headers } });
}

describe('POST /v1/clips', () => {
  it('returns 202 with jobId and streamUrl', async () => {
    const res = await post(await multipart({ ...fields(), breedHint: 'beagle' }, [{ data: jpeg() }, { data: jpeg() }]));
    expect(res.statusCode).toBe(202);
    const { jobId, streamUrl } = res.json();
    expect(jobId).toEqual(expect.any(String));
    expect(streamUrl).toBe(`/v1/stream?jobId=${jobId}`);
  });

  it('rejects a missing or wrong token with 401', async () => {
    const body = await multipart(fields(), [{ data: jpeg() }]);
    expect((await post(body, {})).statusCode).toBe(401);
    const res = await post(body, { authorization: 'Bearer wrong' });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: 'unauthorized' });
  });

  it('is idempotent by clipId', async () => {
    const f = fields();
    const a = await post(await multipart(f, [{ data: jpeg() }]));
    const b = await post(await multipart(f, [{ data: jpeg() }]));
    expect(b.statusCode).toBe(202);
    expect(b.json().jobId).toBe(a.json().jobId);
  });

  it('rejects invalid fields with 400 bad_input', async () => {
    const res = await post(await multipart({ clipId: 'not-a-uuid', petType: 'dog' }, [{ data: jpeg() }]));
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('bad_input');
    expect((await post(await multipart({ ...fields(), petType: 'fish' }, [{ data: jpeg() }]))).statusCode).toBe(400);
    expect((await post(await multipart(fields(), []))).statusCode).toBe(400);
  });

  it('rejects non-JPEG frames with 400', async () => {
    const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
    expect((await post(await multipart(fields(), [{ data: png, type: 'image/png' }]))).statusCode).toBe(400);
    // Claims JPEG but isn't one.
    expect((await post(await multipart(fields(), [{ data: png }]))).statusCode).toBe(400);
  });

  it('rejects more than 5 frames with 413', async () => {
    const res = await post(await multipart(fields(), Array.from({ length: 6 }, () => ({ data: jpeg() }))));
    expect(res.statusCode).toBe(413);
    expect(res.json().error).toBe('bad_input');
  });

  it('rejects a frame over 2 MB with 413', async () => {
    const res = await post(await multipart(fields(), [{ data: jpeg(2 * 1024 * 1024 + 1) }]));
    expect(res.statusCode).toBe(413);
    expect(res.json().error).toBe('bad_input');
  });
});
