import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_STORE_PATH = fileURLToPath(new URL('../data/store.json', import.meta.url));
const STORE_PATH = process.env.CARBON_STORE_PATH || DEFAULT_STORE_PATH;

const initialStore = {
  users: [],
  records: [],
  pointsLedger: [],
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
      users: Array.isArray(parsed.users) ? parsed.users : [],
      records: Array.isArray(parsed.records) ? parsed.records : [],
      pointsLedger: Array.isArray(parsed.pointsLedger) ? parsed.pointsLedger : [],
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
  await writeFile(temporaryPath, JSON.stringify(store, null, 2), 'utf8');
  await writeFile(STORE_PATH, await readFile(temporaryPath));
}

export function storePath() {
  return STORE_PATH;
}
