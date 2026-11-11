import Anthropic from '@anthropic-ai/sdk';
import { describe, expect, it } from 'vitest';
import { createClaudeVision, MODEL, type VisionEvent } from '../src/services/vision.js';
import { jpeg, sampleInsight } from './helpers.js';

const silent = { info() {}, warn() {}, error() {} } as never;

/** Fake SDK client: `stream()` records params and replays text deltas, then a final message. */
function fakeClient(opts: { text?: string[]; final?: object; throws?: unknown }) {
  const calls: Record<string, unknown>[] = [];
  const client = {
    beta: {
      messages: {
        stream(params: Record<string, unknown>) {
          calls.push(params);
          const text = opts.text ?? [];
          return {
            async *[Symbol.asyncIterator]() {
              if (opts.throws) throw opts.throws;
              for (const t of text) yield { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: t } };
            },
            finalMessage: async () =>
              opts.final ?? { stop_reason: 'end_turn', stop_details: null, content: [{ type: 'text', text: text.join('') }] },
          };
        },
      },
    },
  };
  return { client: client as unknown as Anthropic, calls };
}

async function run(client: Anthropic): Promise<VisionEvent[]> {
  const events: VisionEvent[] = [];
  for await (const e of createClaudeVision(client, silent).analyze({ frames: [jpeg(), jpeg()], petType: 'dog' })) {
    events.push(e);
  }
  return events;
}

describe('createClaudeVision', () => {
  it('streams deltas then a validated insight, with the agreed request shape', async () => {
    const json = JSON.stringify(sampleInsight);
    const { client, calls } = fakeClient({ text: [json.slice(0, 10), json.slice(10)] });
    const events = await run(client);
    expect(events).toEqual([
      { type: 'delta', text: json.slice(0, 10) },
      { type: 'delta', text: json.slice(10) },
      { type: 'insight', insight: sampleInsight },
    ]);

    const p = calls[0]!;
    expect(p.model).toBe(MODEL);
    expect(p.betas).toEqual(['server-side-fallback-2026-07-01']);
    expect(p.fallbacks).toBe('default');
    expect(p).not.toHaveProperty('thinking');
    expect(p).not.toHaveProperty('temperature');
    const out = p.output_config as { effort: string; format: { type: string } };
    expect(out.effort).toBe('low');
    expect(out.format.type).toBe('json_schema');
    const content = (p.messages as { content: { type: string }[] }[])[0]!.content;
    expect(content.map((c) => c.type)).toEqual(['image', 'image', 'text']);
  });

  it('maps stop_reason refusal to a refused error', async () => {
    const { client } = fakeClient({
      text: ['{"mo'],
      final: { stop_reason: 'refusal', stop_details: { type: 'refusal', category: 'bio' }, content: [] },
    });
    expect((await run(client)).at(-1)).toMatchObject({ type: 'error', code: 'refused' });
  });

  it('maps max_tokens and unparseable output to internal', async () => {
    const cut = fakeClient({ final: { stop_reason: 'max_tokens', stop_details: null, content: [] } });
    expect((await run(cut.client)).at(-1)).toMatchObject({ type: 'error', code: 'internal' });
    const junk = fakeClient({ text: ['{"mood":"grumpy"}'] });
    expect((await run(junk.client)).at(-1)).toMatchObject({ type: 'error', code: 'internal' });
  });

  it('maps typed SDK errors to protocol codes', async () => {
    const headers = new Headers();
    const cases: [unknown, string][] = [
      [new Anthropic.APIConnectionTimeoutError(), 'timeout'],
      [new Anthropic.APIConnectionError({ message: 'down' }), 'timeout'],
      [new Anthropic.RateLimitError(429, undefined, 'slow down', headers), 'internal'],
      [new Anthropic.BadRequestError(400, undefined, 'bad image', headers), 'bad_input'],
      [new Anthropic.InternalServerError(500, undefined, 'boom', headers), 'internal'],
    ];
    for (const [err, code] of cases) {
      expect(await run(fakeClient({ throws: err }).client)).toEqual([{ type: 'error', code, message: expect.any(String) }]);
    }
  });
});
