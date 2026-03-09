/**
 * Cloudflare Worker: WHOOP → TRMNL Data Proxy
 */

const WHOOP_BASE = "https://api.prod.whoop.com/developer";
const TOKEN_URL  = "https://api.prod.whoop.com/oauth/oauth2/token";

async function refreshAccessToken(env) {
  // Use KV refresh token if available (it rotates), otherwise fall back to secret
  let refreshToken = env.WHOOP_REFRESH_TOKEN.trim();
  if (env.WHOOP_KV) {
    const kvToken = await env.WHOOP_KV.get("refresh_token");
    if (kvToken) refreshToken = kvToken;
  }

  const body = new URLSearchParams({
    grant_type:    "refresh_token",
    refresh_token: refreshToken,
    client_id:     env.WHOOP_CLIENT_ID.trim(),
    client_secret: env.WHOOP_CLIENT_SECRET.trim(),
  });

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  const text = await res.text();
  if (!res.ok) throw new Error(`Token refresh failed (${res.status}): ${text}`);

  const data = JSON.parse(text);

  // Persist both tokens so refresh token rotation works
  if (env.WHOOP_KV) {
    await env.WHOOP_KV.put("access_token",  data.access_token,  { expirationTtl: (data.expires_in ?? 3600) - 60 });
    await env.WHOOP_KV.put("refresh_token", data.refresh_token);
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
  if (!res.ok) throw new Error(`WHOOP ${path} → ${res.status}: ${await res.text()}`);
  return res.json();
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
      const token = await getAccessToken(env);

      const [recoveryData, sleepData, cycleData] = await Promise.all([
        whoopGet("/v2/recovery?limit=1", token),
        whoopGet("/v2/sleep?limit=1", token),
        whoopGet("/v2/cycle?limit=1", token),
      ]);

      const rec   = recoveryData?.records?.[0] ?? null;
      const sleep = sleepData?.records?.[0]    ?? null;
      const cycle = cycleData?.records?.[0]    ?? null;

      const recScore = rec?.score?.recovery_score != null ? Math.round(rec.score.recovery_score) : null;

      const payload = {
        recovery_score:        recScore,
        recovery_color:        recScore != null ? recoveryColor(recScore) : "unknown",
        hrv_rmssd_milli:       rec?.score?.hrv_rmssd_milli != null ? Math.round(rec.score.hrv_rmssd_milli) : null,
        resting_heart_rate:    rec?.score?.resting_heart_rate ?? null,
        spo2_percentage:       rec?.score?.spo2_percentage != null ? rec.score.spo2_percentage.toFixed(1) : null,
        skin_temp_fahrenheit:  rec?.score?.skin_temp_celsius != null ? ((rec.score.skin_temp_celsius * 9/5) + 32).toFixed(1) : null,
        sleep_performance_pct: sleep?.score?.sleep_performance_percentage != null ? Math.round(sleep.score.sleep_performance_percentage) : null,
        sleep_duration:        fmtDuration(sleep?.score?.stage_summary?.total_in_bed_time_milli),
        sleep_deep_duration:   fmtDuration(sleep?.score?.stage_summary?.total_slow_wave_sleep_time_milli),
        sleep_rem_duration:    fmtDuration(sleep?.score?.stage_summary?.total_rem_sleep_time_milli),
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
      return new Response(JSON.stringify({ error: err.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }
  },
};