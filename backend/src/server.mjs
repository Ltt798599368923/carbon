import { createServer } from 'node:http';
import { randomUUID, createHmac, timingSafeEqual } from 'node:crypto';
import { loadFactors } from './factors.mjs';
import { readStore, writeStore } from './store.mjs';

const PORT = Number(process.env.PORT ?? 8787);
const HOST = process.env.HOST ?? '0.0.0.0';
const TOKEN_SECRET = process.env.CARBON_TOKEN_SECRET ?? 'carbonloop-local-secret-change-me';
const ALLOWED_ORIGIN = process.env.CARBON_ALLOWED_ORIGIN ?? '*';
const MAX_BODY_BYTES = 1024 * 1024;
const API_PREFIX = '/api/v1';

class RequestError extends Error {
  constructor(message) {
    super(message);
    this.name = 'RequestError';
  }
}

if (process.env.NODE_ENV === 'production' && !process.env.CARBON_TOKEN_SECRET) {
  throw new Error('生产环境必须设置 CARBON_TOKEN_SECRET');
}

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
    'Access-Control-Allow-Origin': ALLOWED_ORIGIN,
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
  let size = 0;
  for await (const chunk of req) {
    size += Buffer.byteLength(chunk);
    if (size > MAX_BODY_BYTES) throw new RequestError('请求体过大');
    text += chunk;
  }
  if (!text) return {};
  try { return JSON.parse(text); } catch { throw new RequestError('请求体必须是 JSON'); }
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
  return { id: user.id, nickname: user.nickname, campus: user.campus, campusId: user.campusId ?? 'hafu-main', teamId: user.teamId ?? null, createdAt: user.createdAt };
}

function userRecords(userId) {
  return store.records.filter((record) => record.userId === userId).sort((a, b) => b.occurredAt.localeCompare(a.occurredAt));
}

function dateKey(value) {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? '' : parsed.toISOString().slice(0, 10);
}

function userPoints(userId) {
  return store.pointsLedger
    .filter((entry) => entry.userId === userId)
    .reduce((sum, entry) => sum + Number(entry.points || 0), 0);
}

function taskProgress(userId, task, day) {
  return userRecords(userId)
    .filter((record) => dateKey(record.occurredAt) === day && task.factorIds.includes(record.factorId))
    .reduce((sum, record) => sum + record.amount, 0);
}

function taskView(userId, task, day = dateKey(new Date())) {
  const progress = Math.min(task.target, taskProgress(userId, task, day));
  const completed = progress >= task.target;
  return { ...task, day, progress, completed };
}

function syncTaskRewardsForDate(userId, day) {
  if (!day) return;
  for (const task of store.tasks.filter((candidate) => candidate.active && candidate.period === 'daily')) {
    const progress = taskProgress(userId, task, day);
    const existing = store.pointsLedger.find((entry) => entry.userId === userId && entry.taskId === task.id && entry.taskDate === day);
    if (progress >= task.target && !existing) {
      store.taskCompletions.push({ id: `task_${randomUUID()}`, userId, taskId: task.id, taskDate: day, completedAt: new Date().toISOString() });
      store.pointsLedger.push({ id: `points_${randomUUID()}`, userId, taskId: task.id, taskDate: day, points: task.rewardPoints, reason: `任务：${task.name}`, createdAt: new Date().toISOString() });
    } else if (progress < task.target && existing) {
      store.pointsLedger = store.pointsLedger.filter((entry) => !(entry.userId === userId && entry.taskId === task.id && entry.taskDate === day));
      store.taskCompletions = store.taskCompletions.filter((entry) => !(entry.userId === userId && entry.taskId === task.id && entry.taskDate === day));
    }
  }
}

function challengeProgress(userId, challenge) {
  const start = Date.parse(challenge.startsAt);
  const end = Date.parse(challenge.endsAt);
  const records = userRecords(userId).filter((record) => {
    const occurredAt = Date.parse(record.occurredAt);
    const inWindow = Number.isNaN(start) || Number.isNaN(end) || (occurredAt >= start && occurredAt <= end);
    return inWindow && challenge.factorIds.includes(record.factorId);
  });
  return Math.min(challenge.target, records.reduce((sum, record) => sum + record.amount, 0));
}

function challengeView(userId, challenge) {
  const joined = store.challengeParticipants.some((item) => item.userId === userId && item.challengeId === challenge.id);
  const progress = challengeProgress(userId, challenge);
  const now = Date.now();
  const startsAt = Date.parse(challenge.startsAt);
  const endsAt = Date.parse(challenge.endsAt);
  const active = (Number.isNaN(startsAt) || now >= startsAt) && (Number.isNaN(endsAt) || now <= endsAt);
  return { ...challenge, joined, progress, active, completed: progress >= challenge.target };
}

function locationView(location) {
  const actionCount = store.records.filter((record) => record.locationId === location.id).length;
  return { ...location, actionCount };
}

function teamView(team) {
  const members = store.users.filter((user) => user.teamId === team.id);
  const memberIds = new Set(members.map((member) => member.id));
  const records = store.records.filter((record) => memberIds.has(record.userId));
  return {
    ...team,
    memberCount: members.length,
    actionCount: records.length,
    totalReductionKg: Number(records.reduce((sum, record) => sum + record.reductionKg, 0).toFixed(2)),
    totalPoints: store.pointsLedger
      .filter((entry) => memberIds.has(entry.userId))
      .reduce((sum, entry) => sum + Number(entry.points || 0), 0)
  };
}

function campusOverview() {
  const totalReductionKg = store.records.reduce((sum, record) => sum + record.reductionKg, 0);
  const participantIds = new Set(store.records.map((record) => record.userId));
  return {
    campus: store.campuses[0] ?? null,
    summary: {
      participantCount: participantIds.size,
      actionCount: store.records.length,
      totalReductionKg: Number(totalReductionKg.toFixed(2)),
      activeLocationCount: store.locations.filter((location) => location.status === 'open').length
    },
    locations: store.locations.map(locationView),
    teams: store.teams.map(teamView),
    updatedAt: new Date().toISOString()
  };
}

function itemCycleView(item) {
  return {
    ...item,
    events: [...(item.events ?? [])].sort((a, b) => b.createdAt.localeCompare(a.createdAt))
  };
}

const ITEM_FLOWS = new Set(['recycle', 'exchange', 'donate', 'repair']);
const ITEM_STATUSES = {
  recycle: '已进入回收流程',
  exchange: '等待交换',
  donate: '已捐赠',
  repair: '维修中'
};

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
        user = { id: `user_${randomUUID()}`, deviceId, nickname: String(data.nickname ?? '校园用户').trim().slice(0, 30) || '校园用户', campus: String(data.campus ?? '河南财经政法大学').trim().slice(0, 50), campusId: 'hafu-main', teamId: 'team-dorm-302', createdAt: new Date().toISOString() };
        store.users.push(user);
        await persist();
      } else if (!user.campusId || !user.teamId) {
        user.campusId = user.campusId ?? 'hafu-main';
        user.teamId = user.teamId ?? 'team-dorm-302';
        await persist();
      }
      const token = signToken({ sub: user.id, exp: Date.now() + 1000 * 60 * 60 * 24 * 30 });
      return json(res, 200, { ok: true, token, user: cleanUser(user) });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/factors`) {
      return json(res, 200, { ok: true, factors: factorList });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/campus/overview`) {
      return json(res, 200, { ok: true, ...campusOverview() });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/locations`) {
      const type = url.searchParams.get('type');
      const locations = store.locations.filter((location) => !type || location.type === type).map(locationView);
      return json(res, 200, { ok: true, locations });
    }

    const locationMatch = pathname.match(new RegExp(`^${API_PREFIX}/locations/([^/]+)$`));
    if (req.method === 'GET' && locationMatch) {
      const location = store.locations.find((item) => item.id === locationMatch[1]);
      if (!location) return error(res, 404, '点位不存在', 'LOCATION_NOT_FOUND');
      return json(res, 200, { ok: true, location: locationView(location) });
    }

    const user = requireUser(req, res);
    if (!user) return;

    if (req.method === 'GET' && pathname === `${API_PREFIX}/dashboard`) {
      const records = userRecords(user.id);
      const totalReductionKg = records.reduce((sum, record) => sum + record.reductionKg, 0);
      const totalPoints = userPoints(user.id);
      const challenges = store.challenges.map((challenge) => challengeView(user.id, challenge));
      const recentItems = store.itemCycles.filter((item) => item.userId === user.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 3).map(itemCycleView);
      const tasks = store.tasks.filter((task) => task.active).map((task) => taskView(user.id, task));
      const pointsLedger = store.pointsLedger.filter((entry) => entry.userId === user.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 50);
      return json(res, 200, { ok: true, user: cleanUser(user), summary: { totalReductionKg: Number(totalReductionKg.toFixed(2)), totalPoints, recordCount: records.length }, challenges, tasks, pointsLedger, recentRecords: records.slice(0, 5), recentItems });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/records`) {
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
      return json(res, 200, { ok: true, records: userRecords(user.id).slice(0, limit) });
    }

    const recordMatch = pathname.match(new RegExp(`^${API_PREFIX}/records/([^/]+)$`));
    if ((req.method === 'DELETE' || req.method === 'PATCH' || req.method === 'PUT') && recordMatch) {
      const record = store.records.find((candidate) => candidate.userId === user.id && (candidate.id === recordMatch[1] || candidate.clientRecordId === recordMatch[1]));
      if (!record) return error(res, 404, '记录不存在', 'RECORD_NOT_FOUND');
      if (record.itemId) return error(res, 409, '旧物记录请从物品卡片撤销', 'ITEM_RECORD_LOCKED');
      const previousDay = dateKey(record.occurredAt);
      if (req.method === 'DELETE') {
        store.records = store.records.filter((candidate) => candidate.id !== record.id);
        store.pointsLedger = store.pointsLedger.filter((entry) => entry.recordId !== record.id);
        syncTaskRewardsForDate(user.id, previousDay);
        await persist();
        return json(res, 200, { ok: true, record, deleted: true });
      }
      const data = await body(req);
      const factorId = typeof data.factorId === 'string' ? data.factorId : record.factorId;
      const factor = factorMap.get(factorId);
      const amount = data.amount === undefined ? record.amount : Number(data.amount);
      if (!factor) return error(res, 400, '无效的低碳行为类型');
      if (!Number.isFinite(amount) || amount <= 0 || amount > 100000) return error(res, 400, '数量必须大于 0 且不能过大');
      const occurredAt = data.occurredAt && !Number.isNaN(Date.parse(data.occurredAt)) ? new Date(data.occurredAt).toISOString() : record.occurredAt;
      record.factorId = factorId;
      record.factorVersion = factor.version;
      record.amount = amount;
      record.reductionKg = Number((amount * factor.reductionKgPerUnit).toFixed(4));
      record.points = Math.max(1, Math.round(amount * factor.pointsPerUnit));
      record.occurredAt = occurredAt;
      const ledger = store.pointsLedger.find((entry) => entry.recordId === record.id);
      if (ledger) {
        ledger.points = record.points;
        ledger.reason = factor.label;
      }
      syncTaskRewardsForDate(user.id, previousDay);
      syncTaskRewardsForDate(user.id, dateKey(record.occurredAt));
      await persist();
      return json(res, 200, { ok: true, record, updated: true });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/tasks`) {
      return json(res, 200, { ok: true, tasks: store.tasks.filter((task) => task.active).map((task) => taskView(user.id, task)) });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/points-ledger`) {
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
      return json(res, 200, { ok: true, entries: store.pointsLedger.filter((entry) => entry.userId === user.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, limit), totalPoints: userPoints(user.id) });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/items`) {
      const items = store.itemCycles.filter((item) => item.userId === user.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).map(itemCycleView);
      return json(res, 200, { ok: true, items });
    }

    if (req.method === 'POST' && pathname === `${API_PREFIX}/items`) {
      const data = await body(req);
      const title = String(data.title ?? '').trim().slice(0, 80);
      const itemType = String(data.itemType ?? '').trim().slice(0, 40);
      const flow = String(data.flow ?? '').trim();
      const weightKg = Number(data.weightKg);
      const locationId = typeof data.locationId === 'string' ? data.locationId.slice(0, 100) : '';
      const location = locationId ? store.locations.find((item) => item.id === locationId) : null;
      const clientItemId = typeof data.clientItemId === 'string' ? data.clientItemId.slice(0, 100) : '';
      if (!title || !itemType) return error(res, 400, '物品名称和类型必填');
      if (!ITEM_FLOWS.has(flow)) return error(res, 400, '无效的循环方式');
      if (!Number.isFinite(weightKg) || weightKg <= 0 || weightKg > 1000) return error(res, 400, '物品重量必须大于 0 且不能过大');
      if (locationId && (!location || location.status !== 'open')) return error(res, 400, '无效或不可用的校园点位');
      if (clientItemId) {
        const old = store.itemCycles.find((item) => item.userId === user.id && item.clientItemId === clientItemId);
        if (old) return json(res, 200, { ok: true, item: itemCycleView(old), duplicate: true });
      }
      const factor = factorMap.get('recycle');
      const now = new Date().toISOString();
      const reductionKg = Number((weightKg * factor.reductionKgPerUnit).toFixed(4));
      const points = Math.max(1, Math.round(weightKg * factor.pointsPerUnit));
      const item = {
        id: `item_${randomUUID()}`,
        userId: user.id,
        clientItemId,
        campusId: user.campusId ?? 'hafu-main',
        locationId: location?.id ?? null,
        title,
        itemType,
        weightKg,
        flow,
        status: ITEM_STATUSES[flow],
        cycleCount: 1,
        reductionKg,
        points,
        createdAt: now,
        updatedAt: now,
        events: [{ id: `cycle_${randomUUID()}`, type: flow, label: ITEM_STATUSES[flow], note: String(data.note ?? '').trim().slice(0, 200), locationId: location?.id ?? null, createdAt: now }]
      };
      const action = {
        id: `record_${randomUUID()}`,
        userId: user.id,
        clientRecordId: clientItemId ? `item:${clientItemId}` : '',
        factorId: 'recycle',
        factorVersion: factor.version,
        amount: weightKg,
        reductionKg,
        points,
        locationId: location?.id ?? null,
        verificationStatus: location ? 'location_verified' : 'self_reported',
        itemId: item.id,
        occurredAt: now,
        createdAt: now
      };
      store.itemCycles.push(item);
      store.records.push(action);
      store.pointsLedger.push({ id: `points_${randomUUID()}`, userId: user.id, recordId: action.id, points, reason: `物品循环：${title}`, createdAt: now });
      await persist();
      return json(res, 201, { ok: true, item: itemCycleView(item) });
    }

    const itemEventMatch = pathname.match(new RegExp(`^${API_PREFIX}/items/([^/]+)/cycle-events$`));
    if (req.method === 'POST' && itemEventMatch) {
      const item = store.itemCycles.find((candidate) => candidate.id === itemEventMatch[1] && candidate.userId === user.id);
      if (!item) return error(res, 404, '物品记录不存在', 'ITEM_NOT_FOUND');
      const data = await body(req);
      const type = String(data.type ?? '').trim();
      if (!ITEM_FLOWS.has(type)) return error(res, 400, '无效的流转方式');
      const locationId = typeof data.locationId === 'string' ? data.locationId.slice(0, 100) : '';
      const location = locationId ? store.locations.find((candidate) => candidate.id === locationId) : null;
      if (locationId && (!location || location.status !== 'open')) return error(res, 400, '无效或不可用的校园点位');
      const now = new Date().toISOString();
      item.events = item.events ?? [];
      item.events.push({ id: `cycle_${randomUUID()}`, type, label: ITEM_STATUSES[type], note: String(data.note ?? '').trim().slice(0, 200), locationId: location?.id ?? null, createdAt: now });
      item.flow = type;
      item.status = ITEM_STATUSES[type];
      item.cycleCount += 1;
      item.updatedAt = now;
      await persist();
      return json(res, 200, { ok: true, item: itemCycleView(item) });
    }

    if (req.method === 'POST' && (pathname === `${API_PREFIX}/records` || pathname === `${API_PREFIX}/actions`)) {
      const data = await body(req);
      const factorId = typeof data.factorId === 'string' ? data.factorId : '';
      const factor = factorMap.get(factorId);
      const amount = Number(data.amount);
      const locationId = typeof data.locationId === 'string' ? data.locationId.slice(0, 100) : '';
      const location = locationId ? store.locations.find((item) => item.id === locationId) : null;
      const clientRecordId = typeof (data.clientRecordId ?? data.clientActionId) === 'string' ? String(data.clientRecordId ?? data.clientActionId).slice(0, 100) : '';
      if (!factor) return error(res, 400, '无效的低碳行为类型');
      if (locationId && !location) return error(res, 400, '无效的校园点位');
      if (!Number.isFinite(amount) || amount <= 0 || amount > 100000) return error(res, 400, '数量必须大于 0 且不能过大');
      if (clientRecordId) {
        const old = store.records.find((record) => record.userId === user.id && record.clientRecordId === clientRecordId);
        if (old) return json(res, 200, { ok: true, record: old, duplicate: true });
      }
      const reductionKg = Number((amount * factor.reductionKgPerUnit).toFixed(4));
      const points = Math.max(1, Math.round(amount * factor.pointsPerUnit));
      const record = { id: `record_${randomUUID()}`, userId: user.id, clientRecordId, factorId, factorVersion: factor.version, amount, reductionKg, points, locationId: location?.id ?? null, verificationStatus: location ? 'location_verified' : 'self_reported', occurredAt: data.occurredAt && !Number.isNaN(Date.parse(data.occurredAt)) ? new Date(data.occurredAt).toISOString() : new Date().toISOString(), createdAt: new Date().toISOString() };
      store.records.push(record);
      store.pointsLedger.push({ id: `points_${randomUUID()}`, userId: user.id, recordId: record.id, points, reason: factor.label, createdAt: record.createdAt });
      syncTaskRewardsForDate(user.id, dateKey(record.occurredAt));
      await persist();
      return json(res, 201, { ok: true, record, action: record });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/challenges`) {
      return json(res, 200, { ok: true, challenges: store.challenges.map((challenge) => challengeView(user.id, challenge)) });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/teams`) {
      return json(res, 200, { ok: true, teams: store.teams.map(teamView), mine: store.teams.find((team) => team.id === user.teamId) ? teamView(store.teams.find((team) => team.id === user.teamId)) : null });
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
        item.points = userPoints(record.userId);
        item.reductionKg += record.reductionKg;
        item.records += 1;
        totals.set(record.userId, item);
      }
      const ranking = [...totals.entries()].map(([userId, value]) => ({ user: cleanUser(store.users.find((item) => item.id === userId)), points: value.points, reductionKg: Number(value.reductionKg.toFixed(2)), records: value.records })).sort((a, b) => b.points - a.points).slice(0, 50).map((item, index) => ({ rank: index + 1, ...item }));
      return json(res, 200, { ok: true, ranking, mine: ranking.find((item) => item.user.id === user.id) ?? null });
    }

    return error(res, 404, '接口不存在', 'NOT_FOUND');
  } catch (cause) {
    if (cause instanceof RequestError) return error(res, 400, cause.message);
    console.error(cause);
    return error(res, 500, '服务器内部错误', 'INTERNAL_ERROR');
  }
}

const server = createServer((req, res) => handle(req, res));
server.listen(PORT, HOST, () => console.log(`CarbonLoop backend listening on http://${HOST}:${PORT}`));
