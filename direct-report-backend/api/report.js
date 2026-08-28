const crypto = require('crypto');

const MAX_BODY_BYTES = 64 * 1024;
const MAX_ERROR_TEXT = 6000;
const REPO = 'eliaauditore/AotR-8P-WotR';
const ISSUE_API = `https://api.github.com/repos/${REPO}/issues`;

const buckets = new Map();
const RATE_KEY_SECRET = crypto.randomBytes(32);
const WINDOW_MS = 60 * 60 * 1000;
const MAX_PER_WINDOW = 5;

function send(res, status, body) {
  res.statusCode = status;
  res.setHeader('content-type', 'application/json; charset=utf-8');
  res.setHeader('cache-control', 'no-store');
  res.end(JSON.stringify(body));
}

function text(v, max = 500) {
  if (v === null || v === undefined) return '';
  return String(v).slice(0, max);
}

function requestAddress(req) {
  return text(req.headers['x-forwarded-for'], 256).split(',')[0].trim() || req.socket?.remoteAddress || 'unknown';
}

function rateKey(req) {
  // The hosting layer necessarily sees the request address, but the application
  // never retains that raw value in its in-memory limiter state. A random,
  // process-local HMAC key makes the stored bucket identifier non-reversible and
  // intentionally unstable across cold starts/redeployments.
  return crypto.createHmac('sha256', RATE_KEY_SECRET).update(requestAddress(req)).digest('hex');
}

function limited(key) {
  const now = Date.now();
  const active = (buckets.get(key) || []).filter(t => now - t < WINDOW_MS);
  if (active.length >= MAX_PER_WINDOW) {
    buckets.set(key, active);
    return true;
  }
  active.push(now);
  buckets.set(key, active);
  return false;
}

function validCode(v) {
  return /^A8P-[A-Z0-9-]{3,64}$/.test(text(v, 80));
}

function validFingerprint(v) {
  return /^A8P-FP-[A-F0-9]{12}$/.test(text(v, 32));
}

function validHash(v) {
  const s = text(v, 64);
  return /^[A-Fa-f0-9]{64}$/.test(s) ? s.toUpperCase() : null;
}

function sanitizeBundle(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('invalid_bundle');

  const bundle = {
    schema: Number(input.schema) || 1,
    launcher_version: text(input.launcher_version, 64),
    error_code: text(input.error_code, 80),
    fingerprint: text(input.fingerprint, 32),
    timestamp: text(input.timestamp, 80),
    windows: text(input.windows, 160),
    aotr_version: text(input.aotr_version, 64),
    language: text(input.language, 32),
    files: Array.isArray(input.files) ? input.files.slice(0, 16).map(f => ({
      path: text(f?.path, 160),
      role: text(f?.role, 32),
      exists: !!f?.exists,
      size: Number.isFinite(Number(f?.size)) ? Number(f.size) : null,
      expected_sha256: validHash(f?.expected_sha256),
      actual_sha256: validHash(f?.actual_sha256)
    })) : [],
    repair_plan: input.repair_plan && typeof input.repair_plan === 'object' ? {
      source_error_code: text(input.repair_plan.source_error_code, 80),
      actions: Array.isArray(input.repair_plan.actions) ? input.repair_plan.actions.slice(0, 16).map(x => text(x, 64)) : []
    } : null,
    repair_attempts: Array.isArray(input.repair_attempts) ? input.repair_attempts.slice(0, 32).map(a => ({
      timestamp: text(a?.timestamp, 80),
      action: text(a?.action, 64),
      result: text(a?.result, 32),
      detail: text(a?.detail, 1000)
    })) : [],
    last_retry: text(input.last_retry, 80) || null,
    last_error: text(input.last_error, MAX_ERROR_TEXT),
    log_files: Array.isArray(input.log_files) ? input.log_files.slice(0, 16).map(x => text(x, 100)) : [],
    notes: 'Submitted through the accountless AotR 8P WotR direct-report endpoint. No GitHub account is required.'
  };

  if (!validCode(bundle.error_code)) throw new Error('invalid_error_code');
  if (!validFingerprint(bundle.fingerprint)) throw new Error('invalid_fingerprint');
  return bundle;
}

function issueBody(bundle, exactError) {
  const attempts = bundle.repair_attempts.length
    ? bundle.repair_attempts.map(a => `${a.action || 'unknown'}: ${a.result || 'unknown'}${a.detail ? ' — ' + a.detail : ''}`).join('\n')
    : 'none recorded';
  const hashes = bundle.files.length
    ? bundle.files.map(f => `${f.path || f.role}: expected=${f.expected_sha256 || 'n/a'} actual=${f.actual_sha256 || (f.exists ? 'unknown' : 'missing')}`).join('\n')
    : 'none recorded';

  return `<!-- a8p-direct-report -->\n### Launcher version\n\n${bundle.launcher_version || 'unknown'}\n\n### AotR version\n\n${bundle.aotr_version || 'unknown'}\n\n### Windows version\n\n${bundle.windows || 'unknown'}\n\n### Language\n\n${bundle.language || 'unknown'}\n\n### A8P Error Code\n\n${bundle.error_code}\n\n### Support Fingerprint\n\n${bundle.fingerprint}\n\n### Exact error\n\n${exactError || bundle.last_error || 'unknown'}\n\n### Repair plan\n\n${bundle.repair_plan?.actions?.join('\n') || 'none'}\n\n### Repair attempts\n\n${attempts}\n\n### Expected / actual hashes\n\n${hashes}\n\n### Support bundle\n\n\`\`\`json\n${JSON.stringify(bundle)}\n\`\`\`\n`;
}

module.exports = async function handler(req, res) {
  if (req.method === 'GET') return send(res, 200, { ok: true, service: 'a8p-direct-report', schema: 1 });
  if (req.method !== 'POST') return send(res, 405, { ok: false, error: 'method_not_allowed' });

  const declared = Number(req.headers['content-length'] || 0);
  if (declared > MAX_BODY_BYTES) return send(res, 413, { ok: false, error: 'payload_too_large' });
  if (limited(rateKey(req))) return send(res, 429, { ok: false, error: 'rate_limited' });

  let body = req.body;
  if (typeof body === 'string') {
    if (Buffer.byteLength(body, 'utf8') > MAX_BODY_BYTES) return send(res, 413, { ok: false, error: 'payload_too_large' });
    try { body = JSON.parse(body); } catch { return send(res, 400, { ok: false, error: 'invalid_json' }); }
  }
  if (!body || typeof body !== 'object') return send(res, 400, { ok: false, error: 'invalid_json' });

  let bundle;
  try { bundle = sanitizeBundle(body.support_bundle || body); }
  catch (e) { return send(res, 400, { ok: false, error: e.message || 'invalid_bundle' }); }

  const token = process.env.GITHUB_REPORT_TOKEN;
  if (!token) return send(res, 503, { ok: false, error: 'report_service_not_configured' });

  const exactError = text(body.exact_error || bundle.last_error, MAX_ERROR_TEXT);
  const short = text(body.title, 120) || exactError.split(/\r?\n/)[0].slice(0, 90) || 'Launcher failure';

  const gh = await fetch(ISSUE_API, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      accept: 'application/vnd.github+json',
      'content-type': 'application/json',
      'user-agent': 'AotR-8P-WotR-Direct-Report/1'
    },
    body: JSON.stringify({
      title: `[Launcher Report] ${bundle.error_code} - ${short}`,
      body: issueBody(bundle, exactError),
      labels: ['bug', 'launcher', 'launcher-report', 'needs-triage']
    })
  });

  const raw = await gh.text();
  let data = null;
  try { data = JSON.parse(raw); } catch {}
  if (!gh.ok) {
    console.error('github_issue_create_failed', gh.status, raw.slice(0, 1000));
    return send(res, 502, { ok: false, error: 'github_issue_create_failed' });
  }

  return send(res, 201, {
    ok: true,
    issue_number: data.number,
    issue_url: data.html_url,
    fingerprint: bundle.fingerprint
  });
};
