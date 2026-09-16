const test = require('node:test');
const assert = require('node:assert/strict');

const handler = require('./api/report.js');
const {
  sanitizeBundle,
  issueBody,
  sanitizeExitCode,
  sanitizeObservedMs,
  sanitizeRuntimeLocation,
  sanitizeSha256,
  sanitizeWerSignal
} = handler._test;

function baseBundle(overrides = {}) {
  return {
    schema: 1,
    launcher_version: '1.16.3',
    error_code: 'A8P-GAMEPROC-001',
    fingerprint: 'A8P-FP-123456789ABC',
    timestamp: '2026-09-15T20:16:42.6562438Z',
    windows: 'Windows 11 Pro | 25H2 | build 26200.9457',
    aotr_version: 'unknown',
    language: 'es-MX',
    files: [],
    repair_plan: { source_error_code: 'A8P-GAMEPROC-001', actions: ['retry_launch'] },
    repair_attempts: [],
    last_retry: null,
    last_error: 'game.dat exited during initialization.',
    log_files: ['launcher_current.log'],
    ...overrides
  };
}

test('schema 1 reports remain backward compatible', () => {
  const clean = sanitizeBundle(baseBundle());
  assert.equal(clean.schema, 1);
  assert.equal(clean.error_code, 'A8P-GAMEPROC-001');
  assert.equal(clean.process_exit_code, null);
  assert.equal(clean.observed_ms, null);
  assert.equal(clean.runtime_location, null);
  assert.equal(clean.runtime_sha256, null);
  assert.equal(clean.wer_signal, null);

  const body = issueBody(clean, clean.last_error);
  assert.doesNotMatch(body, /### Early-exit diagnostics/);
});

test('schema 2 preserves valid structured early-exit diagnostics', () => {
  const runtimeSha = 'cc08275d60ff8e3bfd4374c29d61304dea8336e6dd00ab8add88b1df95a705dc';
  const clean = sanitizeBundle(baseBundle({
    schema: 2,
    launcher_version: '1.16.4',
    process_exit_code: '0xc0000005/-1073741819',
    observed_ms: 2134,
    runtime_location: 'localappdata',
    runtime_sha256: runtimeSha,
    wer_signal: 'Application Error/1000/exception=c0000005/module=game.dat'
  }));

  assert.equal(clean.schema, 2);
  assert.equal(clean.process_exit_code, '0xC0000005/-1073741819');
  assert.equal(clean.observed_ms, 2134);
  assert.equal(clean.runtime_location, 'LOCALAPPDATA');
  assert.equal(clean.runtime_sha256, runtimeSha.toUpperCase());
  assert.equal(clean.wer_signal, 'Application Error/1000/exception=c0000005/module=game.dat');

  const body = issueBody(clean, clean.last_error);
  assert.match(body, /### Early-exit diagnostics/);
  assert.match(body, /process_exit_code: 0XC0000005\/-1073741819/);
  assert.match(body, /observed_ms: 2134/);
  assert.match(body, /runtime_location: LOCALAPPDATA/);
  assert.match(body, /runtime_sha256: CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC/);
  assert.match(body, /wer_signal: Application Error\/1000\/exception=c0000005\/module=game.dat/);
});

test('invalid diagnostic values are rejected without rejecting the report', () => {
  const clean = sanitizeBundle(baseBundle({
    schema: 2,
    process_exit_code: 'C:\\Users\\Alice\\secret.txt',
    observed_ms: -1,
    runtime_location: 'C:\\Users\\Alice',
    runtime_sha256: 'not-a-hash',
    wer_signal: 'none'
  }));

  assert.equal(clean.schema, 2);
  assert.equal(clean.process_exit_code, null);
  assert.equal(clean.observed_ms, null);
  assert.equal(clean.runtime_location, null);
  assert.equal(clean.runtime_sha256, null);
  assert.equal(clean.wer_signal, null);
});

test('WER sanitizer strips path-looking data and collapses whitespace', () => {
  const value = sanitizeWerSignal('Application Error/1000 module=C:\\Users\\Alice\\secret.dll\\n next');
  assert.ok(value);
  assert.doesNotMatch(value, /Alice|C:\\/i);
  assert.match(value, /\[redacted-path\]/);
  assert.doesNotMatch(value, /[\r\n\t]/);
});

test('diagnostic scalar sanitizers enforce bounded public schema', () => {
  assert.equal(sanitizeExitCode('unavailable'), 'unavailable');
  assert.equal(sanitizeExitCode('0xC0000005/-1073741819'), '0xC0000005/-1073741819');
  assert.equal(sanitizeExitCode('-1'), '-1');
  assert.equal(sanitizeExitCode('abc'), null);

  assert.equal(sanitizeObservedMs(0), 0);
  assert.equal(sanitizeObservedMs(600000), 600000);
  assert.equal(sanitizeObservedMs(600001), null);
  assert.equal(sanitizeObservedMs(1.5), null);

  assert.equal(sanitizeRuntimeLocation('non_localappdata'), 'NON_LOCALAPPDATA');
  assert.equal(sanitizeRuntimeLocation('D:\\Games'), null);

  const sha = 'A'.repeat(64);
  assert.equal(sanitizeSha256(sha), sha);
  assert.equal(sanitizeSha256('A'.repeat(63)), null);
});

test('unknown input fields do not pass through sanitizer', () => {
  const clean = sanitizeBundle(baseBundle({
    schema: 2,
    username: 'should-not-survive',
    machine_name: 'should-not-survive',
    full_path: 'C:\\Users\\Alice\\Game'
  }));

  assert.equal(Object.prototype.hasOwnProperty.call(clean, 'username'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(clean, 'machine_name'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(clean, 'full_path'), false);
});
