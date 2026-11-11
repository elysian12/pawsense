import { z } from 'zod';

const isTest = process.env.NODE_ENV === 'test' || process.env.VITEST === 'true';

const EnvSchema = z.object({
  PORT: z.coerce.number().int().positive().default(8080),
  API_TOKEN: z.string().min(1, 'API_TOKEN is required'),
  // Required at runtime; tests mock the vision service and run without it.
  ANTHROPIC_API_KEY: isTest ? z.string().optional() : z.string().min(1, 'ANTHROPIC_API_KEY is required'),
});

export type Config = z.infer<typeof EnvSchema>;

/** Parses and validates env vars; throws with every problem listed. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = EnvSchema.safeParse(env);
  if (!parsed.success) {
    throw new Error(`Invalid environment:\n${z.prettifyError(parsed.error)}`);
  }
  return parsed.data;
}
