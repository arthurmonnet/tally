# Handoff: PulseBar API Receiver for arthurmonnet.com

## Goal

Add a webhook endpoint to **arthurmonnet.com** (portfolio-2026) that receives daily developer stats pushed from the **PulseBar** macOS app, stores them, and exposes them for display on the site.

---

## Context

**PulseBar** is a macOS menu bar app that collects developer activity stats (keystrokes, clicks, git commits, app usage, etc.) and can push a daily JSON summary to any HTTPS endpoint. Arthur wants to receive that data on his portfolio website so he can display live/daily developer stats publicly.

---

## Target Project

| Key | Value |
|-----|-------|
| Path | `/Users/arthurmonnet/projects/portfolio-2026` |
| Framework | Next.js 16.1.6 (App Router) |
| Language | TypeScript 5.9 (strict mode) |
| Styling | Tailwind CSS v4 |
| Hosting | Vercel |
| Database | **None currently** — data is static in-memory objects |
| Auth | None — only in-memory rate limiting on some routes |
| Validation | Zod available in deps, mostly manual type guards used |
| Path alias | `@/*` → `./src/*` |

### Existing API route pattern

All routes live in `src/app/api/[resource]/route.ts` and follow this shape:

```typescript
import { NextResponse } from "next/server";

export async function POST(request: Request) {
  try {
    const body = await request.json();
    // validate, process
    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("[route] error:", error);
    return NextResponse.json({ error: "Server error" }, { status: 500 });
  }
}
```

### Deployment config

`vercel.json` maps function memory/timeout per route. New routes need an entry:

```json
{
  "functions": {
    "src/app/api/pulse/route.ts": { "memory": 128, "maxDuration": 10 }
  }
}
```

### Environment variables

Stored in `.env.local` and Vercel dashboard. Existing vars:
- `AI_GATEWAY_API_KEY`
- `RESEND`
- `NEXT_PUBLIC_REVIEW_HUB_URL`

---

## What to Build

### 1. POST `/api/pulse` — Webhook receiver

Receives the JSON payload from PulseBar and stores it.

**Authentication:** Validate a shared secret via Bearer token.

```
Authorization: Bearer <PULSE_API_TOKEN>
```

Add env var: `PULSE_API_TOKEN` — a secret token shared between PulseBar and the website. Reject with `401` if missing or wrong.

**Validation:** Validate the incoming payload with Zod (already in deps). Schema below.

**Storage:** Since there's no database, use **Vercel KV (Redis)** or **Vercel Blob** to persist daily summaries. Vercel KV is simpler for key-value lookups by date. Alternatively, a simple JSON file via Vercel Blob works.

Recommended: **Vercel KV** — add `@vercel/kv` to deps.
- Key pattern: `pulse:{date}` (e.g. `pulse:2026-03-13`)
- Value: the full validated payload as JSON
- Also maintain a `pulse:latest` key pointing to the most recent push

**Response:**
- `200` on success
- `401` on bad/missing token
- `400` on invalid payload
- `429` on rate limit (optional)
- `500` on server error

### 2. GET `/api/pulse` — Read stats

Public endpoint to fetch stored stats for display.

- `GET /api/pulse` → returns latest day's stats
- `GET /api/pulse?date=2026-03-13` → returns specific day
- `GET /api/pulse?range=7` → returns last 7 days

Cache with `Cache-Control: public, s-maxage=300, stale-while-revalidate=3600`.

### 3. Types — `src/lib/pulse-types.ts`

Shared TypeScript types and Zod schema for the PulseBar payload:

```typescript
import { z } from "zod";

const appTimeEntrySchema = z.object({
  name: z.string(),
  minutes: z.number(),
});

export const pulsePayloadSchema = z.object({
  version: z.literal(1),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  keystrokes: z.number().int().nonnegative(),
  clicks: z.number().int().nonnegative(),
  copy_paste: z.number().int().nonnegative(),
  screenshots: z.number().int().nonnegative(),
  cmd_z: z.number().int().nonnegative(),
  launcher_opens: z.number().int().nonnegative(),
  app_switches: z.number().int().nonnegative(),
  scroll_distance_m: z.number().nonnegative(),
  mouse_distance_m: z.number().nonnegative(),
  dark_mode_minutes: z.number().int().nonnegative(),
  light_mode_minutes: z.number().int().nonnegative(),
  top_apps: z.array(appTimeEntrySchema),
  files_created: z.record(z.string(), z.number().int()),
  files_deleted: z.number().int().nonnegative(),
  git_commits: z.number().int().nonnegative(),
  git_stashes: z.number().int().nonnegative(),
  peak_ram_gb: z.number().nonnegative(),
  active_hours: z.number().nonnegative(),
  achievements_unlocked: z.array(z.string()),
  fun_line: z.string(),
});

export type PulsePayload = z.infer<typeof pulsePayloadSchema>;
export type AppTimeEntry = z.infer<typeof appTimeEntrySchema>;
```

---

## PulseBar Push Behavior (what the sender does)

| Detail | Value |
|--------|-------|
| HTTP method | `POST` |
| Content-Type | `application/json` |
| Auth header | `Authorization: Bearer <token>` |
| Timeout | 30 seconds |
| Retry | 1 retry after 5s on failure |
| Success | Any 2xx status code |
| Triggers | Scheduled (30min/1hr/3hr), on app quit, on wake-from-sleep, manual |

The payload is **always the full day's stats up to now** — not a delta. Each push for the same date replaces the previous one (upsert by date).

---

## Full JSON Payload Example

```json
{
  "version": 1,
  "date": "2026-03-13",
  "keystrokes": 14832,
  "clicks": 2341,
  "copy_paste": 87,
  "screenshots": 5,
  "cmd_z": 42,
  "launcher_opens": 23,
  "app_switches": 318,
  "scroll_distance_m": 127.4,
  "mouse_distance_m": 84.2,
  "dark_mode_minutes": 420,
  "light_mode_minutes": 60,
  "top_apps": [
    { "name": "Xcode", "minutes": 185.3 },
    { "name": "Safari", "minutes": 94.1 },
    { "name": "Terminal", "minutes": 67.8 }
  ],
  "files_created": { ".swift": 4, ".json": 1 },
  "files_deleted": 2,
  "git_commits": 7,
  "git_stashes": 1,
  "peak_ram_gb": 12.4,
  "active_hours": 8.0,
  "achievements_unlocked": ["streak_7d", "commits_100"],
  "fun_line": "You scrolled the height of the Eiffel Tower today!"
}
```

---

## Implementation Steps

### Step 1: Add dependencies

```bash
npm install @vercel/kv
```

Add `PULSE_API_TOKEN` and `KV_REST_API_URL` / `KV_REST_API_TOKEN` to `.env.local` and Vercel dashboard.

### Step 2: Create types file

Create `src/lib/pulse-types.ts` with the Zod schema and exported types (see above).

### Step 3: Create API route

Create `src/app/api/pulse/route.ts` with:

- **POST handler:**
  1. Extract and validate Bearer token from `Authorization` header
  2. Parse and validate body with `pulsePayloadSchema`
  3. Store in Vercel KV: `set("pulse:{date}", payload)` and `set("pulse:latest", payload)`
  4. Return `{ ok: true }`

- **GET handler:**
  1. Read `?date=` param or default to `pulse:latest`
  2. If `?range=N`, fetch last N days using KV scan or date math
  3. Return JSON with CORS + cache headers

### Step 4: Update vercel.json

Add the function config for the new route.

### Step 5: Configure PulseBar

In PulseBar settings:
- Endpoint: `https://arthurmonnet.com/api/pulse`
- API Token: same value as `PULSE_API_TOKEN` env var
- Frequency: Every hour (or preference)

### Step 6 (optional): Display component

Create a component that fetches `GET /api/pulse` and renders stats on the portfolio. This is a follow-up task — get the receiver working first.

---

## Key Files to Touch

| File | Action |
|------|--------|
| `src/lib/pulse-types.ts` | **Create** — Zod schema + types |
| `src/app/api/pulse/route.ts` | **Create** — POST + GET handlers |
| `vercel.json` | **Edit** — add function config |
| `.env.local` | **Edit** — add `PULSE_API_TOKEN`, KV credentials |
| `package.json` | **Edit** — add `@vercel/kv` |

---

## Constraints

- **No database migrations** — use Vercel KV (serverless Redis), no schema to manage.
- **Upsert semantics** — same date push replaces previous data (PulseBar sends cumulative stats, not deltas).
- **HTTPS only** — Vercel handles TLS.
- **Keep it simple** — no auth framework, just Bearer token comparison.
- **Follow existing patterns** — match the try/catch + NextResponse.json style used in other routes.
- **Immutability** — never mutate request objects or shared state; create new response objects.

---

## API Documentation

Full API docs (payload schema, auth, error codes, example server) are available at:
`/Users/arthurmonnet/Projects/PulseBar/docs/api.html`

Open with: `open /Users/arthurmonnet/Projects/PulseBar/docs/api.html`
