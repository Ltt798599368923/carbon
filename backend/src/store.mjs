import { mkdir, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_STORE_PATH = fileURLToPath(new URL('../data/store.json', import.meta.url));
const STORE_PATH = process.env.CARBON_STORE_PATH || DEFAULT_STORE_PATH;

const initialStore = {
  campuses: [{
    id: 'hafu-main',
    name: '郑州西亚斯学院',
    description: '校园低碳行动示范区',
    center: { lat: 34.806, lng: 113.55 }
  }],
  locations: [
    {
      id: 'location-recycle-east',
      campusId: 'hafu-main',
      type: 'recycle',
      name: '东区旧物回收点',
      description: '纸张、塑料、金属和可再利用物品',
      actionFactorIds: ['recycle'],
      status: 'open',
      qrCode: 'carbonloop://location/location-recycle-east',
      mapPosition: { x: 28, y: 38 }
    },
    {
      id: 'location-exchange-library',
      campusId: 'hafu-main',
      type: 'exchange',
      name: '图书馆二手交换角',
      description: '让旧书、教材和生活用品继续被使用',
      actionFactorIds: ['recycle'],
      status: 'open',
      qrCode: 'carbonloop://location/location-exchange-library',
      mapPosition: { x: 62, y: 25 }
    },
    {
      id: 'location-repair-studio',
      campusId: 'hafu-main',
      type: 'repair',
      name: '学生生活维修站',
      description: '小修小补，延长物品使用寿命',
      actionFactorIds: ['reusable'],
      status: 'open',
      qrCode: 'carbonloop://location/location-repair-studio',
      mapPosition: { x: 75, y: 62 }
    },
    {
      id: 'location-bike-gate',
      campusId: 'hafu-main',
      type: 'mobility',
      name: '南门绿色出行入口',
      description: '从南门开始一段步行或骑行路线',
      actionFactorIds: ['walk', 'transit'],
      status: 'open',
      qrCode: 'carbonloop://location/location-bike-gate',
      mapPosition: { x: 18, y: 72 }
    },
    {
      id: 'location-water-hall',
      campusId: 'hafu-main',
      type: 'reuse',
      name: '生活区饮水点',
      description: '自带水杯，减少一次性瓶装水',
      actionFactorIds: ['reusable'],
      status: 'open',
      qrCode: 'carbonloop://location/location-water-hall',
      mapPosition: { x: 48, y: 70 }
    }
  ],
  teams: [{
    id: 'team-dorm-302',
    campusId: 'hafu-main',
    name: '体验宿舍 302',
    type: 'dorm',
    description: '一起把宿舍变成低碳示范点'
  }],
  users: [],
  records: [],
  itemCycles: [],
  itemRequests: [],
  serviceOrders: [],
  messages: [],
  pointsLedger: [],
  rewards: [
    { id: 'badge-green-start', name: '绿色起点徽章', description: '完成第一笔低碳行为后可兑换的虚拟徽章。', cost: 10, kind: 'badge', code: 'green-start', limitPerUser: 1 },
    { id: 'tree-certificate', name: '校园植树证书', description: '用积分兑换一份 CarbonLoop 虚拟植树证书。', cost: 30, kind: 'certificate', code: 'tree-2026', limitPerUser: 1 },
    { id: 'badge-cycle-star', name: '循环之星徽章', description: '支持旧物循环和第二人生行动。', cost: 50, kind: 'badge', code: 'cycle-star', limitPerUser: 1 }
  ],
  redemptions: [],
  tasks: [{
    id: 'daily-reusable',
    name: '今日少用一次性用品',
    description: '完成一次可观察的重复使用行为。',
    factorIds: ['reusable'],
    target: 1,
    unit: '次',
    rewardPoints: 3,
    period: 'daily',
    active: true
  }],
  taskCompletions: [],
  challenges: [{
    id: 'walk-week-2026-10',
    name: '步行与骑行周',
    description: '本周累计完成 15 公里绿色出行。',
    type: 'distance',
    factorIds: ['walk'],
    target: 15,
    unit: '公里',
    reward: '绿色出发',
    startsAt: '2026-10-05T00:00:00.000Z',
    endsAt: '2026-12-31T23:59:59.999Z'
  }],
  challengeParticipants: []
};

export async function readStore() {
  try {
    const parsed = JSON.parse(await readFile(STORE_PATH, 'utf8'));
    return {
      ...structuredClone(initialStore),
      ...parsed,
      campuses: Array.isArray(parsed.campuses) ? parsed.campuses : structuredClone(initialStore.campuses),
      locations: Array.isArray(parsed.locations) ? parsed.locations : structuredClone(initialStore.locations),
      teams: Array.isArray(parsed.teams) ? parsed.teams : structuredClone(initialStore.teams),
      users: Array.isArray(parsed.users) ? parsed.users : [],
      records: Array.isArray(parsed.records) ? parsed.records : [],
      itemCycles: Array.isArray(parsed.itemCycles) ? parsed.itemCycles : [],
      itemRequests: Array.isArray(parsed.itemRequests) ? parsed.itemRequests : [],
      serviceOrders: Array.isArray(parsed.serviceOrders) ? parsed.serviceOrders : [],
      messages: Array.isArray(parsed.messages) ? parsed.messages : [],
      pointsLedger: Array.isArray(parsed.pointsLedger) ? parsed.pointsLedger : [],
      rewards: Array.isArray(parsed.rewards) ? parsed.rewards : structuredClone(initialStore.rewards),
      redemptions: Array.isArray(parsed.redemptions) ? parsed.redemptions : [],
      tasks: Array.isArray(parsed.tasks) ? parsed.tasks : structuredClone(initialStore.tasks),
      taskCompletions: Array.isArray(parsed.taskCompletions) ? parsed.taskCompletions : [],
      challenges: Array.isArray(parsed.challenges) ? parsed.challenges : structuredClone(initialStore.challenges),
      challengeParticipants: Array.isArray(parsed.challengeParticipants) ? parsed.challengeParticipants : []
    };
  } catch {
    await writeStore(structuredClone(initialStore));
    return structuredClone(initialStore);
  }
}

export async function writeStore(store) {
  await mkdir(dirname(STORE_PATH), { recursive: true });
  const temporaryPath = `${STORE_PATH}.tmp`;
  const serialized = JSON.stringify(store, null, 2);
  await writeFile(temporaryPath, serialized, 'utf8');
  try {
    await rename(temporaryPath, STORE_PATH);
  } catch (error) {
    // Windows cannot replace an existing file with rename; retain a safe fallback.
    await writeFile(STORE_PATH, serialized, 'utf8');
    await unlink(temporaryPath).catch(() => {});
  }
}

export function storePath() {
  return STORE_PATH;
}
