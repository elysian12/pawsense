import Anthropic from '@anthropic-ai/sdk';
import { zodOutputFormat } from '@anthropic-ai/sdk/helpers/zod';
import type { FastifyBaseLogger } from 'fastify';
import { type ErrorCode, Insight } from '../schemas.js';

export interface VisionInput {
  frames: Buffer[]; // JPEGs in time order
  petType: 'cat' | 'dog' | 'unknown';
  breedHint?: string;
}

export type VisionEvent =
  | { type: 'delta'; text: string }
  | { type: 'insight'; insight: Insight }
  | { type: 'error'; code: ErrorCode; message: string };

/** Streams zero or more deltas, then exactly one insight or error. Never throws. */
export interface VisionService {
  analyze(input: VisionInput): AsyncIterable<VisionEvent>;
}

export const MODEL = 'claude-opus-5-5';

const SYSTEM = `You are a careful pet-behavior observer. You are shown keyframes, in time order, from a short video of a pet.
- Describe only what is visible in the frames. Do not guess at anything you cannot see.
- Health flags are observations, not diagnoses (for example "favoring left hind leg", not "hip dysplasia"). Cite the visible evidence for each one.
- For anything concerning, say in the summary that a vet should take a look.
- Never invent breed or medical facts. Use "unknown" (mood) or "other" (activity) when unsure, and lower confidence to match.
- If nothing looks concerning, return an empty healthFlags list.
- confidence is your overall certainty from 0 to 1. summary is 2-3 plain-language sentences for the pet's owner.`;

function userPrompt({ frames, petType, breedHint }: VisionInput): string {
  const pet = petType === 'unknown' ? 'pet' : petType;
  const hint = breedHint ? ` An on-device classifier guessed the breed "${breedHint}"; treat it as a hint, not a fact.` : '';
  return `These ${frames.length} frames are from a 10-second clip of a ${pet}.${hint} Report its mood, activity and any visible health flags.`;
}

export function createClaudeVision(client: Anthropic, log: FastifyBaseLogger): VisionService {
  return {
    async *analyze(input) {
      try {
        const stream = client.beta.messages.stream({
          model: MODEL,
          max_tokens: 8000,
          // Thinking is always on for this model: no `thinking` param. Effort low = quick visual read.
          output_config: { effort: 'low', format: zodOutputFormat(Insight) },
          // On a safety refusal the API re-runs the request on a fallback model inside the same stream.
          betas: ['server-side-fallback-2026-07-01'],
          fallbacks: 'default',
          system: SYSTEM,
          messages: [
            {
              role: 'user',
              content: [
                ...input.frames.map((f) => ({
                  type: 'image' as const,
                  source: { type: 'base64' as const, media_type: 'image/jpeg' as const, data: f.toString('base64') },
                })),
                { type: 'text' as const, text: userPrompt(input) },
              ],
            },
          ],
        });

        for await (const event of stream) {
          if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
            yield { type: 'delta', text: event.delta.text };
          }
        }

        const final = await stream.finalMessage();
        if (final.stop_reason === 'refusal') {
          log.warn({ category: final.stop_details?.category }, 'vision refused');
          yield { type: 'error', code: 'refused', message: 'The model declined to analyze this clip.' };
          return;
        }
        if (final.stop_reason === 'max_tokens') {
          yield { type: 'error', code: 'internal', message: 'The analysis was cut off.' };
          return;
        }

        const text = final.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
        const parsed = Insight.safeParse(parseJson(text));
        if (!parsed.success) {
          log.error({ text }, 'vision returned an invalid insight');
          yield { type: 'error', code: 'internal', message: 'The model returned an invalid result.' };
          return;
        }
        yield { type: 'insight', insight: parsed.data };
      } catch (err) {
        log.error({ err }, 'vision call failed');
        yield { type: 'error', ...mapError(err) };
      }
    },
  };
}

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

// Most specific first. The SDK already retried 429/5xx/connection errors (maxRetries).
function mapError(err: unknown): { code: ErrorCode; message: string } {
  if (err instanceof Anthropic.RateLimitError) return { code: 'internal', message: 'Rate limited, try again shortly.' };
  if (err instanceof Anthropic.APIConnectionError) return { code: 'timeout', message: 'The model call timed out.' };
  if (err instanceof Anthropic.BadRequestError) return { code: 'bad_input', message: 'The frames could not be analyzed.' };
  return { code: 'internal', message: 'The analysis failed.' };
}
