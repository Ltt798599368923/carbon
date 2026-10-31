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
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS'
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

function rewardView(userId, reward) {
  const redeemed = store.redemptions.some((item) => item.userId === userId && item.rewardId === reward.id);
  const totalPoints = userPoints(userId);
  return { ...reward, redeemed, canRedeem: !redeemed && totalPoints >= reward.cost };
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
    workflowStatus: item.workflowStatus ?? 'PENDING',
    workflowStatusLabel: item.workflowStatusLabel ?? '待核验',
    appointment: appointmentView(item.appointment),
    events: [...(item.events ?? [])].sort((a, b) => b.createdAt.localeCompare(a.createdAt))
  };
}

const ITEM_FLOWS = new Set(['recycle', 'exchange', 'donate', 'repair']);
const ITEM_WORKFLOW_STATUSES = new Set(['PENDING', 'APPROVED', 'BOOKED', 'RECEIVED', 'IN_STOCK', 'RESERVED', 'COMPLETED', 'SCRAPPED', 'CANCELED', 'REJECTED']);
const ITEM_APPOINTMENT_CAPACITY = 20;
const ITEM_WORKFLOW_LABELS = {
  PENDING: '待核验',
  APPROVED: '已通过核验',
  BOOKED: '待投递',
  RECEIVED: '已收货',
  IN_STOCK: '在库可领取',
  RESERVED: '已预约领取',
  COMPLETED: '已完成流转',
  SCRAPPED: '已报废处置',
  CANCELED: '已撤回',
  REJECTED: '核验不通过'
};
const ITEM_STATUSES = {
  recycle: '已进入回收流程',
  exchange: '等待交换',
  donate: '已捐赠',
  repair: '维修中'
};
const ITEM_COMPLETED_STATUSES = {
  recycle: '已回收',
  exchange: '已完成交换',
  donate: '已完成捐赠',
  repair: '已维修完成'
};
const REQUEST_TYPES = new Set(['exchange', 'donate']);
const SERVICE_TYPES = new Set(['repair', 'recycle']);

function publicItemView(item) {
  const owner = store.users.find((candidate) => candidate.id === item.userId);
  const requests = store.itemRequests.filter((request) => request.itemId === item.id);
  return {
    ...itemCycleView(item),
    owner: owner ? cleanUser(owner) : null,
    requestCount: requests.length,
    hasMyPendingRequest: false
  };
}

function itemRequestView(request, viewerId) {
  const item = store.itemCycles.find((candidate) => candidate.id === request.itemId);
  const applicant = store.users.find((candidate) => candidate.id === request.applicantId);
  const owner = store.users.find((candidate) => candidate.id === request.ownerId);
  return {
    ...request,
    item: item ? { id: item.id, title: item.title, itemType: item.itemType, flow: item.flow, status: item.status } : null,
    applicant: applicant ? cleanUser(applicant) : null,
    owner: owner ? cleanUser(owner) : null,
    isIncoming: request.ownerId === viewerId
  };
}

function serviceOrderView(order) {
  const item = store.itemCycles.find((candidate) => candidate.id === order.itemId);
  const requester = store.users.find((candidate) => candidate.id === order.requesterId);
  const provider = order.providerId ? store.users.find((candidate) => candidate.id === order.providerId) : null;
  const location = order.locationId ? store.locations.find((candidate) => candidate.id === order.locationId) : null;
  return {
    ...order,
    item: item ? { id: item.id, title: item.title, itemType: item.itemType, status: item.status } : null,
    requester: requester ? cleanUser(requester) : null,
    provider: provider ? cleanUser(provider) : null,
    location: location ? locationView(location) : null
  };
}

function awardPoints(userId, points, reason, orderId = undefined) {
  store.pointsLedger.push({
    id: `points_${randomUUID()}`,
    userId,
    points,
    reason,
    orderId,
    createdAt: new Date().toISOString()
  });
}


const ITEM_STATIONS = [
  { id: 'station-east', name: '东区旧物驿站', address: '生活区东侧服务点', openHours: '周一至周六 09:00-20:00', enabled: true },
  { id: 'station-library', name: '图书馆共享驿站', address: '图书馆一层服务台', openHours: '周一至周五 10:00-18:00', enabled: true }
];

function itemWorkflowLabel(status) {
  return ITEM_WORKFLOW_LABELS[status] ?? status;
}

function itemEvent(item, type, label, note, actor = 'CarbonLoop') {
  const now = new Date().toISOString();
  item.events = item.events ?? [];
  item.events.push({ id: `cycle_${randomUUID()}`, type, label, note: String(note ?? '').trim().slice(0, 200), actor, createdAt: now });
  item.updatedAt = now;
}

function updateItemWorkflow(item, status, note, actor = 'CarbonLoop') {
  if (!ITEM_WORKFLOW_STATUSES.has(status)) return false;
  item.workflowStatus = status;
  item.workflowStatusLabel = itemWorkflowLabel(status);
  itemEvent(item, status.toLowerCase(), item.workflowStatusLabel, note, actor);
  return true;
}

function nextAppointmentCode(item) {
  const existing = new Set(store.itemCycles.flatMap((candidate) => candidate.appointment?.code ? [candidate.appointment.code] : []));
  let code = '';
  do {
    code = String(10000000 + Math.floor(Math.random() * 90000000));
  } while (existing.has(code));
  return code;
}

function stationView(station) {
  return { ...station, enabled: true };
}

function getStation(stationId) {
  return ITEM_STATIONS.find((station) => station.id === stationId) ?? null;
}

function activeAppointmentCount(stationId, slot) {
  return store.itemCycles.filter((item) => item.appointment?.stationId === stationId && item.appointment?.slot === slot && item.appointment?.state === 'active').length;
}

function refreshItemAppointment(item) {
  const appointment = item.appointment;
  if (!appointment || appointment.state !== 'active' || !appointment.expiresAt) return false;
  if (Date.parse(appointment.expiresAt) >= Date.now()) return false;
  appointment.state = 'expired';
  appointment.usedAt = null;
  if (appointment.type === 'delivery' && item.workflowStatus === 'BOOKED') updateItemWorkflow(item, 'APPROVED', '投递预约已过期，物品退回可预约状态', 'system');
  if (appointment.type === 'pickup' && item.workflowStatus === 'RESERVED') updateItemWorkflow(item, 'IN_STOCK', '领取预约已过期，库存已释放', 'system');
  return true;
}

function refreshAllItemAppointments() {
  let changed = false;
  for (const item of store.itemCycles) changed = refreshItemAppointment(item) || changed;
  return changed;
}

function appointmentView(appointment) {
  if (!appointment) return null;
  const { bookedByUserId, ...publicAppointment } = appointment;
  return publicAppointment;
}

function catalogItemView(item) {
  const view = itemCycleView(item);
  const { userId, clientItemId, ...publicItem } = view;
  return publicItem;
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
        user = { id: `user_${randomUUID()}`, deviceId, nickname: String(data.nickname ?? '校园用户').trim().slice(0, 30) || '校园用户', campus: String(data.campus ?? '郑州西亚斯学院').trim().slice(0, 50), campusId: 'hafu-main', teamId: 'team-dorm-302', createdAt: new Date().toISOString() };
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

    if (req.method === 'GET' && pathname === `${API_PREFIX}/items/stations`) {
      return json(res, 200, { ok: true, stations: ITEM_STATIONS.map(stationView) });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/items/catalog`) {
      if (refreshAllItemAppointments()) await persist();
      const items = store.itemCycles
        .filter((item) => ['APPROVED', 'BOOKED', 'RECEIVED', 'IN_STOCK', 'RESERVED', 'COMPLETED'].includes(item.workflowStatus ?? 'PENDING'))
        .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
        .map(catalogItemView);
      return json(res, 200, { ok: true, items });
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

    if (req.method === 'GET' && pathname === `${API_PREFIX}/rewards`) {
      return json(res, 200, {
        ok: true,
        rewards: store.rewards.map((reward) => rewardView(user.id, reward)),
        redemptions: store.redemptions.filter((item) => item.userId === user.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)),
        totalPoints: userPoints(user.id)
      });
    }

    const rewardMatch = pathname.match(new RegExp(`^${API_PREFIX}/rewards/([^/]+)/redeem$`));
    if (req.method === 'POST' && rewardMatch) {
      const reward = store.rewards.find((item) => item.id === rewardMatch[1]);
      if (!reward) return error(res, 404, '奖励不存在', 'REWARD_NOT_FOUND');
      const redeemed = store.redemptions.some((item) => item.userId === user.id && item.rewardId === reward.id);
      if (redeemed && reward.limitPerUser === 1) return error(res, 409, '该奖励每位用户只能兑换一次', 'REWARD_ALREADY_REDEEMED');
      const totalPoints = userPoints(user.id);
      if (totalPoints < reward.cost) return error(res, 400, `积分不足，需要 ${reward.cost} 分`, 'INSUFFICIENT_POINTS');
      const now = new Date().toISOString();
      const redemption = { id: `redemption_${randomUUID()}`, userId: user.id, rewardId: reward.id, rewardName: reward.name, cost: reward.cost, kind: reward.kind, code: reward.code, createdAt: now };
      store.redemptions.push(redemption);
      store.pointsLedger.push({ id: `points_${randomUUID()}`, userId: user.id, points: -reward.cost, reason: `兑换：${reward.name}`, createdAt: now });
      await persist();
      return json(res, 201, { ok: true, reward: rewardView(user.id, reward), redemption, totalPoints: userPoints(user.id) });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/points-ledger`) {
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
      return json(res, 200, { ok: true, entries: store.pointsLedger.filter((entry) => entry.userId === user.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, limit), totalPoints: userPoints(user.id) });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/items/market`) {
      const flow = url.searchParams.get('flow');
      const status = url.searchParams.get('status');
      const items = store.itemCycles
        .filter((item) => item.public !== false && item.userId !== user.id)
        .filter((item) => !flow || item.flow === flow)
        .filter((item) => !status || item.status === status)
        .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
        .map((item) => ({
          ...publicItemView(item),
          hasMyPendingRequest: store.itemRequests.some((request) => request.itemId === item.id && request.applicantId === user.id && request.status === 'pending')
        }));
      return json(res, 200, { ok: true, items });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/items`) {
      const items = store.itemCycles.filter((item) => item.userId === user.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).map(itemCycleView);
      return json(res, 200, { ok: true, items });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/requests`) {
      const scope = url.searchParams.get('scope') ?? 'all';
      const requests = store.itemRequests
        .filter((request) => scope === 'incoming' ? request.ownerId === user.id : scope === 'outgoing' ? request.applicantId === user.id : request.ownerId === user.id || request.applicantId === user.id)
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
        .map((request) => itemRequestView(request, user.id));
      return json(res, 200, { ok: true, requests });
    }

    const itemRequestMatch = pathname.match(new RegExp(`^${API_PREFIX}/items/([^/]+)/requests$`));
    if (req.method === 'POST' && itemRequestMatch) {
      const item = store.itemCycles.find((candidate) => candidate.id === itemRequestMatch[1] && candidate.public !== false);
      if (!item) return error(res, 404, '公开物品不存在', 'ITEM_NOT_FOUND');
      if (item.userId === user.id) return error(res, 400, '不能申请自己的物品', 'OWN_ITEM');
      if (!REQUEST_TYPES.has(item.flow)) return error(res, 400, '该物品当前不支持交换或领取', 'ITEM_NOT_AVAILABLE');
      if (item.status !== ITEM_STATUSES[item.flow]) return error(res, 409, '该物品当前不可申请', 'ITEM_NOT_AVAILABLE');
      const data = await body(req);
      const duplicate = store.itemRequests.find((request) => request.itemId === item.id && request.applicantId === user.id && ['pending', 'accepted'].includes(request.status));
      if (duplicate) return json(res, 200, { ok: true, request: itemRequestView(duplicate, user.id), duplicate: true });
      const now = new Date().toISOString();
      const request = {
        id: `request_${randomUUID()}`,
        itemId: item.id,
        ownerId: item.userId,
        applicantId: user.id,
        type: item.flow,
        message: String(data.message ?? '').trim().slice(0, 300),
        offerTitle: String(data.offerTitle ?? '').trim().slice(0, 100),
        status: 'pending',
        createdAt: now,
        updatedAt: now
      };
      store.itemRequests.push(request);
      item.updatedAt = now;
      await persist();
      return json(res, 201, { ok: true, request: itemRequestView(request, user.id) });
    }

    const requestDecisionMatch = pathname.match(new RegExp(`^${API_PREFIX}/requests/([^/]+)/(accept|reject|cancel)$`));
    if (req.method === 'POST' && requestDecisionMatch) {
      const request = store.itemRequests.find((candidate) => candidate.id === requestDecisionMatch[1]);
      if (!request) return error(res, 404, '申请不存在', 'REQUEST_NOT_FOUND');
      const action = requestDecisionMatch[2];
      if (action === 'accept' && request.ownerId !== user.id) return error(res, 403, '只有物品发布者可以同意申请', 'FORBIDDEN');
      if ((action === 'reject' || action === 'cancel') && request.ownerId !== user.id && request.applicantId !== user.id) return error(res, 403, '无权处理该申请', 'FORBIDDEN');
      if (request.status !== 'pending') return json(res, 200, { ok: true, request: itemRequestView(request, user.id), duplicate: true });
      const item = store.itemCycles.find((candidate) => candidate.id === request.itemId);
      const now = new Date().toISOString();
      request.status = action === 'accept' ? 'accepted' : action === 'reject' ? 'rejected' : 'cancelled';
      request.updatedAt = now;
      if (action === 'accept' && item) {
        item.status = item.flow === 'exchange' ? '已有人申请交换' : '已有人申请领取';
        item.reservedBy = request.applicantId;
        item.updatedAt = now;
        for (const other of store.itemRequests.filter((candidate) => candidate.itemId === item.id && candidate.id !== request.id && candidate.status === 'pending')) {
          other.status = 'rejected';
          other.updatedAt = now;
        }
      }
      await persist();
      return json(res, 200, { ok: true, request: itemRequestView(request, user.id) });
    }

    const requestCompleteMatch = pathname.match(new RegExp(`^${API_PREFIX}/requests/([^/]+)/complete$`));
    if (req.method === 'POST' && requestCompleteMatch) {
      const request = store.itemRequests.find((candidate) => candidate.id === requestCompleteMatch[1]);
      if (!request) return error(res, 404, '申请不存在', 'REQUEST_NOT_FOUND');
      if (request.ownerId !== user.id && request.applicantId !== user.id) return error(res, 403, '无权确认该申请', 'FORBIDDEN');
      if (!['accepted', 'completion_pending'].includes(request.status)) return error(res, 409, '只有已同意的申请才能完成', 'REQUEST_NOT_ACCEPTED');
      const item = store.itemCycles.find((candidate) => candidate.id === request.itemId);
      const now = new Date().toISOString();
      if (user.id === request.ownerId) request.ownerConfirmed = true;
      if (user.id === request.applicantId) request.applicantConfirmed = true;
      request.updatedAt = now;
      const bothConfirmed = request.ownerConfirmed === true && request.applicantConfirmed === true;
      request.status = bothConfirmed ? 'completed' : 'completion_pending';
      if (bothConfirmed) {
        request.completedAt = now;
        if (item) {
          item.status = ITEM_COMPLETED_STATUSES[item.flow];
          item.completedAt = now;
          item.updatedAt = now;
        }
        if (!request.pointsAwarded) {
          awardPoints(request.ownerId, 5, `${item?.flow === 'exchange' ? '完成交换' : '完成捐赠'}：${item?.title ?? '旧物'}`, request.id);
          awardPoints(request.applicantId, 5, `${item?.flow === 'exchange' ? '完成交换' : '完成领取'}：${item?.title ?? '旧物'}`, request.id);
          request.pointsAwarded = true;
        }
      }
      await persist();
      return json(res, 200, { ok: true, request: itemRequestView(request, user.id), item: item ? itemCycleView(item) : null, waitingForOtherParty: !bothConfirmed });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/service-orders`) {
      const scope = url.searchParams.get('scope') ?? 'mine';
      const orders = store.serviceOrders
        .filter((order) => scope === 'open' ? !order.providerId && order.status === 'pending' : scope === 'provider' ? order.providerId === user.id : order.requesterId === user.id || order.providerId === user.id)
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
        .map(serviceOrderView);
      return json(res, 200, { ok: true, orders });
    }

    if (req.method === 'POST' && pathname === `${API_PREFIX}/service-orders`) {
      const data = await body(req);
      const itemId = String(data.itemId ?? '').trim();
      const item = store.itemCycles.find((candidate) => candidate.id === itemId && candidate.userId === user.id);
      if (!item) return error(res, 404, '只能为自己发布的物品提交服务订单', 'ITEM_NOT_FOUND');
      if (!SERVICE_TYPES.has(item.flow)) return error(res, 400, '只有维修或回收物品可以提交服务订单', 'INVALID_SERVICE_TYPE');
      const existing = store.serviceOrders.find((order) => order.itemId === item.id && ['pending', 'accepted', 'in_progress'].includes(order.status));
      if (existing) return json(res, 200, { ok: true, order: serviceOrderView(existing), duplicate: true });
      const locationId = typeof data.locationId === 'string' ? data.locationId.slice(0, 100) : '';
      const location = locationId ? store.locations.find((candidate) => candidate.id === locationId && candidate.status === 'open') : null;
      if (locationId && !location) return error(res, 400, '无效或不可用的服务点位');
      const now = new Date().toISOString();
      const order = {
        id: `service_${randomUUID()}`,
        itemId: item.id,
        requesterId: user.id,
        providerId: null,
        type: item.flow,
        description: String(data.description ?? '').trim().slice(0, 500),
        locationId: location?.id ?? null,
        scheduledAt: typeof data.scheduledAt === 'string' ? data.scheduledAt.slice(0, 50) : null,
        status: 'pending',
        createdAt: now,
        updatedAt: now
      };
      store.serviceOrders.push(order);
      item.status = item.flow === 'repair' ? '等待维修人员接单' : '等待回收员接单';
      item.updatedAt = now;
      await persist();
      return json(res, 201, { ok: true, order: serviceOrderView(order) });
    }

    const serviceAcceptMatch = pathname.match(new RegExp(`^${API_PREFIX}/service-orders/([^/]+)/accept$`));
    if (req.method === 'POST' && serviceAcceptMatch) {
      const order = store.serviceOrders.find((candidate) => candidate.id === serviceAcceptMatch[1]);
      if (!order) return error(res, 404, '服务订单不存在', 'SERVICE_ORDER_NOT_FOUND');
      if (order.requesterId === user.id) return error(res, 400, '不能接自己的服务订单', 'OWN_ORDER');
      if (order.status !== 'pending' || order.providerId) return error(res, 409, '该订单已经被接单或已结束', 'ORDER_NOT_AVAILABLE');
      const now = new Date().toISOString();
      order.providerId = user.id;
      order.status = 'accepted';
      order.updatedAt = now;
      const item = store.itemCycles.find((candidate) => candidate.id === order.itemId);
      if (item) { item.status = order.type === 'repair' ? '维修中' : '回收员处理中'; item.updatedAt = now; }
      await persist();
      return json(res, 200, { ok: true, order: serviceOrderView(order) });
    }

    const serviceCompleteMatch = pathname.match(new RegExp(`^${API_PREFIX}/service-orders/([^/]+)/complete$`));
    if (req.method === 'POST' && serviceCompleteMatch) {
      const order = store.serviceOrders.find((candidate) => candidate.id === serviceCompleteMatch[1]);
      if (!order) return error(res, 404, '服务订单不存在', 'SERVICE_ORDER_NOT_FOUND');
      if (order.requesterId !== user.id && order.providerId !== user.id) return error(res, 403, '无权完成该订单', 'FORBIDDEN');
      if (!['accepted', 'completion_pending'].includes(order.status)) return error(res, 409, '订单当前不能完成', 'ORDER_NOT_ACTIVE');
      const now = new Date().toISOString();
      if (user.id === order.requesterId) order.requesterConfirmed = true;
      if (user.id === order.providerId) order.providerConfirmed = true;
      order.updatedAt = now;
      const bothConfirmed = order.requesterConfirmed === true && order.providerConfirmed === true;
      order.status = bothConfirmed ? 'completed' : 'completion_pending';
      const item = store.itemCycles.find((candidate) => candidate.id === order.itemId);
      if (bothConfirmed) {
        order.completedAt = now;
        if (item) { item.status = ITEM_COMPLETED_STATUSES[order.type]; item.completedAt = now; item.updatedAt = now; }
        if (!order.pointsAwarded) {
          awardPoints(order.requesterId, 5, `${order.type === 'repair' ? '完成维修' : '完成回收'}：${item?.title ?? '旧物'}`, order.id);
          if (order.providerId) awardPoints(order.providerId, 3, `${order.type === 'repair' ? '提供维修服务' : '完成回收服务'}：${item?.title ?? '旧物'}`, order.id);
          order.pointsAwarded = true;
        }
      }
      await persist();
      return json(res, 200, { ok: true, order: serviceOrderView(order), item: item ? itemCycleView(item) : null, waitingForOtherParty: !bothConfirmed });
    }

    if (req.method === 'GET' && pathname === `${API_PREFIX}/items`) {
      if (refreshAllItemAppointments()) await persist();
      const items = store.itemCycles.filter((item) => item.userId === user.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).map(itemCycleView);
      return json(res, 200, { ok: true, items });
    }

    if (req.method === 'POST' && pathname === `${API_PREFIX}/items`) {
      const data = await body(req);
      const title = String(data.title ?? '').trim().slice(0, 80);
      const itemType = String(data.itemType ?? '').trim().slice(0, 40);
      const flow = String(data.flow ?? '').trim();
      const weightKg = Number(data.weightKg);
      const conditionLevel = Number(data.conditionLevel ?? 0);
      const quantity = Number(data.quantity ?? 1);
      const locationId = typeof data.locationId === 'string' ? data.locationId.slice(0, 100) : '';
      const location = locationId ? store.locations.find((item) => item.id === locationId) : null;
      const clientItemId = typeof data.clientItemId === 'string' ? data.clientItemId.slice(0, 100) : '';
      if (!title || !itemType) return error(res, 400, '物品名称和类型必填');
      if (!ITEM_FLOWS.has(flow)) return error(res, 400, '无效的循环方式');
      if (!Number.isFinite(weightKg) || weightKg <= 0 || weightKg > 1000) return error(res, 400, '物品重量必须大于 0 且不能过大');
      if (!Number.isInteger(quantity) || quantity < 1 || quantity > 1000) return error(res, 400, '物品数量必须为正整数');
      if (data.conditionLevel !== undefined && (!Number.isInteger(conditionLevel) || conditionLevel < 1 || conditionLevel > 5)) return error(res, 400, '成色需为 1 至 5 档');
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
        public: data.public !== false,
        campusId: user.campusId ?? 'hafu-main',
        locationId: location?.id ?? null,
        title,
        itemType,
        weightKg,
        quantity,
        conditionLevel: conditionLevel || null,
        verifiedConditionLevel: null,
        description: String(data.description ?? '').trim().slice(0, 300),
        imageUris: Array.isArray(data.imageUris) ? data.imageUris.filter((uri) => typeof uri === 'string').slice(0, 6) : [],
        transferMethod: typeof data.transferMethod === 'string' ? data.transferMethod.slice(0, 30) : flow,
        flow,
        status: ITEM_STATUSES[flow],
        workflowStatus: 'PENDING',
        workflowStatusLabel: itemWorkflowLabel('PENDING'),
        appointment: null,
        cycleCount: 1,
        reductionKg,
        points,
        createdAt: now,
        updatedAt: now,
        events: [{ id: `cycle_${randomUUID()}`, type: 'pending', label: itemWorkflowLabel('PENDING'), note: '已提交管理员核验', actor: user.nickname, locationId: location?.id ?? null, createdAt: now }]
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

    const workflowMatch = pathname.match(new RegExp(`^${API_PREFIX}/items/([^/]+)/(approve|reject|appointments|verify-delivery|shelve|reserve|complete|scrap|cancel)$`));
    if (req.method === 'POST' && workflowMatch) {
      const item = store.itemCycles.find((candidate) => candidate.id === workflowMatch[1]);
      if (!item) return error(res, 404, '物品记录不存在', 'ITEM_NOT_FOUND');
      const action = workflowMatch[2];
      const data = await body(req);
      refreshItemAppointment(item);

      if (action === 'approve') {
        if (item.workflowStatus !== 'PENDING') return error(res, 409, '仅待核验物品可以通过审核', 'INVALID_ITEM_STATE');
        updateItemWorkflow(item, 'APPROVED', '内容与图片已完成体验审核', user.nickname);
        item.verificationRemark = '内容与图片已完成体验审核';
      } else if (action === 'reject') {
        const reason = String(data.reason ?? data.note ?? '').trim().slice(0, 200);
        if (item.workflowStatus !== 'PENDING') return error(res, 409, '仅待核验物品可以驳回', 'INVALID_ITEM_STATE');
        if (reason.length < 2) return error(res, 400, '请填写驳回意见');
        item.verificationRemark = reason;
        updateItemWorkflow(item, 'REJECTED', reason, user.nickname);
      } else if (action === 'appointments') {
        const type = data.type === 'pickup' ? 'pickup' : data.type === 'delivery' ? 'delivery' : '';
        const stationId = String(data.stationId ?? '').trim();
        const station = getStation(stationId);
        const slot = String(data.slot ?? '').trim().slice(0, 80);
        const slotStartsAt = data.slotStartsAt && !Number.isNaN(Date.parse(data.slotStartsAt)) ? new Date(data.slotStartsAt).toISOString() : '';
        if (!station || !station.enabled) return error(res, 400, '请选择有效的开放驿站');
        if (!type) return error(res, 400, '预约类型必须为 delivery 或 pickup');
        if (!slot || !slotStartsAt) return error(res, 400, '预约时段和开始时间必填');
        if (Date.parse(slotStartsAt) < Date.now()) return error(res, 400, '预约开始时间不能早于当前时间');
        if (activeAppointmentCount(stationId, slot) >= ITEM_APPOINTMENT_CAPACITY) return error(res, 409, '该时段预约已满', 'APPOINTMENT_FULL');
        if (type === 'delivery') {
          if (item.userId !== user.id) return error(res, 403, '只能为自己的物品预约投递', 'FORBIDDEN');
          if (item.workflowStatus !== 'APPROVED') return error(res, 409, '只有已通过核验的物品可以预约投递', 'INVALID_ITEM_STATE');
        } else if (item.workflowStatus !== 'IN_STOCK') {
          return error(res, 409, '这件物品暂不可预约领取', 'INVALID_ITEM_STATE');
        }
        const now = new Date().toISOString();
        item.appointment = { type, code: nextAppointmentCode(item), stationId, stationName: station.name, slot, slotStartsAt, expiresAt: new Date(new Date(slotStartsAt).setHours(23, 59, 59, 999)).toISOString(), state: 'active', usedAt: null, bookedByUserId: user.id };
        item.stationId = stationId;
        updateItemWorkflow(item, type === 'delivery' ? 'BOOKED' : 'RESERVED', type === 'delivery' ? '预约投递，已生成 8 位核销码' : '预约领取，库存已锁定', user.nickname);
        item.updatedAt = now;
      } else if (action === 'verify-delivery') {
        const code = String(data.code ?? '').trim();
        const appointment = item.appointment;
        const stationId = String(data.stationId ?? '').trim();
        if (!/^\d{8}$/.test(code) || !appointment || appointment.code !== code || appointment.type !== 'delivery') return error(res, 400, '投递预约码无效');
        if (appointment.state === 'used') return error(res, 409, '该预约码已核销，不能重复处理', 'APPOINTMENT_USED');
        if (appointment.state !== 'active') return error(res, 409, '该预约码已取消或过期', 'APPOINTMENT_INACTIVE');
        if (appointment.stationId !== stationId) return error(res, 403, '该预约不属于当前驿站', 'STATION_MISMATCH');
        if (item.workflowStatus !== 'BOOKED') return error(res, 409, '物品状态不允许收货核销', 'INVALID_ITEM_STATE');
        const actualWeightKg = Number(data.actualWeightKg ?? data.weightKg);
        const verifiedConditionLevel = Number(data.verifiedConditionLevel ?? data.conditionLevel);
        if (!Number.isFinite(actualWeightKg) || actualWeightKg <= 0) return error(res, 400, '请输入大于 0 的现场复核重量');
        if (!Number.isInteger(verifiedConditionLevel) || verifiedConditionLevel < 1 || verifiedConditionLevel > 5) return error(res, 400, '请选择 1 至 5 档复核成色');
        item.actualWeightKg = actualWeightKg;
        item.verifiedConditionLevel = verifiedConditionLevel;
        appointment.state = 'used';
        appointment.usedAt = new Date().toISOString();
        updateItemWorkflow(item, 'RECEIVED', `扫码收货；复核重量 ${actualWeightKg} kg，成色 ${verifiedConditionLevel} 档`, user.nickname);
      } else if (action === 'shelve') {
        const shelfLocation = String(data.shelfLocation ?? data.shelf ?? '').trim().slice(0, 30);
        if (item.workflowStatus !== 'RECEIVED') return error(res, 409, '仅已收货物品可以上架', 'INVALID_ITEM_STATE');
        if (!shelfLocation) return error(res, 400, '请填写货位号');
        if (store.itemCycles.some((candidate) => candidate.id !== item.id && candidate.workflowStatus === 'IN_STOCK' && candidate.stationId === item.stationId && candidate.shelfLocation === shelfLocation)) return error(res, 409, '该货位已被占用', 'SHELF_OCCUPIED');
        item.shelfLocation = shelfLocation;
        updateItemWorkflow(item, 'IN_STOCK', `完成上架，货位 ${shelfLocation}`, user.nickname);
      } else if (action === 'reserve') {
        if (item.workflowStatus !== 'IN_STOCK') return error(res, 409, '这件物品暂不可预约领取', 'INVALID_ITEM_STATE');
        const station = getStation(String(data.stationId ?? item.stationId));
        const slot = String(data.slot ?? '').trim().slice(0, 80);
        const slotStartsAt = data.slotStartsAt && !Number.isNaN(Date.parse(data.slotStartsAt)) ? new Date(data.slotStartsAt).toISOString() : '';
        if (!station || !slot || !slotStartsAt) return error(res, 400, '领取驿站和预约时段必填');
        if (Date.parse(slotStartsAt) < Date.now()) return error(res, 400, '预约开始时间不能早于当前时间');
        if (activeAppointmentCount(station.id, slot) >= ITEM_APPOINTMENT_CAPACITY) return error(res, 409, '该时段预约已满', 'APPOINTMENT_FULL');
        item.stationId = station.id;
        item.appointment = { type: 'pickup', code: nextAppointmentCode(item), stationId: station.id, stationName: station.name, slot, slotStartsAt, expiresAt: new Date(new Date(slotStartsAt).setHours(23, 59, 59, 999)).toISOString(), state: 'active', usedAt: null, bookedByUserId: user.id };
        updateItemWorkflow(item, 'RESERVED', '预约领取，库存已锁定', user.nickname);
      } else if (action === 'complete') {
        const appointment = item.appointment;
        if (item.workflowStatus !== 'RESERVED' || !appointment || appointment.type !== 'pickup') return error(res, 409, '物品状态不允许领取核销', 'INVALID_ITEM_STATE');
        const code = String(data.code ?? '').trim();
        const operatorMode = code.length > 0;
        if (operatorMode) {
          if (code !== appointment.code) return error(res, 400, '领取预约码无效');
          if (appointment.stationId !== String(data.stationId ?? '').trim()) return error(res, 403, '该预约不属于当前驿站', 'STATION_MISMATCH');
        } else if (appointment.bookedByUserId !== user.id) {
          return error(res, 403, '只有预约人或驿站操作员可以完成领取', 'FORBIDDEN');
        }
        if (appointment.state === 'used') return error(res, 409, '该领取预约已完成，不能重复处理', 'APPOINTMENT_USED');
        if (appointment.state !== 'active') return error(res, 409, '该领取预约已取消或过期', 'APPOINTMENT_INACTIVE');
        appointment.state = 'used';
        appointment.usedAt = new Date().toISOString();
        updateItemWorkflow(item, 'COMPLETED', '预约领取核销完成', user.nickname);
      } else if (action === 'scrap') {
        const reason = String(data.reason ?? data.note ?? '').trim().slice(0, 200);
        if (item.workflowStatus !== 'RECEIVED') return error(res, 409, '仅已收货物品可以报废处置', 'INVALID_ITEM_STATE');
        if (reason.length < 2) return error(res, 400, '报废原因必填');
        item.scrapReason = reason;
        updateItemWorkflow(item, 'SCRAPPED', `报废处置：${reason}`, user.nickname);
      } else if (action === 'cancel') {
        if (!['PENDING', 'APPROVED', 'BOOKED', 'RESERVED'].includes(item.workflowStatus)) return error(res, 409, '当前状态不可撤回', 'INVALID_ITEM_STATE');
        if (item.appointment?.state === 'active') item.appointment.state = 'canceled';
        updateItemWorkflow(item, item.workflowStatus === 'RESERVED' ? 'IN_STOCK' : 'CANCELED', '用户主动撤回或取消预约', user.nickname);
      }
      await persist();
      return json(res, 200, { ok: true, item: itemCycleView(item) });
    }

    const itemEventMatch = pathname.match(new RegExp(`^${API_PREFIX}/items/([^/]+)/cycle-events$`));
    if (req.method === 'POST' && itemEventMatch) {
      const item = store.itemCycles.find((candidate) => candidate.id === itemEventMatch[1] && candidate.userId === user.id);
      if (!item) return error(res, 404, '物品记录不存在', 'ITEM_NOT_FOUND');
      const data = await body(req);
      const type = String(data.type ?? '').trim();
      if (!ITEM_FLOWS.has(type)) return error(res, 400, '无效的流转方式');
      // 同一物品连续点击当前状态时保持幂等，避免重复增加流转次数。
      if (item.flow === type) return json(res, 200, { ok: true, item: itemCycleView(item), duplicate: true });
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
