import { z } from 'zod';

// Wire contract from docs/WS_PROTOCOL.md. The app's ClipInsight.fromJson mirrors these.

export const PetType = z.enum(['cat', 'dog', 'unknown']);

export const ClipFields = z.object({
  clipId: z.uuid(),
  petType: PetType,
  breedHint: z.string().trim().min(1).max(100).optional(),
});
export type ClipFields = z.infer<typeof ClipFields>;

export const Insight = z.object({
  mood: z.enum(['relaxed', 'playful', 'anxious', 'alert', 'tired', 'unknown']),
  activity: z.enum(['sleeping', 'playing', 'eating', 'walking', 'resting', 'grooming', 'other']),
  healthFlags: z.array(
    z.object({
      flag: z.string(),
      severity: z.enum(['low', 'medium', 'high']),
      evidence: z.string(),
    }),
  ),
  summary: z.string(),
  confidence: z.number().min(0).max(1),
});
export type Insight = z.infer<typeof Insight>;

export const ErrorCode = z.enum(['refused', 'timeout', 'bad_input', 'internal']);
export type ErrorCode = z.infer<typeof ErrorCode>;

export const StreamQuery = z.object({ jobId: z.string().min(1).max(100) });

export const ServerMessage = z.discriminatedUnion('type', [
  z.object({ type: z.literal('status'), jobId: z.string(), status: z.enum(['analyzing', 'analyzed', 'failed']) }),
  z.object({ type: z.literal('delta'), jobId: z.string(), text: z.string() }),
  z.object({ type: z.literal('insight'), jobId: z.string(), insight: Insight }),
  z.object({ type: z.literal('error'), jobId: z.string(), code: ErrorCode, message: z.string() }),
  z.object({ type: z.literal('done'), jobId: z.string() }),
]);
export type ServerMessage = z.infer<typeof ServerMessage>;
