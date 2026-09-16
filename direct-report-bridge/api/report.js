const MAX_BODY_BYTES = 64 * 1024;
const MAX_ERROR_TEXT = 6000;
const LEGACY_UPSTREAM = 'https://a8p-direct-report.vercel.app/api/report';

function str(v, max = 1000) {
  if (v === null || v === undefined) return '';
  return String(v).slice(0, max);
}

function sanitizeExitCode(v) {
  const value = str(v, 64).trim();
  if (!value) return null;
  if (/^unavailable$/i.test(value)) return 'unavailable';
  if (/^0x[0-9A-Fa-f]{8}\/-?\d+$/.test(value)) {
    const parts = value.split('/');
    return parts[0].toUpperCase() + '/' + parts[1];
  }
  if (/^-?\d+$/.test(value)) return value;
  return null;
}

function sanitizeObservedMs(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  if (!Number.isSafeInteger(n) || n < 0 || n > 600000) return null;
  return n;
}

function sanitizeRuntimeLocation(v) {
  const value = str(v, 32).trim().toUpperCase();
  return ['LOCALAPPDATA', 'NON_LOCALAPPDATA', 'UNKNOWN'].includes(value) ? value : null;
}

function sanitizeSha256(v) {
  const value = str(v, 64);
  return /^[A-Fa-f0-9]{64}$/.test(value) ? value.toUpperCase() : null;
}

function sanitizeWerSignal(v) {
  let value = str(v, 320).replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (!value || /^none$/i.test(value)) return null;
  value = value.replace(/\b[A-Za-z]:\\[^;|\s]*/g, '[redacted-path]');
  value = value.replace(/\\\\[^\\\s;|]+\\[^;|\s]*/g, '[redacted-path]');
  return value.slice(0, 320);
}

function sanitizeText(v, max = MAX_ERROR_TEXT) {
  return str(v, max)
    .replace(/\b[A-Za-z]:\\Users\\[^\\\r\n]+/gi, '[redacted-user-path]')
    .replace(/\\\\[^\\\s]+\\Users\\[^\\\r\n]+/gi, '[redacted-user-path]')
    .slice(0, max);
}

function diagnosticBlock(bundle) {
  const d = {
    process_exit_code: sanitizeExitCode(bundle && bundle.process_exit_code),
    observed_ms: sanitizeObservedMs(bundle && bundle.observed_ms),
    runtime_location: sanitizeRuntimeLocation(bundle && bundle.runtime_location),
    runtime_sha256: sanitizeSha256(bundle && bundle.runtime_sha256),
    wer_signal: sanitizeWerSignal(bundle && bundle.wer_signal),
  };

  if (Object.values(d).every(v => v === null)) return { block: '', diagnostics: d };

  const block = [
    '',
    '[A8P_SCHEMA2_EARLY_EXIT]',
    'process_exit_code=' + (d.process_exit_code ?? 'n/a'),
    'observed_ms=' + (d.observed_ms ?? 'n/a'),
    'runtime_location=' + (d.runtime_location ?? 'n/a'),
    'runtime_sha256=' + (d.runtime_sha256 ?? 'n/a'),
    'wer_signal=' + (d.wer_signal ?? 'n/a'),
    '[/A8P_SCHEMA2_EARLY_EXIT]',
  ].join('\n');

  return { block, diagnostics: d };
}

function legacyBundle(input = {}, block = '') {
  const files = Array.isArray(input.files) ? input.files.slice(0, 32) : [];
  const attempts = Array.isArray(input.repair_attempts) ? input.repair_attempts.slice(0, 32) : [];
  const logFiles = Array.isArray(input.log_files) ? input.log_files.slice(0, 16).map(x => str(x, 100)) : [];

  const baseError = sanitizeText(input.last_error || '', MAX_ERROR_TEXT);
  const combinedError = sanitizeText((baseError + block).trim(), MAX_ERROR_TEXT);

  return {
    schema: 1,
    launcher_version: str(input.launcher_version, 40),
    error_code: str(input.error_code, 80),
    fingerprint: str(input.fingerprint, 80),
    timestamp: str(input.timestamp, 80),
    windows: str(input.windows, 300),
    aotr_version: str(input.aotr_version, 80),
    language: str(input.language, 40),
    files,
    repair_plan: input.repair_plan && typeof input.repair_plan === 'object' ? input.repair_plan : null,
    repair_attempts: attempts,
    last_retry: str(input.last_retry, 80) || null,
    last_error: combinedError,
    log_files: logFiles,
  };
}

async function readJson(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) {
      const err = new Error('payload too large');
      err.status = 413;
      throw err;
    }
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString('utf8');
  if (!raw) return {};
  return JSON.parse(raw);
}

function sendJson(res, status, body) {
  res.statusCode = status;
  res.setHeader('content-type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(body));
}

module.exports = async function handler(req, res) {
  if (req.method === 'GET') {
    return sendJson(res, 200, {
      ok: true,
      service: 'a8p-direct-report-v2-bridge',
      schema: 2,
      upstream: 'legacy-accountless-github-writer',
    });
  }

  if (req.method !== 'POST') {
    res.setHeader('allow', 'GET, POST');
    return sendJson(res, 405, { ok: false, error: 'method_not_allowed' });
  }

  try {
    const input = await readJson(req);
    const bundle = input && typeof input.bundle === 'object' ? input.bundle : {};
    const result = diagnosticBlock(bundle);

    const forwarded = {
      schema: 1,
      title: sanitizeText(input.title || '', 180),
      exact_error: sanitizeText(((input.exact_error || bundle.last_error || '') + result.block).trim(), MAX_ERROR_TEXT),
      support_bundle: legacyBundle(bundle, result.block),
    };

    const upstream = await fetch(LEGACY_UPSTREAM, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'user-agent': 'AotR-8P-WotR-schema2-bridge/1',
      },
      body: JSON.stringify(forwarded),
      signal: AbortSignal.timeout(15000),
    });

    const text = await upstream.text();
    let body = null;
    try { body = JSON.parse(text); } catch { body = { ok: false, error: 'invalid_upstream_response' }; }

    if (!upstream.ok) {
      return sendJson(res, upstream.status, {
        ok: false,
        error: body && body.error ? body.error : 'upstream_failed',
      });
    }

    return sendJson(res, upstream.status, Object.assign({}, body, {
      schema: 2,
      diagnostics_forwarded: Object.values(result.diagnostics).some(v => v !== null),
    }));
  } catch (err) {
    const status = Number(err && err.status) || 400;
    return sendJson(res, status, { ok: false, error: status === 413 ? 'payload_too_large' : 'invalid_request' });
  }
};

module.exports._test = {
  sanitizeExitCode,
  sanitizeObservedMs,
  sanitizeRuntimeLocation,
  sanitizeSha256,
  sanitizeWerSignal,
  diagnosticBlock,
  legacyBundle,
};
