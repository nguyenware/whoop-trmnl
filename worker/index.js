/**
 * Cloudflare Worker: WHOOP → TRMNL Data Proxy
 */

const WHOOP_BASE = "https://api.prod.whoop.com/developer";
const TOKEN_URL  = "https://api.prod.whoop.com/oauth/oauth2/token";

async function refreshAccessToken(env) {
  // WHOOP rotates refresh tokens: each one is single-use, and the old one is
  // invalidated the moment it's exchanged. The KV copy is the live token; the
  // WHOOP_REFRESH_TOKEN secret is only the seed for the very first refresh.
  let refreshToken = env.WHOOP_REFRESH_TOKEN?.trim();
  if (env.WHOOP_KV) {
    const kvToken = await env.WHOOP_KV.get("refresh_token");
    if (kvToken) refreshToken = kvToken;
  }
  if (!refreshToken) {
    throw new Error("No refresh token available. Set the WHOOP_REFRESH_TOKEN secret (see README Step 2).");
  }

  const body = new URLSearchParams({
    grant_type:    "refresh_token",
    refresh_token: refreshToken,
    client_id:     env.WHOOP_CLIENT_ID.trim(),
    client_secret: env.WHOOP_CLIENT_SECRET.trim(),
    scope:         "offline", // required by WHOOP to receive a new refresh token
  });

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  const text = await res.text();
  if (!res.ok) throw new Error(`Token refresh failed (${res.status}): ${text}`);

  const data = JSON.parse(text);

  if (env.WHOOP_KV) {
    // Store the rotated refresh token first — if this write is lost, the only
    // valid refresh token is gone and the user must re-run get_token.js.
    if (data.refresh_token) {
      await env.WHOOP_KV.put("refresh_token", data.refresh_token);
    }
    await env.WHOOP_KV.put("access_token", data.access_token, {
      expirationTtl: Math.max(60, (data.expires_in ?? 3600) - 300),
    });
  }

  return data.access_token;
}

async function getAccessToken(env) {
  // Try cached access token first
  if (env.WHOOP_KV) {
    const cached = await env.WHOOP_KV.get("access_token");
    if (cached) return cached;
  }
  // Access token missing or expired — refresh
  return refreshAccessToken(env);
}

// Returns null instead of throwing on 404
async function whoopGet(path, token) {
  const res = await fetch(`${WHOOP_BASE}${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 404) return null;
  if (!res.ok) {
    const err = new Error(`WHOOP ${path} → ${res.status}: ${await res.text()}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}

function fetchWhoopData(token) {
  return Promise.all([
    whoopGet("/v2/recovery?limit=1", token),
    whoopGet("/v2/activity/sleep?limit=5", token),
    whoopGet("/v2/cycle?limit=1", token),
  ]);
}

function fmtDuration(ms) {
  if (!ms) return "—";
  const h = Math.floor(ms / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  return `${h}h ${m}m`;
}

function recoveryColor(score) {
  if (score >= 67) return "green";
  if (score >= 34) return "yellow";
  return "red";
}

export default {
  async fetch(request, env) {
    const apiKey = request.headers.get("X-API-Key") || new URL(request.url).searchParams.get("api_key");
    if (apiKey !== env.WORKER_API_KEY) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    try {
      let token = await getAccessToken(env);

      let recoveryData, sleepData, cycleData;
      try {
        [recoveryData, sleepData, cycleData] = await fetchWhoopData(token);
      } catch (err) {
        // Cached access token may have been revoked/expired early — refresh once and retry
        if (err.status !== 401) throw err;
        token = await refreshAccessToken(env);
        [recoveryData, sleepData, cycleData] = await fetchWhoopData(token);
      }

      const rec   = recoveryData?.records?.[0] ?? null;
      const cycle = cycleData?.records?.[0]    ?? null;
      // Skip naps — show last night's main sleep
      const sleeps = sleepData?.records ?? [];
      const sleep  = sleeps.find(s => s.nap === false) ?? sleeps[0] ?? null;

      const recScore = rec?.score?.recovery_score != null ? Math.round(rec.score.recovery_score) : null;
      const stages   = sleep?.score?.stage_summary ?? null;
      // Time actually asleep = time in bed minus awake time
      const asleepMs = stages?.total_in_bed_time_milli != null
        ? stages.total_in_bed_time_milli - (stages.total_awake_time_milli ?? 0)
        : null;

      const payload = {
        recovery_score:        recScore,
        recovery_color:        recScore != null ? recoveryColor(recScore) : "unknown",
        hrv_rmssd_milli:       rec?.score?.hrv_rmssd_milli != null ? Math.round(rec.score.hrv_rmssd_milli) : null,
        resting_heart_rate:    rec?.score?.resting_heart_rate ?? null,
        spo2_percentage:       rec?.score?.spo2_percentage != null ? rec.score.spo2_percentage.toFixed(1) : null,
        skin_temp_celsius:     rec?.score?.skin_temp_celsius != null ? rec.score.skin_temp_celsius.toFixed(1) : null,
        skin_temp_fahrenheit:  rec?.score?.skin_temp_celsius != null ? ((rec.score.skin_temp_celsius * 9/5) + 32).toFixed(1) : null,
        sleep_performance_pct: sleep?.score?.sleep_performance_percentage != null ? Math.round(sleep.score.sleep_performance_percentage) : null,
        sleep_duration:        fmtDuration(asleepMs),
        sleep_time_in_bed:     fmtDuration(stages?.total_in_bed_time_milli),
        sleep_deep_duration:   fmtDuration(stages?.total_slow_wave_sleep_time_milli),
        sleep_rem_duration:    fmtDuration(stages?.total_rem_sleep_time_milli),
        sleep_efficiency_pct:  sleep?.score?.sleep_efficiency_percentage != null ? Math.round(sleep.score.sleep_efficiency_percentage) : null,
        respiratory_rate:      sleep?.score?.respiratory_rate != null ? sleep.score.respiratory_rate.toFixed(1) : null,
        day_strain:            cycle?.score?.strain != null ? cycle.score.strain.toFixed(1) : null,
        avg_heart_rate:        cycle?.score?.average_heart_rate ?? null,
        kilojoules:            cycle?.score?.kilojoule != null ? Math.round(cycle.score.kilojoule) : null,
        calories:              cycle?.score?.kilojoule != null ? Math.round(cycle.score.kilojoule / 4.184) : null,
        score_state:           rec?.score_state ?? "UNKNOWN",
        last_updated:          new Date().toISOString(),
      };

      return new Response(JSON.stringify(payload), {
        headers: {
          "Content-Type":                "application/json",
          "Cache-Control":               "no-store",
          "Access-Control-Allow-Origin": "*",
        },
      });

    } catch (err) {
      // Non-200 responses make TRMNL keep showing the last good screen
      return new Response(JSON.stringify({ error: err.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }
  },
};
