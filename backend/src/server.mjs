import { createServer } from 'node:http';
import { randomUUID, createHmac, timingSafeEqual } from 'node:crypto';
import { loadFactors } from './factors.mjs';
import { readStore, writeStore } from './store.mjs';

const PORT = Number(process.env.PORT ?? 8787);
const HOST = process.env.HOST ?? '0.0.0.0';
const TOKEN_SECRET = process.env.CARBON_TOKEN_SECRET ?? 'carbonloop-local-secret-change-me';
const API_PREFIX = '/api/v1';

const factorList = await loadFactors();
const factorMap = new Map(factorList.map((factor) => [factor.id, factor]));
let store = await readStore();
let writeQueue = Promise.resolve();

function persist() {
  writeQueue = writeQueue.then(() => writeStore(store));
  return writeQueue;
}

function json(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Client-Id',
    'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS'
  });
  res.end(payload);
}

function error(res, status, message, code = 'BAD_REQUEST') {
  json(res, status, { ok: false, error: { code, message } });
}

async function body(req) {
  let text = '';
  for await (const chunk of req) text += chunk;
  if (!text) return {};
  try { return JSON.parse(text); } catch { throw new Error('请求体必须是 JSON'); }
}

function signToken(payload) {
  const encoded = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = createHmac('sha256', TOKEN_SECRET).update(encoded).digest('base64url');
  return `${encoded}.${signature}`;
}

function verifyToken(token) {
  if (!token || !token.includes('.')) return null;
  const [encoded, signature] = token.split('.');
  const expected = createHmac('sha256', TOKEN_SECRET).update(encoded).digest('base64url');
  if (signature.length !== expected.length || !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;
  try {
    const payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
    return payload.exp > Date.now() ? payload : null;
  } catch { return null; }
}

function currentUser(req) {
  const value = req.headers.authorization ?? '';
  const token = value.startsWith('Bearer ') ? value.slice(7) : '';
  const payload = verifyToken(token);
  return payload ? store.users.find((user) => user.id === payload.sub) ?? null : null;
}

function requireUser(req, res) {
  const user = currentUser(req);
  if (!user) error(res, 401, '请先建立用户身份', 'UNAUTHORIZED');
  return user;
}

function cleanUser(user) {
  return { id: user.id, nickname: user.nickname, campus: user.campus, createdAt: user.createdAt };
}

function userRecords(userId) {
  return store.records.filter((record) => record.userId === userId).sort((a, b) => b.occurredAt.localeCompare(a.occurredAt));
}

function challengeProgress(userId, challenge) {
  const records = userRecords(userId).filter((record) => challenge.factorIds.includes(record.factorId));
  return Math.min(challenge.target, records.reduce((sum, record) => sum + record.amount, 0));
}

function challengeView(userId, challenge) {
  const joined = store.challengeParticipants.some((item) => item.userId === userId && item.challengeId === challenge.id);
  const progress = challengeProgress(userId, challenge);
  return { ...challenge, joined, progress, completed: progress >= challenge.target };
}

async function handle(req, res) {
  if (req.method === 'OPTIONS') return json(res, 204, {});
  const url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`);
  const pathname = url.pathname;

  if (req.method === 'GET' && pathname === '/health') {
    return json(res, 200, { ok: true, service: 'carbonloop-backend', time: new Date().toISOString(), users: store.users.length, records: store.records.length });
  }
  if (!pathname.startsWith(API_PREFIX)) return error(res, 404, '接口不存在', 'NOT_FOUND');

  try {
    if (req.method === 'POST' && pathname === `${API_PREFIX}/auth/guest`) {
      const data = await body(req);
      const deviceId = typeof data.deviceId === 'string' && data.deviceId.trim() ? data.deviceId.trim().slice(0, 100) : null;
      if (!deviceId) return error(res, 400, 'deviceId 必填');
      let user = store.users.find((item) => item.deviceId === deviceId);
      if (!user) {
        user = { id: `user_${randomUUID()}`, deviceId, nickname: String(data.nickname ?? '校园用户').trim().slice(0, 30) || '校园用户', campus: String(data.campus ?? '未设置').trim().slice(0, 50), createdAt: new Date().toISOString() };
        store.users.push(user);
        await persist();
      }
      const token = signToken({ sub: user.id, exp: Date.now() + 1000 * 60 * 60 * 24 * 30 });
      return json(res, 200, { ok: true, token, user: cleanUser(user) });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/factors`) {
      return json(res, 200, { ok: true, factors: factorList });
    }

    const user = requireUser(req, res);
    if (!user) return;

    if (req.method === 'GET' && pathname === `${API_PREFIX}/dashboard`) {
      const records = userRecords(user.id);
      const totalReductionKg = records.reduce((sum, record) => sum + record.reductionKg, 0);
      const totalPoints = records.reduce((sum, record) => sum + record.points, 0);
      const challenges = store.challenges.map((challenge) => challengeView(user.id, challenge));
      return json(res, 200, { ok: true, user: cleanUser(user), summary: { totalReductionKg: Number(totalReductionKg.toFixed(2)), totalPoints, recordCount: records.length }, challenges, recentRecords: records.slice(0, 5) });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/records`) {
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
      return json(res, 200, { ok: true, records: userRecords(user.id).slice(0, limit) });
    }

    if (req.method === 'POST' && pathname === `${API_PREFIX}/records`) {
      const data = await body(req);
      const factorId = typeof data.factorId === 'string' ? data.factorId : '';
      const factor = factorMap.get(factorId);
      const amount = Number(data.amount);
      const clientRecordId = typeof data.clientRecordId === 'string' ? data.clientRecordId.slice(0, 100) : '';
      if (!factor) return error(res, 400, '无效的低碳行为类型');
      if (!Number.isFinite(amount) || amount <= 0 || amount > 100000) return error(res, 400, '数量必须大于 0 且不能过大');
      if (clientRecordId) {
        const old = store.records.find((record) => record.userId === user.id && record.clientRecordId === clientRecordId);
        if (old) return json(res, 200, { ok: true, record: old, duplicate: true });
      }
      const reductionKg = Number((amount * factor.reductionKgPerUnit).toFixed(4));
      const points = Math.max(1, Math.round(amount * factor.pointsPerUnit));
      const record = { id: `record_${randomUUID()}`, userId: user.id, clientRecordId, factorId, factorVersion: factor.version, amount, reductionKg, points, occurredAt: data.occurredAt && !Number.isNaN(Date.parse(data.occurredAt)) ? new Date(data.occurredAt).toISOString() : new Date().toISOString(), createdAt: new Date().toISOString() };
      store.records.push(record);
      store.pointsLedger.push({ id: `points_${randomUUID()}`, userId: user.id, recordId: record.id, points, reason: factor.label, createdAt: record.createdAt });
      await persist();
      return json(res, 201, { ok: true, record });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/challenges`) {
      return json(res, 200, { ok: true, challenges: store.challenges.map((challenge) => challengeView(user.id, challenge)) });
    }

    const challengeMatch = pathname.match(new RegExp(`^${API_PREFIX}/challenges/([^/]+)/join$`));
    if (req.method === 'POST' && challengeMatch) {
      const challengeId = challengeMatch[1];
      const challenge = store.challenges.find((item) => item.id === challengeId);
      if (!challenge) return error(res, 404, '挑战不存在', 'CHALLENGE_NOT_FOUND');
      if (!store.challengeParticipants.some((item) => item.userId === user.id && item.challengeId === challengeId)) {
        store.challengeParticipants.push({ userId: user.id, challengeId, joinedAt: new Date().toISOString() });
        await persist();
      }
      return json(res, 200, { ok: true, challenge: challengeView(user.id, challenge) });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/leaderboard`) {
      const totals = new Map();
      for (const record of store.records) {
        const item = totals.get(record.userId) ?? { points: 0, reductionKg: 0, records: 0 };
        item.points += record.points;
        item.reductionKg += record.reductionKg;
        item.records += 1;
        totals.set(record.userId, item);
      }
      const ranking = [...totals.entries()].map(([userId, value]) => ({ user: cleanUser(store.users.find((item) => item.id === userId)), points: value.points, reductionKg: Number(value.reductionKg.toFixed(2)), records: value.records })).sort((a, b) => b.points - a.points).slice(0, 50).map((item, index) => ({ rank: index + 1, ...item }));
      return json(res, 200, { ok: true, ranking, mine: ranking.find((item) => item.user.id === user.id) ?? null });
    }

    return error(res, 404, '接口不存在', 'NOT_FOUND');
  } catch (cause) {
    console.error(cause);
    return error(res, 500, '服务器内部错误', 'INTERNAL_ERROR');
  }
}

const server = createServer((req, res) => handle(req, res));
server.listen(PORT, HOST, () => console.log(`CarbonLoop backend listening on http://${HOST}:${PORT}`));
