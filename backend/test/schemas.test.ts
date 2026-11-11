import { describe, expect, it } from 'vitest';
import { ClipFields, Insight, ServerMessage } from '../src/schemas.js';
import { sampleInsight } from './helpers.js';

describe('schemas', () => {
  it('ClipFields accepts a valid clip and rejects bad ids and pet types', () => {
    const clipId = crypto.randomUUID();
    expect(ClipFields.parse({ clipId, petType: 'dog', breedHint: 'beagle' })).toEqual({
      clipId,
      petType: 'dog',
      breedHint: 'beagle',
    });
    expect(ClipFields.safeParse({ clipId: 'nope', petType: 'dog' }).success).toBe(false);
    expect(ClipFields.safeParse({ clipId, petType: 'hamster' }).success).toBe(false);
  });

  it('Insight enforces enums and confidence range', () => {
    expect(Insight.parse(sampleInsight)).toEqual(sampleInsight);
    expect(Insight.safeParse({ ...sampleInsight, mood: 'grumpy' }).success).toBe(false);
    expect(Insight.safeParse({ ...sampleInsight, confidence: 1.5 }).success).toBe(false);
    expect(
      Insight.safeParse({ ...sampleInsight, healthFlags: [{ flag: 'limping', severity: 'urgent', evidence: 'x' }] })
        .success,
    ).toBe(false);
  });

  it('ServerMessage covers every protocol message', () => {
    const jobId = 'j';
    for (const msg of [
      { type: 'status', jobId, status: 'analyzing' },
      { type: 'delta', jobId, text: 'hi' },
      { type: 'insight', jobId, insight: sampleInsight },
      { type: 'error', jobId, code: 'refused', message: 'no' },
      { type: 'done', jobId },
    ]) {
      expect(ServerMessage.safeParse(msg).success).toBe(true);
    }
    expect(ServerMessage.safeParse({ type: 'error', jobId, code: 'network', message: '' }).success).toBe(false);
  });
});
