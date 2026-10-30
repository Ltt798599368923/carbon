import { ICONS, LOCAL_FACTORS } from './modules/factors.js';
import { request } from './modules/api-client.js';
import { getPendingActions, saveDeviceId, savePendingActions as persistPendingActions, saveToken } from './modules/local-store.js';
import { flushPendingActions as flushQueue } from './modules/sync-queue.js';

const state = {
  factors: {},
  records: [],
  items: [],
  challenges: [],
  locations: [],
  teams: [],
  campus: null,
  campusSummary: { participantCount: 0, actionCount: 0, totalReductionKg: 0, activeLocationCount: 0 },
  locationFilter: 'all',
  selectedLocationId: '',
  pendingActions: getPendingActions(),
  user: null,
  summary: { totalReductionKg: 0, totalPoints: 0, recordCount: 0 },
  currentView: 'home',
  ready: false,
};

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const format = (value) => Number(value || 0).toFixed(2);
const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]));
const dateKey = (value = new Date()) => {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return [date.getFullYear(), String(date.getMonth() + 1).padStart(2, '0'), String(date.getDate()).padStart(2, '0')].join('-');
};
const clientId = () => window.crypto?.randomUUID?.() || `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;

function showToast(message) {
  const toast = $('#toast');
  toast.textContent = message;
  toast.classList.add('show');
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => toast.classList.remove('show'), 2800);
}

async function login() {
  const response = await request('/api/v1/auth/guest', {
    method: 'POST',
    body: JSON.stringify({ deviceId: saveDeviceId(), nickname: '校园用户', campus: '我的校园' }),
  });
  saveToken(response.token);
  state.user = response.user;
}

async function refresh() {
  await flushPendingActions();
  const dashboard = await request('/api/v1/dashboard');
  const optional = (path, fallback) => request(path).catch(() => fallback);
  const [records, challenges, factors, overview, teams, items] = await Promise.all([
    optional('/api/v1/records?limit=100', { records: state.records }),
    optional('/api/v1/challenges', { challenges: state.challenges }),
    optional('/api/v1/factors', { factors: Object.values(state.factors) }),
    optional('/api/v1/campus/overview', { campus: state.campus, summary: state.campusSummary, locations: state.locations }),
    optional('/api/v1/teams', { teams: state.teams }),
    optional('/api/v1/items', { items: state.items }),
  ]);
  state.user = dashboard.user || state.user;
  state.summary = dashboard.summary || state.summary;
  state.records = records.records || [];
  state.challenges = challenges.challenges || [];
  state.factors = Object.fromEntries((factors.factors || []).map((factor) => [factor.id, factor]));
  state.campus = overview.campus;
  state.campusSummary = overview.summary || state.campusSummary;
  state.locations = overview.locations || [];
  state.teams = teams.teams || [];
  state.items = items.items || dashboard.recentItems || [];
  state.ready = true;
  updateProfile();
  render();
}

function savePendingActions() {
  persistPendingActions(state.pendingActions);
}

async function flushPendingActions() {
  if (!state.pendingActions.length) return;
  state.pendingActions = await flushQueue(state.pendingActions, request);
  savePendingActions();
}

async function boot() {
  try {
    await login();
    await refresh();
    showToast('已连接 CarbonLoop 云端数据');
  } catch (error) {
    state.ready = false;
    render();
    showToast(`无法连接后端：${error.message}`);
  }
}

function navigate(view) {
  state.currentView = view;
  $$('.view').forEach((node) => node.classList.toggle('active', node.dataset.view === view));
  $$('.nav-item').forEach((node) => node.classList.toggle('active', node.dataset.go === view));
  window.scrollTo({ top: 0, behavior: 'smooth' });
  render();
}

function metricCard(label, value, unit, foot) {
  return `<article class="metric-card"><div class="metric-label">${escapeHtml(label)}</div><div class="metric-value">${escapeHtml(value)}<span class="metric-unit">${escapeHtml(unit)}</span></div><div class="metric-foot">${escapeHtml(foot)}</div></article>`;
}

function renderMetrics() {
  const today = state.records.filter((item) => dateKey(item.occurredAt) === dateKey()).reduce((sum, item) => sum + item.reductionKg, 0);
  const joinedCount = state.challenges.filter((challenge) => challenge.joined).length;
  const metrics = [
    metricCard('今日减排', format(today), 'kg', state.ready ? '来自云端记录' : '等待连接后加载'),
    metricCard('累计减排', format(state.summary.totalReductionKg), 'kg', `${state.summary.recordCount} 笔低碳记录`),
    metricCard('碳积分', `${state.summary.totalPoints || 0}`, '分', `${joinedCount} 个挑战已加入`),
  ];
  $('#metricGrid').innerHTML = metrics.join('');
  $('#profileMetrics').innerHTML = [
    metricCard('累计减排', format(state.summary.totalReductionKg), 'kg', '服务端核算'),
    metricCard('完成行为', `${state.summary.recordCount || 0}`, '次', '持续记录中'),
    metricCard('参与挑战', `${joinedCount}`, '个', '云端同步'),
  ].join('');
  renderCampusOverview();
}

const LOCATION_META = {
  recycle: { icon: '♻', label: '物品循环', color: 'green' },
  exchange: { icon: '↔', label: '二手交换', color: 'blue' },
  repair: { icon: '⌁', label: '维修再用', color: 'orange' },
  mobility: { icon: '↗', label: '绿色出行', color: 'green' },
  reuse: { icon: '◉', label: '减少一次性用品', color: 'blue' },
};

function locationCard(location) {
  const meta = LOCATION_META[location.type] || { icon: '•', label: '校园行动', color: 'green' };
  const itemLocation = ['recycle', 'exchange', 'repair'].includes(location.type);
  return `<article class="location-row"><div class="location-symbol ${meta.color}">${meta.icon}</div><div class="location-copy"><div class="location-title-line"><h3>${escapeHtml(location.name)}</h3><span class="location-status">${location.status === 'open' ? '开放中' : '暂不可用'}</span></div><p>${escapeHtml(location.description)}</p><div class="location-meta"><span>${escapeHtml(meta.label)}</span><span>${Number(location.actionCount || 0)} 次参与</span></div></div><div class="location-actions"><button class="location-action secondary" data-location-item="${escapeHtml(location.id)}" ${!itemLocation || location.status !== 'open' ? 'hidden' : ''}>登记旧物</button><button class="location-action" data-location-action="${escapeHtml(location.id)}" ${location.status !== 'open' ? 'disabled' : ''}>去行动</button></div></article>`;
}

function mapMarker(location, mini = false) {
  const meta = LOCATION_META[location.type] || { icon: '•', color: 'green' };
  const position = location.mapPosition || { x: 50, y: 50 };
  return `<button class="map-marker ${meta.color} ${state.selectedLocationId === location.id ? 'selected' : ''} ${mini ? 'mini' : ''}" style="left:${Number(position.x) || 50}%;top:${Number(position.y) || 50}%" data-location-select="${escapeHtml(location.id)}" aria-label="${escapeHtml(location.name)}"><span>${meta.icon}</span>${mini ? '' : `<small>${escapeHtml(location.name)}</small>`}</button>`;
}

function campusMapMarkup(locations, mini = false) {
  return `<div class="map-ground"><div class="map-quad map-quad-a"></div><div class="map-quad map-quad-b"></div><div class="map-quad map-quad-c"></div><div class="map-quad map-quad-d"></div><div class="map-road road-horizontal"></div><div class="map-road road-vertical"></div><div class="map-path path-diagonal"></div><div class="map-greenway"></div><span class="map-label label-library">图书馆</span><span class="map-label label-dorm">生活区</span><span class="map-label label-field">体育场</span><span class="map-label label-gate">南门</span>${locations.map((location) => mapMarker(location, mini)).join('')}</div>`;
}

function renderCampusOverview() {
  const summary = state.campusSummary;
  const team = state.teams.find((item) => item.id === state.user?.teamId) || state.teams[0];
  $('#campusOverview').innerHTML = `<div class="campus-number"><strong>${format(summary.totalReductionKg)}</strong><span>kg CO₂e</span><small>校园累计估算减排</small></div><div class="campus-stats"><div><strong>${Number(summary.participantCount || 0)}</strong><span>位行动者</span></div><div><strong>${Number(summary.actionCount || 0)}</strong><span>次行动</span></div><div><strong>${Number(summary.activeLocationCount || 0)}</strong><span>个开放点位</span></div></div>${state.pendingActions.length ? `<div class="pending-note">${state.pendingActions.length} 条行动等待联网同步</div>` : ''}${team ? `<div class="team-progress"><div><span>${escapeHtml(team.name)}</span><b>${Number(team.actionCount || 0)} 次行动</b></div><div class="team-progress-track"><span style="width:${Math.min(100, Number(team.actionCount || 0) * 8)}%"></span></div><small>团队累计减排 ${format(team.totalReductionKg)} kg CO₂e</small></div>` : ''}`;
  $('#campusMiniMap').innerHTML = campusMapMarkup(state.locations, true);
}

function renderMap() {
  const visibleLocations = state.locations.filter((location) => state.locationFilter === 'all' || location.type === state.locationFilter || (state.locationFilter === 'recycle' && location.type === 'exchange'));
  $('#campusMap').innerHTML = campusMapMarkup(visibleLocations);
  $('#locationList').innerHTML = visibleLocations.map(locationCard).join('');
  $$('#locationFilters [data-location-filter]').forEach((button) => button.classList.toggle('active', button.dataset.locationFilter === state.locationFilter));
}

function renderChart() {
  const values = Array.from({ length: 7 }, (_, offset) => {
    const date = new Date();
    date.setDate(date.getDate() - (6 - offset));
    const key = dateKey(date);
    return state.records.filter((item) => dateKey(item.occurredAt) === key).reduce((sum, item) => sum + item.reductionKg, 0);
  });
  const max = Math.max(...values, 1);
  $('#weeklyChart').innerHTML = values.map((value, index) => `<div class="bar-wrap"><div class="bar ${index === values.length - 1 ? 'current' : ''}" style="height:${Math.max(12, (value / max) * 100)}%" title="${value.toFixed(2)} kg"></div></div>`).join('');
}

function challengeView(challenge) {
  const progress = Number(challenge.progress || 0);
  const percentage = Math.min(100, challenge.target ? (progress / challenge.target) * 100 : 0);
  return { ...challenge, tag: challenge.active === false ? '已结束' : '进行中', days: challenge.active === false ? '已结束' : '校园挑战', title: challenge.name, progress: percentage, progressText: `${format(progress)} / ${format(challenge.target)} ${challenge.unit}` };
}

function challengeCard(source, featured = false) {
  const challenge = challengeView(source);
  const joined = !!challenge.joined;
  return `<article class="challenge-card ${featured ? 'featured' : ''}"><div><div class="challenge-meta"><span>${escapeHtml(challenge.tag)}</span><span>${escapeHtml(challenge.days)}</span></div><h${featured ? '3' : '2'}>${escapeHtml(challenge.title)}</h${featured ? '3' : '2'}><p>${escapeHtml(challenge.description)}</p></div><div><div class="progress-line"><span style="width:${Math.min(100, Number(challenge.progress) || 0)}%"></span></div><div class="challenge-actions"><strong>${escapeHtml(challenge.progressText)}</strong><button class="join-button ${joined ? 'joined' : ''}" data-challenge="${escapeHtml(challenge.id)}" ${joined || challenge.active === false ? 'disabled' : ''}>${joined ? '已加入' : challenge.active === false ? '已结束' : '加入挑战'}</button></div></div></article>`;
}

function renderChallenges() {
  const first = state.challenges[0];
  $('#featuredChallenge').innerHTML = first ? challengeCard(first, true) : '<p class="empty-state">暂无进行中的挑战</p>';
  $('#challengeList').innerHTML = state.challenges.length ? state.challenges.map((item) => challengeCard(item)).join('') : '<p class="empty-state">暂无挑战</p>';
}

function formatDate(value) {
  if (!value) return '未知时间';
  return new Date(value).toLocaleString('zh-CN', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function renderRecords() {
  $('#recordList').innerHTML = state.records.length ? state.records.map((item) => {
    const factor = state.factors[item.factorId] || { label: item.factorId, unit: '', icon: '' };
    return `<div class="record-item"><div class="record-icon">${ICONS[item.factorId] || '·'}</div><div class="record-main"><b>${escapeHtml(factor.label)}</b><small>${escapeHtml(item.amount)} ${escapeHtml(factor.unit)} · ${escapeHtml(formatDate(item.occurredAt))}</small></div><div class="record-value">-${format(item.reductionKg)} kg<small>+${Number(item.points || 0)} 积分</small></div></div>`;
  }).join('') : '<p class="empty-state">还没有记录，先完成一次低碳行为吧。</p>';
}

const FLOW_META = { exchange: ['↔', '二手交换'], donate: ['♡', '捐赠'], repair: ['⌁', '维修再用'], recycle: ['♻', '回收'] };

function renderItems() {
  const container = $('#itemCardList');
  if (!container) return;
  container.innerHTML = state.items.length ? state.items.map((item) => {
    const [icon, label] = FLOW_META[item.flow] || ['•', item.flow];
    return `<article class="item-card"><div class="item-card-icon">${icon}</div><div class="item-card-copy"><div class="item-card-heading"><h3>${escapeHtml(item.title)}</h3><span>${escapeHtml(item.status)}</span></div><p>${escapeHtml(item.itemType)} · ${escapeHtml(item.weightKg)} kg · ${Number(item.cycleCount || 0)} 次流转</p><div class="item-card-foot"><span>避免约 ${format(item.reductionKg)} kg CO₂e</span><b>+${Number(item.points || 0)} 分</b></div><div class="item-timeline"><span class="timeline-dot"></span><small>已登记 · ${escapeHtml(label)}</small><span class="timeline-line"></span><small>${item.events?.length > 1 ? `最近更新 ${escapeHtml(formatDate(item.updatedAt))}` : '等待下一次流转'}</small></div><div class="item-card-actions"><select class="item-next-flow" data-item-flow="${escapeHtml(item.id)}"><option value="exchange">转为交换</option><option value="donate">转为捐赠</option><option value="repair">转为维修</option><option value="recycle">转为回收</option></select><button class="item-event-button" data-item-event="${escapeHtml(item.id)}">更新流转</button></div></div></article>`;
  }).join('') : '<p class="empty-state">还没有物品卡片。让一本旧书或一件闲置物品开始它的第二人生吧。</p>';
}

function renderItemLocations() {
  const select = $('#itemLocation');
  if (!select) return;
  const selected = state.selectedLocationId || select.value;
  select.innerHTML = '<option value="">不关联点位</option>' + state.locations.filter((location) => ['recycle', 'exchange', 'repair', 'reuse'].includes(location.type)).map((location) => `<option value="${escapeHtml(location.id)}">${escapeHtml(location.name)}</option>`).join('');
  select.value = selected;
}

function updateCalculation() {
  const type = $('#behaviorType').value;
  const amount = Number($('#behaviorAmount').value || 0);
  const factor = state.factors[type] || LOCAL_FACTORS[type] || { unit: '', reductionKgPerUnit: 0, pointsPerUnit: 0 };
  $('#behaviorUnit').value = factor.unit;
  $('#calculatedReduction').textContent = factor.calculationStatus === 'behavior_only' ? '仅记录行为' : `${format(amount * factor.reductionKgPerUnit)} kg CO₂e`;
  $('#calculatedPoints').textContent = `+${Math.max(1, Math.round(amount * factor.pointsPerUnit))} 积分`;
}

function updateProfile() {
  const name = $('.profile-banner h1');
  const campus = $('.profile-banner p:last-child');
  if (name && state.user) name.textContent = state.user.nickname;
  if (campus && state.user) campus.textContent = state.user.campus;
}

function render() {
  renderMetrics();
  renderChart();
  renderChallenges();
  renderRecords();
  renderItems();
  renderItemLocations();
  renderMap();
  updateCalculation();
}

$$('[data-go]').forEach((button) => button.addEventListener('click', () => navigate(button.dataset.go)));
$('#behaviorType').addEventListener('change', updateCalculation);
$('#behaviorAmount').addEventListener('input', updateCalculation);
$('#profileShortcut').addEventListener('click', () => navigate('profile'));
$('#completeRecommendation').addEventListener('click', () => { $('#behaviorType').value = 'reusable'; $('#behaviorAmount').value = '1'; updateCalculation(); navigate('record'); showToast('已为你准备好推荐行为'); });
$('#locationFilters').addEventListener('click', (event) => {
  const button = event.target.closest('[data-location-filter]');
  if (!button) return;
  state.locationFilter = button.dataset.locationFilter;
  renderMap();
});
document.addEventListener('click', (event) => {
  const marker = event.target.closest('[data-location-select]');
  if (!marker) return;
  state.selectedLocationId = marker.dataset.locationSelect;
  renderMap();
});
document.addEventListener('click', (event) => {
  const itemButton = event.target.closest('[data-location-item]');
  if (itemButton) {
    state.selectedLocationId = itemButton.dataset.locationItem;
    navigate('profile');
    showToast('已选择校园点位，登记物品后会关联到此处');
    return;
  }
  const button = event.target.closest('[data-location-action]');
  if (!button) return;
  const location = state.locations.find((item) => item.id === button.dataset.locationAction);
  if (!location) return;
  state.selectedLocationId = location.id;
  const factorId = location.actionFactorIds.find((id) => state.factors[id]);
  if (!factorId) return showToast('这个点位暂未开放线上记录');
  $('#behaviorType').value = factorId;
  $('#behaviorAmount').value = factorId === 'recycle' ? '1' : '1';
  navigate('record');
  $('#recordForm').dataset.locationId = location.id;
  showToast(`正在记录：${location.name}`);
});
$('#recordForm').addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const factorId = $('#behaviorType').value;
  const amount = Number($('#behaviorAmount').value || 0);
  if (!Number.isFinite(amount) || amount <= 0) return showToast('请输入有效的行为数量');
  const submit = $('button[type="submit"]', form);
  submit.disabled = true;
  const locationId = form.dataset.locationId || '';
  const action = { clientActionId: clientId(), factorId, amount, locationId, occurredAt: new Date().toISOString() };
  try {
    if (!state.ready) throw new Error('offline');
    await request('/api/v1/actions', { method: 'POST', body: JSON.stringify(action) });
    delete form.dataset.locationId;
    await refresh();
    showToast(`已记录 ${state.factors[factorId].label}`);
    navigate('home');
  } catch (error) {
    state.pendingActions.push(action);
    savePendingActions();
    render();
    showToast('当前离线，行动已保存到待同步队列');
  } finally {
    submit.disabled = false;
  }
});
window.addEventListener('online', async () => {
  await flushPendingActions();
  try {
    await refresh();
    showToast('待同步行动已更新');
  } catch (error) {
    showToast(`同步暂未完成：${error.message}`);
  }
});
document.addEventListener('click', async (event) => {
  const button = event.target.closest('[data-item-event]');
  if (!button || !state.ready) return;
  const itemId = button.dataset.itemEvent;
  const flow = $(`[data-item-flow="${itemId}"]`).value;
  button.disabled = true;
  try {
    await request(`/api/v1/items/${itemId}/cycle-events`, { method: 'POST', body: JSON.stringify({ type: flow }) });
    await refresh();
    showToast('物品流转已更新');
  } catch (error) {
    showToast(`更新失败：${error.message}`);
  } finally {
    button.disabled = false;
  }
});
document.addEventListener('click', async (event) => {
  const button = event.target.closest('[data-challenge]');
  if (!button || button.disabled || !state.ready) return;
  button.disabled = true;
  try {
    await request(`/api/v1/challenges/${button.dataset.challenge}/join`, { method: 'POST' });
    await refresh();
    showToast('已加入挑战');
  } catch (error) {
    button.disabled = false;
    showToast(`加入失败：${error.message}`);
  }
});
$('#itemForm').addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!state.ready) return showToast('后端未连接，暂时无法创建物品卡片');
  const form = event.currentTarget;
  const submit = $('button[type="submit"]', form);
  submit.disabled = true;
  try {
    await request('/api/v1/items', { method: 'POST', body: JSON.stringify({ clientItemId: clientId(), title: $('#itemTitle').value, itemType: $('#itemType').value, weightKg: Number($('#itemWeight').value), flow: $('#itemFlow').value, locationId: $('#itemLocation').value }) });
    form.reset();
    await refresh();
    showToast('第二人生卡片已生成');
  } catch (error) {
    showToast(`创建失败：${error.message}`);
  } finally {
    submit.disabled = false;
  }
});

render();
boot();
