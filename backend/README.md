# Backend

Fastify + TypeScript service that turns a clip's keyframes into a streamed
vision-model insight. Contract: [`docs/WS_PROTOCOL.md`](../docs/WS_PROTOCOL.md).

```
POST /v1/clips (multipart) ─► JobStore (in memory, 15 min TTL) ◄─ GET /v1/stream?jobId= (WebSocket)
                                   │
                                   └─► services/vision.ts ─► Claude (claude-opus-5-5, streaming, structured output)
```

| File | Role |
|---|---|
| `src/server.ts` | Fastify bootstrap, plugins, error mapping, log redaction of `?token=` |
| `src/config.ts` | zod-validated env |
| `src/auth.ts` | Bearer token check (header, or `?token=` for WebSocket; header wins) |
| `src/schemas.ts` | zod schemas for the wire protocol |
| `src/routes/clips.ts` | `POST /v1/clips`: up to 5 JPEGs ≤ 2 MB, idempotent by `clipId`, `202 {jobId, streamUrl}` |
| `src/routes/stream.ts` | `GET /v1/stream`: start or attach to the analysis, forward `status/delta/insight/error/done` |
| `src/services/jobs.ts` | Job store: one vision call per job, fan-out to sockets, replay of finished results |
| `src/services/vision.ts` | `VisionService` interface + the Claude implementation |

## Setup

```bash
cd backend
cp .env.example .env      # set API_TOKEN (long random string) and ANTHROPIC_API_KEY
npm ci
npm run dev               # tsx watch on :8080
```

Checks: `npm run lint` (eslint + `tsc --noEmit`), `npm test` (vitest, mocked vision,
no API key needed), `npm run build`.

Docker: `docker compose up --build` builds the multi-stage image and runs it with `.env`.

Quick manual test (no model call needed for the upload):

```bash
curl -H "Authorization: Bearer $API_TOKEN" \
  -F clipId=$(uuidgen | tr A-Z a-z) -F petType=dog -F "frames[]=@frame.jpg;type=image/jpeg" \
  localhost:8080/v1/clips
# then open ws://localhost:8080/v1/stream?jobId=<jobId>&token=$API_TOKEN (e.g. with `npx wscat -c`)
```

## The vision call

- `client.beta.messages.stream()` with model `claude-opus-5-5`, `max_tokens: 8000`,
  `output_config: { effort: 'low', format: zodOutputFormat(Insight) }`. This model
  always thinks; `effort: 'low'` keeps it a quick visual read. No `thinking`,
  `temperature` or prefill (the model rejects them).
- Structured output: the response text is guaranteed to follow the `Insight`
  JSON schema. The text deltas are forwarded as `delta` messages (the app shows
  them as a typing effect); the final text is parsed and re-validated with zod.
- Refusals: `betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default'`
  lets the API retry a safety-declined request on a fallback model inside the
  same stream. If the whole chain still refuses, `stop_reason === 'refusal'`
  becomes `{type:'error', code:'refused'}`.
- Errors are mapped by SDK error class, never by message: connection errors and
  timeouts → `timeout`, 400 → `bad_input`, rate limits (after the SDK's 2 retries)
  and everything else → `internal`.
- The system prompt keeps health flags to visible observations, never diagnoses,
  and asks for a vet suggestion when something looks concerning.

## Time to first delta (for `docs/METRICS.md`)

Each job logs `ttfdMs` and `totalMs`, both measured from the start of the vision
call (when the first socket connects), so upload time is not included. For the
app-side "time to first insight token", also time it in the app from tap to first delta.

```bash
docker compose logs api | grep -E 'ttfdMs|totalMs'        # local
docker logs pawsense-backend | grep -E 'ttfdMs|totalMs'   # VM (CI deploy)
```

Record the median over at least 10 real clips. Not measured yet: there was no API key during the build.

## Deploy (Phase 9)

CI (`.github/workflows/backend-ci.yml`) builds the image, pushes it to GHCR, then
deploys over SSH once `DEPLOY_HOST`, `DEPLOY_USER` and `DEPLOY_SSH_KEY` are set.
The VM needs only Docker and `~/pawsense/.env` (`ANTHROPIC_API_KEY`, `API_TOKEN`).
The deploy step runs:

```bash
docker pull ghcr.io/elysian12/pawsense-backend:<sha>
docker rm -f pawsense-backend
docker run -d --name pawsense-backend --restart unless-stopped \
  --env-file ~/pawsense/.env -p 8080:8080 ghcr.io/elysian12/pawsense-backend:<sha>
```

and waits for `/health`. To deploy by hand, run the same commands. `docker compose`
is for local runs (`docker compose up --build`); if you use it on the VM instead,
stop the `pawsense-backend` container first, since both bind port 8080.

The image has a `HEALTHCHECK` on `/health`. Jobs live in memory, so a restart drops
running jobs; the app re-posts the clip by `clipId` and gets a new job. Put TLS in
front (Caddy or the Lightsail load balancer) so the app can use `https`/`wss`.
