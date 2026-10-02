import { createRemoteJWKSet, jwtVerify } from "jose";

const keySets = new Map();

export function localRequest(request, env) {
  return env.LOCAL_DEV === "true" && ["127.0.0.1", "localhost", "[::1]"].includes(new URL(request.url).hostname);
}

export async function authorize(request, env) {
  if (localRequest(request, env)) return true;
  const team = env.ACCESS_TEAM_DOMAIN || "";
  const audience = env.ACCESS_AUD || "";
  const token = request.headers.get("Cf-Access-Jwt-Assertion");
  if (!/^[a-z0-9-]+\.cloudflareaccess\.com$/.test(team) || !audience || !token) return false;
  if (!keySets.has(team)) {
    keySets.set(team, createRemoteJWKSet(new URL(`https://${team}/cdn-cgi/access/certs`), { timeoutDuration: 5000 }));
  }
  try {
    const { payload } = await jwtVerify(token, keySets.get(team), {
      issuer: `https://${team}`, audience, algorithms: ["RS256"], requiredClaims: ["exp", "sub"],
    });
    return typeof payload.email === "string" && payload.email.length > 0;
  } catch {
    return false;
  }
}
