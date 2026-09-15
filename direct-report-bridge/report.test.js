const test = require('node:test');
const assert = require('node:assert/strict');

const { _test } = require('./api/report.js');

test('valid schema2 diagnostics become legacy-safe diagnostic block', () => {
  const sha = 'a'.repeat(64);
  const result = _test.diagnosticBlock({
    process_exit_code: '0xc0000005/-1073741819',
    observed_ms: 2134,
    runtime_location: 'localappdata',
    runtime_sha256: sha,
    wer_signal: 'Application Error/1000/exception=c0000005/module=game.dat',
  });

  assert.equal(result.diagnostics.process_exit_code, '0XC0000005/-1073741819');
  assert.equal(result.diagnostics.observed_ms, 2134);
  assert.equal(result.diagnostics.runtime_location, 'LOCALAPPDATA');
  assert.equal(result.diagnostics.runtime_sha256, sha.toUpperCase());
  assert.match(result.block, /\[A8P_SCHEMA2_EARLY_EXIT\]/);
  assert.match(result.block, /wer_signal=Application Error\/1000\/exception=c0000005\/module=game.dat/);
});

test('invalid diagnostic values are nulled and paths are redacted', () => {
  const result = _test.diagnosticBlock({
    process_exit_code: 'C:\\Users\\Alice\\x',
    observed_ms: -5,
    runtime_location: 'C:\\Users\\Alice',
    runtime_sha256: 'bad',
    wer_signal: 'Application Error module=C:\\Users\\Alice\\secret.dll',
  });

  assert.equal(result.diagnostics.process_exit_code, null);
  assert.equal(result.diagnostics.observed_ms, null);
  assert.equal(result.diagnostics.runtime_location, null);
  assert.equal(result.diagnostics.runtime_sha256, null);
  assert.ok(result.diagnostics.wer_signal);
  assert.doesNotMatch(result.diagnostics.wer_signal, /Alice|C:\\/i);
  assert.match(result.block, /\[redacted-path\]/);
});

test('legacy bundle preserves old fields and embeds diagnostics in last_error', () => {
  const result = _test.diagnosticBlock({ observed_ms: 900 });
  const bundle = _test.legacyBundle({
    schema: 2,
    launcher_version: '1.16.4',
    error_code: 'A8P-GAMEPROC-001',
    fingerprint: 'A8P-FP-ABCDEF012345',
    last_error: 'game.dat exited during initialization.',
    log_files: ['launcher_current.log'],
  }, result.block);

  assert.equal(bundle.schema, 1);
  assert.equal(bundle.launcher_version, '1.16.4');
  assert.match(bundle.last_error, /observed_ms=900/);
  assert.deepEqual(bundle.log_files, ['launcher_current.log']);
  assert.equal(Object.hasOwn(bundle, 'process_exit_code'), false);
});
