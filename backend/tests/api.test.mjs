import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const port = 18787 + Math.floor(Math.random() * 500);
const temp = await mkdtemp(join(tmpdir(), 'carbonloop-'));
const child = spawn(process.execPath, ['src/server.mjs'], {
  cwd: new URL('..', import.meta.url),
  env: { ...process.env, PORT: String(port), CARBON_STORE_PATH: join(temp, 'store.json') },
  stdio: 'ignore'
});

async function waitForServer() {
  for (let i = 0; i < 30; i += 1) {
    try { if ((await fetch(`http://127.0.0.1:${port}/health`)).ok) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('backend did not start');
}

before(async () => {
  await waitForServer();
});

after(async () => {
  child.kill();
  await rm(temp, { recursive: true, force: true });
});

test('health and factor catalog', async () => {
  const health = await (await fetch(`http://127.0.0.1:${port}/health`)).json();
  assert.equal(health.ok, true);
  const factors = await (await fetch(`http://127.0.0.1:${port}/api/v1/factors`)).json();
  assert.equal(factors.factors.length, 5);
});

test('server computes and deduplicates records', async () => {
  const login = await (await fetch(`http://127.0.0.1:${port}/api/v1/auth/guest`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceId: 'test-device' })
  })).json();
  const headers = { authorization: `Bearer ${login.token}`, 'content-type': 'application/json' };
  const first = await (await fetch(`http://127.0.0.1:${port}/api/v1/records`, {
    method: 'POST', headers,
    body: JSON.stringify({ clientRecordId: 'one', factorId: 'walk', amount: 3 })
  })).json();
  const second = await (await fetch(`http://127.0.0.1:${port}/api/v1/records`, {
    method: 'POST', headers,
    body: JSON.stringify({ clientRecordId: 'one', factorId: 'walk', amount: 3 })
  })).json();
  assert.equal(first.record.reductionKg, 0.6);
  assert.equal(first.record.points, 6);
  assert.equal(second.duplicate, true);
  const dashboard = await (await fetch(`http://127.0.0.1:${port}/api/v1/dashboard`, { headers })).json();
  assert.equal(dashboard.summary.recordCount, 1);
});
