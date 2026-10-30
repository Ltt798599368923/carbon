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
  assert.equal(factors.factors.length, 7);
  assert.equal(factors.factors.find((factor) => factor.id === 'water').calculationStatus, 'behavior_only');
  const overview = await (await fetch(`http://127.0.0.1:${port}/api/v1/campus/overview`)).json();
  assert.equal(overview.locations.length, 5);
  assert.equal(overview.summary.activeLocationCount, 5);
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

test('challenge progress is date-bounded and join is idempotent', async () => {
  const login = await (await fetch(`http://127.0.0.1:${port}/api/v1/auth/guest`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceId: 'challenge-device' })
  })).json();
  const headers = { authorization: `Bearer ${login.token}`, 'content-type': 'application/json' };
  const before = await (await fetch(`http://127.0.0.1:${port}/api/v1/challenges`, { headers })).json();
  assert.equal(before.challenges[0].progress, 0);
  assert.equal(before.challenges[0].active, true);
  const joinUrl = `http://127.0.0.1:${port}/api/v1/challenges/${before.challenges[0].id}/join`;
  const firstJoin = await (await fetch(joinUrl, { method: 'POST', headers })).json();
  const secondJoin = await (await fetch(joinUrl, { method: 'POST', headers })).json();
  assert.equal(firstJoin.challenge.joined, true);
  assert.equal(secondJoin.challenge.joined, true);
  await fetch(`http://127.0.0.1:${port}/api/v1/records`, {
    method: 'POST', headers,
    body: JSON.stringify({ clientRecordId: 'challenge-record', factorId: 'walk', amount: 3, occurredAt: '2020-01-01T00:00:00.000Z' })
  });
  const after = await (await fetch(`http://127.0.0.1:${port}/api/v1/challenges`, { headers })).json();
  assert.equal(after.challenges[0].progress, 0);
});

test('malformed JSON is rejected as a client error', async () => {
  const response = await fetch(`http://127.0.0.1:${port}/api/v1/auth/guest`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: '{not-json'
  });
  const payload = await response.json();
  assert.equal(response.status, 400);
  assert.equal(payload.error.code, 'BAD_REQUEST');
});

test('location action updates campus and team aggregates', async () => {
  const login = await (await fetch(`http://127.0.0.1:${port}/api/v1/auth/guest`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceId: 'location-device' })
  })).json();
  const headers = { authorization: `Bearer ${login.token}`, 'content-type': 'application/json' };
  const response = await (await fetch(`http://127.0.0.1:${port}/api/v1/actions`, {
    method: 'POST', headers,
    body: JSON.stringify({ clientActionId: 'location-action-1', factorId: 'recycle', amount: 2, locationId: 'location-recycle-east' })
  })).json();
  assert.equal(response.action.verificationStatus, 'location_verified');
  const overview = await (await fetch(`http://127.0.0.1:${port}/api/v1/campus/overview`)).json();
  const location = overview.locations.find((item) => item.id === 'location-recycle-east');
  assert.equal(location.actionCount, 1);
  assert.equal(overview.summary.actionCount, 3);
  const teams = await (await fetch(`http://127.0.0.1:${port}/api/v1/teams`, { headers })).json();
  assert.equal(teams.mine.name, '体验宿舍 302');
  assert.equal(teams.mine.actionCount, 3);
});

test('item cycle creates a passport card and only credits once', async () => {
  const login = await (await fetch(`http://127.0.0.1:${port}/api/v1/auth/guest`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceId: 'item-device' })
  })).json();
  const headers = { authorization: `Bearer ${login.token}`, 'content-type': 'application/json' };
  const created = await (await fetch(`http://127.0.0.1:${port}/api/v1/items`, {
    method: 'POST', headers,
    body: JSON.stringify({ clientItemId: 'item-1', title: '大一教材', itemType: '书籍', weightKg: 1.5, flow: 'exchange', locationId: 'location-exchange-library' })
  })).json();
  assert.equal(created.item.status, '等待交换');
  assert.equal(created.item.cycleCount, 1);
  assert.equal(created.item.reductionKg, 0.675);
  const duplicate = await (await fetch(`http://127.0.0.1:${port}/api/v1/items`, {
    method: 'POST', headers,
    body: JSON.stringify({ clientItemId: 'item-1', title: '大一教材', itemType: '书籍', weightKg: 1.5, flow: 'exchange' })
  })).json();
  assert.equal(duplicate.duplicate, true);
  const updated = await (await fetch(`${`http://127.0.0.1:${port}`}/api/v1/items/${created.item.id}/cycle-events`, {
    method: 'POST', headers,
    body: JSON.stringify({ type: 'donate', note: '捐给新生' })
  })).json();
  assert.equal(updated.item.status, '已捐赠');
  assert.equal(updated.item.cycleCount, 2);
  const items = await (await fetch(`http://127.0.0.1:${port}/api/v1/items`, { headers })).json();
  assert.equal(items.items.length, 1);
  const dashboard = await (await fetch(`http://127.0.0.1:${port}/api/v1/dashboard`, { headers })).json();
  assert.equal(dashboard.summary.totalPoints, 6);
  assert.equal(dashboard.recentItems[0].cycleCount, 2);
});

test('behavior-only records, tasks, ledger and record reversal stay consistent', async () => {
  const login = await (await fetch(`http://127.0.0.1:${port}/api/v1/auth/guest`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceId: 'p0-record-device' })
  })).json();
  const headers = { authorization: `Bearer ${login.token}`, 'content-type': 'application/json' };
  const saved = await (await fetch(`http://127.0.0.1:${port}/api/v1/records`, {
    method: 'POST', headers,
    body: JSON.stringify({ clientRecordId: 'water-1', factorId: 'water', amount: 1, occurredAt: '2026-10-30T08:00:00.000Z' })
  })).json();
  assert.equal(saved.record.reductionKg, 0);
  assert.equal(saved.record.points, 1);
  const ledger = await (await fetch(`http://127.0.0.1:${port}/api/v1/points-ledger`, { headers })).json();
  assert.equal(ledger.totalPoints, 1);
  const updated = await (await fetch(`http://127.0.0.1:${port}/api/v1/records/${saved.record.id}`, {
    method: 'PATCH', headers,
    body: JSON.stringify({ factorId: 'reusable', amount: 1, occurredAt: '2026-10-30T08:00:00.000Z' })
  })).json();
  assert.equal(updated.record.reductionKg, 0.06);
  const afterTask = await (await fetch(`http://127.0.0.1:${port}/api/v1/tasks`, { headers })).json();
  assert.equal(afterTask.tasks[0].completed, true);
  const afterDelete = await (await fetch(`http://127.0.0.1:${port}/api/v1/records/${saved.record.id}`, { method: 'DELETE', headers })).json();
  assert.equal(afterDelete.deleted, true);
  const dashboard = await (await fetch(`http://127.0.0.1:${port}/api/v1/dashboard`, { headers })).json();
  assert.equal(dashboard.summary.recordCount, 0);
  assert.equal(dashboard.summary.totalPoints, 0);
});
