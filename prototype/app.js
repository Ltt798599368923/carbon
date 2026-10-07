const factors = {
  walk: { label: '步行 / 骑行出行', unit: '公里', factor: 0.2, icon: '🚲', points: 2 },
  transit: { label: '公交 / 地铁出行', unit: '公里', factor: 0.08, icon: '🚌', points: 1 },
  recycle: { label: '旧物回收', unit: '公斤', factor: 0.45, icon: '♻', points: 4 },
  energy: { label: '节约用电', unit: '度', factor: 0.57, icon: '⚡', points: 3 },
  reusable: { label: '减少一次性用品', unit: '次', factor: 0.06, icon: '🥤', points: 6 },
};

const initialRecords = [
  { type: 'walk', amount: 3, reduction: 0.6, points: 6, time: '今天 08:40' },
  { type: 'reusable', amount: 2, reduction: 0.12, points: 12, time: '昨天 12:20' },
  { type: 'recycle', amount: 1.5, reduction: 0.68, points: 6, time: '昨天 09:10' },
  { type: 'transit', amount: 8, reduction: 0.64, points: 8, time: '周一 17:30' },
];

const state = {
  records: JSON.parse(localStorage.getItem('carbonloop-records') || 'null') || initialRecords,
  joined: JSON.parse(localStorage.getItem('carbonloop-joined') || 'null') || {},
  currentView: 'home',
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const format = (value) => Number(value).toFixed(2);
const totals = () => state.records.reduce((acc, item) => ({ reduction: acc.reduction + item.reduction, points: acc.points + item.points }), { reduction: 0, points: 0 });

function saveState() {
  localStorage.setItem('carbonloop-records', JSON.stringify(state.records));
  localStorage.setItem('carbonloop-joined', JSON.stringify(state.joined));
}

function showToast(message) {
  const toast = $('#toast');
  toast.textContent = message;
  toast.classList.add('show');
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => toast.classList.remove('show'), 2400);
}

function navigate(view) {
  state.currentView = view;
  $$('.view').forEach((node) => node.classList.toggle('active', node.dataset.view === view));
  $$('.nav-item').forEach((node) => node.classList.toggle('active', node.dataset.go === view));
  window.scrollTo({ top: 0, behavior: 'smooth' });
  render();
}

function metricCard(label, value, unit, foot) {
  return `<article class="metric-card"><div class="metric-label">${label}</div><div class="metric-value">${value}<span class="metric-unit">${unit}</span></div><div class="metric-foot">${foot}</div></article>`;
}

function renderMetrics() {
  const total = totals();
  const today = state.records.filter((item) => item.time.startsWith('今天')).reduce((sum, item) => sum + item.reduction, 0);
  const metrics = [
    metricCard('今日减排', format(today), 'kg', '较昨日 +12.4%'),
    metricCard('本月累计', format(total.reduction + 11.84), 'kg', '超过 68% 的同学'),
    metricCard('碳积分', `${total.points + 214}`, '分', '距离下一级还差 86 分'),
  ];
  $('#metricGrid').innerHTML = metrics.join('');
  $('#profileMetrics').innerHTML = [metricCard('累计减排', format(total.reduction + 11.84), 'kg', '坚持就是改变'), metricCard('完成行为', `${state.records.length + 18}`, '次', '本月持续增长'), metricCard('参与挑战', '2', '个', '已完成 1 个')].join('');
}

function renderChart() {
  const values = [1.2, 2.2, 1.6, 2.9, 2.4, 3.2, Math.max(2.8, totals().reduction)];
  const max = Math.max(...values);
  $('#weeklyChart').innerHTML = values.map((value, index) => `<div class="bar-wrap"><div class="bar ${index === values.length - 1 ? 'current' : ''}" style="height:${Math.max(12, (value / max) * 100)}%" title="${value.toFixed(1)} kg"></div></div>`).join('');
}

function challengeCard(challenge, featured = false) {
  const joined = !!state.joined[challenge.id];
  return `<article class="challenge-card ${featured ? 'featured' : ''}"><div><div class="challenge-meta"><span>${challenge.tag}</span><span>${challenge.days}</span></div><h${featured ? '3' : '2'}>${challenge.title}</h${featured ? '3' : '2'}><p>${challenge.description}</p></div><div><div class="progress-line"><span style="width:${challenge.progress}%"></span></div><div class="challenge-actions"><strong>${challenge.progressText}</strong><button class="join-button ${joined ? 'joined' : ''}" data-challenge="${challenge.id}">${joined ? '已加入' : '加入挑战'}</button></div></div></article>`;
}

const challenges = [
  { id: 'bike7', tag: '绿色出行', days: '7 天挑战', title: '骑行与步行周', description: '本周累计完成 15 公里绿色出行。', progress: 64, progressText: '已完成 9.6 / 15 km' },
  { id: 'less-plastic', tag: '减塑生活', days: '连续 5 天', title: '自带餐具行动', description: '减少一次性餐具，让每次就餐更轻盈。', progress: 40, progressText: '已完成 2 / 5 天' },
  { id: 'energy-room', tag: '节能宿舍', days: '本月挑战', title: '宿舍节电先锋', description: '记录节电行为，为宿舍赢取绿色积分。', progress: 78, progressText: '宿舍排名第 6' },
  { id: 'recycle', tag: '循环利用', days: '长期任务', title: '回收新星计划', description: '完成 10 次回收，解锁专属徽章。', progress: 50, progressText: '已完成 5 / 10 次' },
];

function renderChallenges() {
  $('#featuredChallenge').innerHTML = challengeCard(challenges[0], true);
  $('#challengeList').innerHTML = challenges.map((item) => challengeCard(item)).join('');
}

function renderRecords() {
  $('#recordList').innerHTML = state.records.map((item) => {
    const factor = factors[item.type];
    return `<div class="record-item"><div class="record-icon">${factor.icon}</div><div class="record-main"><b>${factor.label}</b><small>${item.amount} ${factor.unit} · ${item.time}</small></div><div class="record-value">-${format(item.reduction)} kg<small>+${item.points} 积分</small></div></div>`;
  }).join('');
}

function updateCalculation() {
  const type = $('#behaviorType').value;
  const amount = Number($('#behaviorAmount').value || 0);
  const factor = factors[type];
  $('#behaviorUnit').value = factor.unit;
  $('#calculatedReduction').textContent = `${format(amount * factor.factor)} kg CO₂e`;
  $('#calculatedPoints').textContent = `+${Math.max(1, Math.round(amount * factor.points))} 积分`;
}

function render() {
  renderMetrics();
  renderChart();
  renderChallenges();
  renderRecords();
  updateCalculation();
}

$$('[data-go]').forEach((button) => button.addEventListener('click', () => navigate(button.dataset.go)));
$('#behaviorType').addEventListener('change', updateCalculation);
$('#behaviorAmount').addEventListener('input', updateCalculation);
$('#profileShortcut').addEventListener('click', () => navigate('profile'));
$('#completeRecommendation').addEventListener('click', () => { $('#behaviorType').value = 'reusable'; $('#behaviorAmount').value = '1'; updateCalculation(); navigate('record'); showToast('已为你准备好推荐行为'); });
$('#recordForm').addEventListener('submit', (event) => {
  event.preventDefault();
  const type = $('#behaviorType').value;
  const amount = Number($('#behaviorAmount').value || 0);
  const factor = factors[type];
  if (!amount || amount <= 0) return showToast('请输入有效的行为数量');
  state.records.unshift({ type, amount, reduction: amount * factor.factor, points: Math.max(1, Math.round(amount * factor.points)), time: '刚刚' });
  saveState(); render(); showToast(`已记录 ${factor.label}，获得 ${Math.max(1, Math.round(amount * factor.points))} 个积分`); navigate('home');
});
document.addEventListener('click', (event) => {
  const button = event.target.closest('[data-challenge]');
  if (!button) return;
  const id = button.dataset.challenge;
  state.joined[id] = true; saveState(); render(); showToast('已加入挑战，一起完成低碳目标吧！');
});

render();
