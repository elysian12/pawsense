import { randomUUID } from 'node:crypto';
import type { FastifyBaseLogger } from 'fastify';
import type { ClipFields, ServerMessage } from '../schemas.js';
import type { VisionService } from './vision.js';

export const RESULT_TTL_MS = 15 * 60 * 1000;

type Listener = (msg: ServerMessage) => void;

interface Job {
  id: string;
  clip: ClipFields;
  frames: Buffer[];
  state: 'pending' | 'running' | 'finished';
  final?: ServerMessage; // insight or error
  listeners: Set<Listener>;
  expiresAt: number; // pending and finished jobs expire; running ones never do
}

// ponytail: in-memory, single process. Jobs are lost on restart (the app re-posts by clipId); Redis if we scale out.
export class JobStore {
  private readonly jobs = new Map<string, Job>();
  private readonly byClip = new Map<string, string>();
  private readonly sweeper: NodeJS.Timeout;

  constructor(
    private readonly vision: VisionService,
    private readonly log: FastifyBaseLogger,
    private readonly now: () => number = Date.now,
  ) {
    this.sweeper = setInterval(() => this.sweep(), 60_000).unref();
  }

  /**
   * Idempotent by clipId: a repeat returns the existing job's id and keeps its frames,
   * unless that job finished with an error. Then it is a retry: a new job with these frames.
   */
  create(clip: ClipFields, frames: Buffer[]): string {
    const existingId = this.byClip.get(clip.clipId);
    const existing = existingId === undefined ? undefined : this.get(existingId);
    if (existing && existing.final?.type !== 'error') return existing.id;
    if (existing) this.remove(existing);

    const job: Job = {
      id: randomUUID(),
      clip,
      frames,
      state: 'pending',
      listeners: new Set(),
      expiresAt: this.now() + RESULT_TTL_MS,
    };
    this.jobs.set(job.id, job);
    this.byClip.set(clip.clipId, job.id);
    return job.id;
  }

  /**
   * Subscribes to a job's messages, starting the vision call if nobody has yet.
   * A finished job replays its final message + done. Returns an unsubscribe function,
   * or undefined if the job is unknown or expired.
   */
  attach(jobId: string, listener: Listener): (() => void) | undefined {
    const job = this.get(jobId);
    if (!job) return undefined;

    if (job.state === 'finished') {
      listener(job.final!);
      listener({ type: 'done', jobId });
      return () => {};
    }

    job.listeners.add(listener);
    listener({ type: 'status', jobId, status: 'analyzing' });
    if (job.state === 'pending') void this.run(job);
    return () => job.listeners.delete(listener);
  }

  close(): void {
    clearInterval(this.sweeper);
  }

  private get(jobId: string): Job | undefined {
    const job = this.jobs.get(jobId);
    if (job && job.expiresAt <= this.now()) {
      this.remove(job);
      return undefined;
    }
    return job;
  }

  private async run(job: Job): Promise<void> {
    job.state = 'running';
    job.expiresAt = Infinity;
    const started = performance.now();
    let firstDelta = true;
    let final: ServerMessage | undefined;

    try {
      for await (const ev of this.vision.analyze({ frames: job.frames, ...job.clip })) {
        if (ev.type === 'delta') {
          if (firstDelta) {
            firstDelta = false;
            // Time to first insight token, for docs/METRICS.md.
            this.log.info({ jobId: job.id, ttfdMs: Math.round(performance.now() - started) }, 'vision first delta');
          }
          this.emit(job, { type: 'delta', jobId: job.id, text: ev.text });
        } else if (ev.type === 'insight') {
          final = { type: 'insight', jobId: job.id, insight: ev.insight };
        } else {
          final = { type: 'error', jobId: job.id, code: ev.code, message: ev.message };
        }
      }
    } catch (err) {
      this.log.error({ err, jobId: job.id }, 'vision service threw');
    }

    job.final = final ?? { type: 'error', jobId: job.id, code: 'internal', message: 'The analysis failed.' };
    job.state = 'finished';
    job.frames = [];
    job.expiresAt = this.now() + RESULT_TTL_MS;
    this.log.info(
      { jobId: job.id, totalMs: Math.round(performance.now() - started), result: job.final.type },
      'vision finished',
    );
    this.emit(job, job.final);
    this.emit(job, { type: 'done', jobId: job.id });
    job.listeners.clear();
  }

  private emit(job: Job, msg: ServerMessage): void {
    for (const listener of job.listeners) listener(msg);
  }

  private sweep(): void {
    for (const job of this.jobs.values()) this.get(job.id);
  }

  private remove(job: Job): void {
    this.jobs.delete(job.id);
    if (this.byClip.get(job.clip.clipId) === job.id) this.byClip.delete(job.clip.clipId);
  }
}
