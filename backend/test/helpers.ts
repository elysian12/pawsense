import type { AddressInfo } from 'node:net';
import { WebSocket } from 'ws';
import { loadConfig } from '../src/config.js';
import type { Insight } from '../src/schemas.js';
import { buildServer } from '../src/server.js';
import type { VisionEvent, VisionService } from '../src/services/vision.js';

export const TOKEN = 'test-token';
export const AUTH = { authorization: `Bearer ${TOKEN}` };

export const jpeg = (size = 16) => {
  const b = Buffer.alloc(size);
  b.set([0xff, 0xd8, 0xff, 0xe0]);
  return b;
};

export const sampleInsight: Insight = {
  mood: 'playful',
  activity: 'playing',
  healthFlags: [],
  summary: 'The dog is chasing a ball.',
  confidence: 0.8,
};

/** Mock vision service: replays `events` and counts calls. */
export function mockVision(events: VisionEvent[] = [
  { type: 'delta', text: '{"mood":' },
  { type: 'delta', text: '"playful"...' },
  { type: 'insight', insight: sampleInsight },
]) {
  const svc = {
    calls: 0,
    async *analyze() {
      svc.calls++;
      for (const e of events) yield e;
    },
  } satisfies VisionService & { calls: number };
  return svc;
}

export function makeApp(vision: VisionService = mockVision()) {
  return buildServer(loadConfig({ API_TOKEN: TOKEN }), { vision });
}

export async function multipart(
  fields: Record<string, string>,
  frames: { data: Buffer; type?: string; field?: string }[],
) {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.append(k, v);
  frames.forEach((f, i) =>
    fd.append(f.field ?? 'frames[]', new Blob([new Uint8Array(f.data)], { type: f.type ?? 'image/jpeg' }), `f${i}.jpg`),
  );
  const req = new Request('http://localhost', { method: 'POST', body: fd });
  return {
    payload: Buffer.from(await req.arrayBuffer()),
    headers: { 'content-type': req.headers.get('content-type')! },
  };
}

export async function listen(app: ReturnType<typeof makeApp>) {
  await app.listen({ port: 0, host: '127.0.0.1' });
  return `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}`;
}

/** Connects and collects every message until the server closes the socket. */
export function collect(url: string, headers: Record<string, string> = {}) {
  return new Promise<{ messages: Record<string, unknown>[]; code: number }>((resolve, reject) => {
    const ws = new WebSocket(url, { headers });
    const messages: Record<string, unknown>[] = [];
    ws.on('message', (data) => messages.push(JSON.parse(String(data))));
    ws.on('close', (code) => resolve({ messages, code }));
    ws.on('unexpected-response', (_req, res) => reject(new Error(`HTTP ${res.statusCode}`)));
    ws.on('error', reject);
  });
}
