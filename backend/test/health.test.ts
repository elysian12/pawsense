import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';
import { buildServer } from '../src/server.js';

describe('GET /health', () => {
  it('returns ok', async () => {
    const app = buildServer(loadConfig({ API_TOKEN: 'test' }));
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: 'ok' });
    await app.close();
  });
});

describe('loadConfig', () => {
  it('rejects a missing API_TOKEN and defaults PORT', () => {
    expect(() => loadConfig({})).toThrow(/API_TOKEN/);
    expect(loadConfig({ API_TOKEN: 't' }).PORT).toBe(8080);
  });
});
