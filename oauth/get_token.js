#!/usr/bin/env node
const https    = require("https");
const readline = require("readline");
const crypto   = require("crypto");

const CLIENT_ID      = process.env.WHOOP_CLIENT_ID;
const CLIENT_SECRET  = process.env.WHOOP_CLIENT_SECRET;
const REDIRECT_URI   = "http://localhost:3000/callback";
const SCOPES         = "offline read:recovery read:cycles read:sleep read:profile read:body_measurement";
const AUTH_URL       = "https://api.prod.whoop.com/oauth/oauth2/auth";
const TOKEN_URL_HOST = "api.prod.whoop.com";
const TOKEN_URL_PATH = "/oauth/oauth2/token";

if (!CLIENT_ID || !CLIENT_SECRET) {
  console.error("Error: set WHOOP_CLIENT_ID and WHOOP_CLIENT_SECRET env vars first.");
  process.exit(1);
}

const state = crypto.randomBytes(16).toString("hex");

const authLink =
  `${AUTH_URL}?client_id=${CLIENT_ID}` +
  `&redirect_uri=${encodeURIComponent(REDIRECT_URI)}` +
  `&response_type=code` +
  `&scope=${encodeURIComponent(SCOPES)}` +
  `&state=${state}`;

console.log("\n──────────────────────────────────────────────────");
console.log("1. Open this URL in your browser:");
console.log("\n" + authLink + "\n");
console.log("2. Authorize the app.");
console.log("3. You'll be redirected to a page that can't load (localhost:3000).");
console.log("   That's fine — copy the FULL URL from your browser address bar.");
console.log("──────────────────────────────────────────────────\n");

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

rl.question("Paste the full redirect URL here: ", (redirectUrl) => {
  rl.close();

  let code;
  try {
    const parsed = new URL(redirectUrl.trim());
    code = parsed.searchParams.get("code");
  } catch (e) {
    console.error("Couldn't parse that URL:", e.message);
    process.exit(1);
  }

  if (!code) {
    console.error("No 'code' parameter found in that URL. Make sure you copied the full address bar URL.");
    process.exit(1);
  }

  console.log("\nGot auth code, exchanging for tokens...");

  const body = new URLSearchParams({
    grant_type:    "authorization_code",
    code,
    redirect_uri:  REDIRECT_URI,
    client_id:     CLIENT_ID,
    client_secret: CLIENT_SECRET,
  }).toString();

  const options = {
    hostname: TOKEN_URL_HOST,
    path:     TOKEN_URL_PATH,
    method:   "POST",
    headers:  {
      "Content-Type":   "application/x-www-form-urlencoded",
      "Content-Length": Buffer.byteLength(body),
    },
  };

  const req = https.request(options, (res) => {
    let data = "";
    res.on("data", d => data += d);
    res.on("end", () => {
      let json;
      try { json = JSON.parse(data); } catch (e) {
        console.error("Bad response from WHOOP:", data);
        process.exit(1);
      }

      if (json.error) {
        console.error("WHOOP error:", json.error, json.error_description || "");
        process.exit(1);
      }

      console.log("\n✅ SUCCESS! Run these Wrangler commands to store your secrets:\n");
      console.log(`wrangler secret put WHOOP_REFRESH_TOKEN`);
      console.log(`  → value: ${json.refresh_token}\n`);
      console.log(`wrangler secret put WHOOP_CLIENT_ID`);
      console.log(`  → value: ${CLIENT_ID}\n`);
      console.log(`wrangler secret put WHOOP_CLIENT_SECRET`);
      console.log(`  → value: ${CLIENT_SECRET}\n`);
    });
  });

  req.on("error", e => { console.error("Request error:", e.message); process.exit(1); });
  req.write(body);
  req.end();
});