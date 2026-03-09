# WHOOP → TRMNL Plugin

Displays your daily WHOOP recovery score, sleep metrics, and strain data on a TRMNL e-ink display.

```
┌─────────────────────────────────────────────┐
│ ⟳ WHOOP                              scored │
│─────────────────────────────────────────────│
│  ╭──────╮   HRV          Resting HR         │
│  │  78% │   82 ms        52 bpm             │
│  │Recov.│   SpO₂         Skin Temp          │
│  ╰──────╯   98.2%        36.1°C             │
│─────────────────────────────────────────────│
│  😴 SLEEP              ⚡ STRAIN            │
│  Performance  84%      Day Strain   8.4     │
│  Duration     7h 48m   Avg HR       68 bpm  │
│  Deep         1h 06m   Calories     2,214   │
│  REM          1h 52m   Kilojoules   9,264   │
│  Efficiency   91%                           │
│  Resp. Rate   14.8 rpm                      │
└─────────────────────────────────────────────┘
```

---

## Architecture

```
TRMNL device  ──polls──▶  Cloudflare Worker  ──fetches──▶  WHOOP API
                          (handles OAuth,
                           token refresh,
                           data shaping)
```

TRMNL's **Polling** strategy hits your Worker URL every 15–60 minutes. The Worker uses your stored OAuth refresh token to get a fresh access token, calls three WHOOP endpoints in parallel, and returns a flat JSON object that TRMNL's Liquid template can render.

---

## Setup Guide

### Step 1 — Create a WHOOP Developer App

1. Go to [developer-dashboard.whoop.com](https://developer-dashboard.whoop.com) and sign in.
2. Click **Create App**.
3. Set the redirect URI to `http://localhost:3000/callback` (for the one-time token fetch).
4. Note your **Client ID** and **Client Secret**.
5. Enable these scopes: `offline`, `read:recovery`, `read:cycles`, `read:sleep`, `read:profile`, `read:body_measurement`.

### Step 2 — Get Your Refresh Token (one time only)

```bash
cd oauth/
npm install       # installs nothing; uses only Node built-ins
WHOOP_CLIENT_ID=xxx WHOOP_CLIENT_SECRET=yyy node get_token.js
```

Open the printed URL in your browser, authorize, and your terminal will print a `WHOOP_REFRESH_TOKEN`. **Save it securely.**

### Step 3 — Deploy the Cloudflare Worker

You need [Wrangler](https://developers.cloudflare.com/workers/wrangler/) (Cloudflare's CLI):

```bash
npm install -g wrangler
wrangler login

cd worker/
wrangler deploy
```

Then store secrets (you'll be prompted for each value):

```bash
wrangler secret put WHOOP_CLIENT_ID
wrangler secret put WHOOP_CLIENT_SECRET
wrangler secret put WHOOP_REFRESH_TOKEN   # from Step 2
wrangler secret put WORKER_API_KEY        # make up a random string, e.g. openssl rand -hex 16
```

**Optional but recommended:** Add KV-based token caching (reduces API calls):

```bash
wrangler kv:namespace create "WHOOP_KV"
# copy the printed id, uncomment the [[kv_namespaces]] block in wrangler.toml, paste the id
wrangler deploy
```

Your Worker URL will be something like:
`https://whoop-trmnl.YOUR_SUBDOMAIN.workers.dev`

Test it:
```bash
curl "https://whoop-trmnl.YOUR_SUBDOMAIN.workers.dev/?api_key=YOUR_KEY"
```

You should see JSON like:
```json
{
  "recovery_score": 78,
  "hrv_rmssd_milli": 82,
  "resting_heart_rate": 52,
  "sleep_performance_pct": 84,
  "sleep_duration": "7h 48m",
  ...
}
```

### Step 4 — Create the TRMNL Private Plugin

1. In TRMNL, go to **Plugins → Private Plugin → Add**.
2. **Name:** WHOOP Dashboard (or whatever you like).
3. **Strategy:** Polling.
4. **Polling URL:**
   ```
   https://whoop-trmnl.YOUR_SUBDOMAIN.workers.dev/?api_key=YOUR_KEY
   ```
5. Click **Edit Markup** and paste the contents of `trmnl/markup.html`.
6. Save and add the plugin to your playlist.

---

## Available Template Variables

| Variable | Type | Description |
|---|---|---|
| `recovery_score` | integer | Recovery % (0–100) |
| `recovery_color` | string | `green` / `yellow` / `red` |
| `hrv_rmssd_milli` | integer | HRV in milliseconds |
| `resting_heart_rate` | integer | RHR in bpm |
| `spo2_percentage` | string | Blood oxygen % (4.0 only) |
| `skin_temp_celsius` | string | Skin temp °C (4.0 only) |
| `sleep_performance_pct` | integer | Sleep performance % |
| `sleep_duration` | string | e.g. `"7h 48m"` |
| `sleep_deep_duration` | string | Deep (SWS) sleep |
| `sleep_rem_duration` | string | REM sleep |
| `sleep_efficiency_pct` | integer | Sleep efficiency % |
| `respiratory_rate` | string | Breaths per minute |
| `day_strain` | string | Strain score (0–21 scale) |
| `avg_heart_rate` | integer | Avg HR over cycle |
| `calories` | integer | kcal burned |
| `kilojoules` | integer | kJ (WHOOP native) |
| `score_state` | string | `SCORED` / `PENDING_SLEEP` |
| `last_updated` | string | ISO timestamp |

---

## Customization Tips

**Show only recovery (minimal layout):** Remove the `lower-grid` div from the markup.

**Imperial temperatures:** In the Worker, convert `skin_temp_celsius` before returning:
```js
skin_temp_fahrenheit: rec?.score?.skin_temp_celsius != null
  ? ((rec.score.skin_temp_celsius * 9/5) + 32).toFixed(1) : null,
```

**Refresh rate:** In TRMNL plugin settings, set the refresh interval. 30–60 minutes is ideal since WHOOP data updates after sleep/workouts are processed, not in real time.

---

## File Structure

```
whoop-trmnl/
├── worker/
│   ├── index.js         ← Cloudflare Worker (deploy this)
│   └── wrangler.toml    ← Deployment config
├── trmnl/
│   └── markup.html      ← Paste into TRMNL plugin editor
├── oauth/
│   └── get_token.js     ← One-time OAuth helper
└── README.md
```

---

## Troubleshooting

**Worker returns 401:** Check that `WORKER_API_KEY` secret matches the `api_key` query param.

**Token refresh fails:** The refresh token may have expired (WHOOP tokens expire if unused). Re-run `get_token.js`.

**`score_state` shows `PENDING_SLEEP`:** Your WHOOP hasn't processed last night's sleep yet. The Worker returns whatever WHOOP has; the display will update once scoring completes.

**SpO2 / skin temp are null:** These are WHOOP 4.0+ only features.
