# Clip analysis API: REST + WebSocket contract

The app uploads a clip's keyframes over REST, then streams the analysis over a
WebSocket. Source of truth for `backend/src/schemas.ts` (zod) and the app's
`features/clip_analysis` data layer (`ClipInsight.fromJson`,
`ClipAnalysisEvent`).

## Auth

Every request carries the shared app token (`API_TOKEN`, from
`dart_defines.json` in the app and `.env` on the backend):

- REST: `Authorization: Bearer <API_TOKEN>` header.
- WebSocket: the same header **or** a `token=<API_TOKEN>` query parameter.
  Some WebSocket clients cannot set headers on the upgrade request, so the
  server accepts either; if both are present the header wins.

A missing or wrong token gets `401` (REST) or the upgrade is rejected with
`401` (WS). The Anthropic API key never leaves the backend.

## `POST /v1/clips`

`multipart/form-data`:

| Field | Type | Rules |
|---|---|---|
| `clipId` | string | Client-generated UUID (v4). **Idempotency key.** |
| `petType` | string | `cat` \| `dog` \| `unknown` |
| `breedHint` | string | Optional. Breed label from on-device classification. |
| `frames[]` | file | 1-5 JPEG files (`image/jpeg`), each at most 2 MB. Order = time order. The server also accepts the field name `frames`. |

Multipart limits (enforced by the server): at most 5 files of 2 MB each,
10 text fields of at most 1 KB each, 15 parts in total. A file under any other
field name is a `400`.

Responses:

| Status | Body | When |
|---|---|---|
| `202 Accepted` | `{ "jobId": "…", "streamUrl": "/v1/stream?jobId=…" }` | Job created (or already exists for this `clipId`). |
| `400 Bad Request` | `{ "error": "bad_input", "message": "…" }` | Validation failed (zod). |
| `401 Unauthorized` | `{ "error": "unauthorized" }` | Bad/missing token. |
| `413 Payload Too Large` | `{ "error": "bad_input", "message": "…" }` | A frame over 2 MB or more than 5 frames. |
| `500 Internal Server Error` | `{ "error": "internal", "message": "…" }` | Unexpected server failure. Safe to retry with the same `clipId`. |

**Idempotency:** posting the same `clipId` again (e.g. the app retried after a
timeout) returns `202` with the **same** `jobId` and does not start a second
analysis. The exception is a job that **finished with an `error`**:
re-posting its `clipId` is a retry and starts a **new** job (new `jobId`, the
newly uploaded frames). Pending, running and successfully finished jobs are
always returned as-is. `streamUrl` is relative to `API_BASE_URL` (swap `http` for `ws`);
the client appends `&token=…` if it authenticates by query.

## `GET /v1/stream?jobId=…[&token=…]` (WebSocket)

On connect, the server starts the vision call for the job, or attaches to the
one already running, and forwards events. Messages are JSON text frames,
server → client only. Every message has `type` and `jobId`.

```jsonc
// server → client
{ "type": "status",  "jobId": "…", "status": "analyzing" }
{ "type": "delta",   "jobId": "…", "text": "…partial text…" }
{ "type": "insight", "jobId": "…", "insight": {
    "mood": "relaxed|playful|anxious|alert|tired|unknown",
    "activity": "sleeping|playing|eating|walking|resting|grooming|other",
    "healthFlags": [ { "flag": "limping", "severity": "low|medium|high", "evidence": "…" } ],
    "summary": "2–3 sentence plain-language summary",
    "confidence": 0.0
} }
{ "type": "error",   "jobId": "…", "code": "refused|timeout|bad_input|internal", "message": "…" }
{ "type": "done",    "jobId": "…" }
```

| Type | Meaning |
|---|---|
| `status` | Job state. `status` is `analyzing` while the model runs (later values the client should tolerate: `analyzed`, `failed`). |
| `delta` | A chunk of the model's streamed text. Append in order; for the "typing" effect only, never parsed. |
| `insight` | The final structured result. `confidence` is in [0, 1]; `healthFlags` may be empty. Health flags are observations, not diagnoses. |
| `error` | Analysis failed. `refused`: the model declined (stop_reason `refusal`). `timeout`: the model call timed out. `bad_input`: unusable frames. `internal`: anything else (incl. rate limits after retries). |
| `done` | Always the last message, after `insight` or `error`. The server then closes the socket with code 1000. |

Order for a successful job: `status` → `delta`* → `insight` → `done`.
For a failed job: `status` → `delta`* → `error` → `done`.

Unknown enum values must not crash the client: it maps them to `unknown`
(mood), `other` (activity) or `low` (severity). Unknown message types are
ignored.

Errors that happen before the job exists (unknown `jobId`) are sent as one
`error` message with `code: "bad_input"` followed by `done`.

## Reconnects and replay

- If the socket drops, the client reconnects to the same `jobId`. A job still
  running is re-attached (deltas sent before the reconnect are not replayed).
- When a job has finished, the server keeps its final result for **15 minutes**.
  Connecting in that window replays `insight` (or `error`) followed by `done`
  immediately, without calling the model again.
- After 15 minutes the job is gone: the client re-posts the clip with the same
  `clipId` (idempotent) to start a new job.
- The client saves the insight to Drift keyed by `clipId`, so a replayed
  insight never duplicates a feed entry.
