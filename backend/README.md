# Meal-scan backend

A small [Cloudflare Worker](https://developers.cloudflare.com/workers/) that receives a meal photo from the iOS app,
asks Claude (vision + structured outputs) to identify the foods and estimate portions and nutrients, and returns
JSON the app shows for review.

The Anthropic API key lives only here, as a Worker secret. The iOS app never contains it.

```
iPhone ──HTTPS──▶ POST /v1/meal-scans (Worker) ──▶ Anthropic Messages API (claude-opus-5-5)
         JSON: base64 JPEG          validates, rate-limits, normalizes
```

## Endpoints

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/health` | Liveness check, returns `{"status":"ok"}` |
| `POST` | `/v1/meal-scans` | Analyze a photo |

Request (`Content-Type: application/json`):

```json
{ "imageBase64": "<base64 JPEG/PNG/WebP, ≤ 5 MB>", "mediaType": "image/jpeg", "locale": "de_DE", "note": "optional, ≤ 300 chars" }
```

Optional headers: `Authorization: Bearer <APP_CLIENT_TOKEN>`, `X-Installation-ID: <random UUID>` (rate-limit key).

Response `200`:

```json
{
  "containsFood": true,
  "mealName": "Chicken, rice and broccoli",
  "items": [
    { "name": "Grilled chicken breast", "portion": "1 fillet", "grams": 150, "calories": 248,
      "protein": 46.5, "carbs": 0, "fat": 5.4, "confidence": "high" }
  ],
  "notes": "Cooking oil may add calories."
}
```

Errors use `{"error": {"code": "...", "message": "..."}}` with these statuses: `400` invalid request or image,
`401` bad client token, `413` too large, `415` not JSON, `422` model declined the image, `429` rate limited,
`502`/`503` upstream problems.

## Security measures

* API key stored as a Worker secret (`wrangler secret put ANTHROPIC_API_KEY`), never in the repo or the app.
* Optional shared client token (`APP_CLIENT_TOKEN`), compared in constant time. Because it ships inside the app it is
  a speed bump for casual abuse, not a real secret. For production, add
  [App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity) verification.
* Per-installation (or per-IP) rate limit via the Workers Rate Limiting binding (20 scans/minute by default).
* Strict input validation: JSON only, body size limit checked before reading, base64 and locale formats, a supported
  media type, and file signature (magic bytes) matching the declared type.
* Photos and user notes are never logged or stored; logs contain only the failure category.
* Model output is clamped, rounded and truncated before it reaches the app.
* No CORS headers: browsers can't call the API from other websites.

## Model configuration

| Variable | Default | Notes |
| --- | --- | --- |
| `CLAUDE_MODEL` | `claude-opus-5-5` | Any vision-capable Claude model. |
| `CLAUDE_EFFORT` | `medium` | `low` answers faster and costs less; `high` thinks longer about portions. |

Requests enable server-side refusal fallback (`fallbacks: "default"`): if a safety classifier declines a request,
the API retries it on the recommended fallback model within the same call. A food photo will rarely trigger this.

## Run locally

```bash
cd backend
npm install
cp .dev.vars.example .dev.vars        # add your ANTHROPIC_API_KEY
npm run dev                           # http://localhost:8787
npm test                              # unit tests (no API key needed)
npm run check                         # typecheck + tests + bundle
```

To point the iOS simulator at the local Worker, set `SCAN_API_BASE_URL = http:/$()/localhost:8787` in
`ios/Config/Secrets.xcconfig` (local networking is allowed by the app's ATS settings).

## Deploy

```bash
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put APP_CLIENT_TOKEN   # optional; use the same value as SCAN_API_CLIENT_TOKEN in the app
npm run deploy
```

Then set `SCAN_API_BASE_URL` in `ios/Config/Secrets.xcconfig` to the deployed URL
(e.g. `https:/$()/calorie-scan.<account>.workers.dev`).

**Plan note:** a photo upload is a ~0.5–1 MB JSON body. Parsing and forwarding it can exceed the 10 ms CPU limit of
the Workers Free plan, so use the Workers Paid plan for production.

The handler only uses web-standard `Request`/`Response`, so `src/handler.ts` can be reused on other runtimes
(Deno, Bun, Node 18+) with a few lines of glue.
