/**
 * CarbonLoop domain model.
 * Keep calculation rules independent from the UI so the same logic can be reused
 * by the phone, tablet and future distributed-sync layers.
 */
export interface CarbonFactor {
  id: string;
  label: string;
  unit: string;
  icon: string;
  reductionKgPerUnit: number;
  pointsPerUnit: number;
  version: string;
  source: string;
  baseline: string;
  calculationStatus: 'estimated_demo' | 'behavior_only';
}

export interface CarbonRecord {
  id: string;
  factorId: string;
  factorVersion: string;
  amount: number;
  reductionKg: number;
  points: number;
  occurredAt: string;
  createdAt: string;
  verificationStatus: 'self_reported' | 'location_verified';
  locationId?: string;
  syncStatus?: 'pending' | 'synced';
  syncOperation?: 'create' | 'update';
}

export const CARBON_FACTORS: CarbonFactor[] = [
  { id: 'walk', label: '步行 / 骑行出行', unit: '公里', icon: '行', reductionKgPerUnit: 0.2, pointsPerUnit: 2, version: '0.1.0', source: 'CarbonLoop 演示因子，待正式来源复核', baseline: '待核实：与燃油机动车出行的比较基准', calculationStatus: 'estimated_demo' },
  { id: 'transit', label: '公交 / 地铁出行', unit: '公里', icon: '轨', reductionKgPerUnit: 0.08, pointsPerUnit: 1, version: '0.1.0', source: 'CarbonLoop 演示因子，待正式来源复核', baseline: '待核实：与单人机动车出行的比较基准', calculationStatus: 'estimated_demo' },
  { id: 'recycle', label: '旧物回收', unit: '公斤', icon: '收', reductionKgPerUnit: 0.45, pointsPerUnit: 4, version: '0.1.0', source: 'CarbonLoop 演示因子，待正式来源复核', baseline: '待核实：按物品品类和去向区分的避免排放基准', calculationStatus: 'estimated_demo' },
  { id: 'energy', label: '节约用电', unit: '度', icon: '电', reductionKgPerUnit: 0.57, pointsPerUnit: 3, version: '0.1.0', source: 'CarbonLoop 演示因子，待正式来源复核', baseline: '待核实：适用电网区域和时间范围', calculationStatus: 'estimated_demo' },
  { id: 'reusable', label: '减少一次性用品', unit: '次', icon: '杯', reductionKgPerUnit: 0.06, pointsPerUnit: 6, version: '0.1.0', source: 'CarbonLoop 演示因子，待正式来源复核', baseline: '待核实：被替代的一次性用品类型', calculationStatus: 'estimated_demo' },
  { id: 'water', label: '节约用水', unit: '次', icon: '水', reductionKgPerUnit: 0, pointsPerUnit: 1, version: '0.1.0', source: '暂无已确认的 CarbonLoop 因子', baseline: '当前只记录行为，不量化减排', calculationStatus: 'behavior_only' },
  { id: 'meal', label: '光盘行动', unit: '次', icon: '餐', reductionKgPerUnit: 0, pointsPerUnit: 2, version: '0.1.0', source: '暂无已确认的 CarbonLoop 食物浪费因子', baseline: '当前只记录行为，不量化减排', calculationStatus: 'behavior_only' }
];

export type RecordPeriod = 'day' | 'week' | 'month' | 'year';

export interface RecordBucket {
  key: string;
  label: string;
  reductionKg: number;
  points: number;
  count: number;
}

export interface PeriodBounds {
  start: Date;
  end: Date;
}

export function findFactor(id: string): CarbonFactor {
  for (const factor of CARBON_FACTORS) {
    if (factor.id === id) {
      return factor;
    }
  }
  return CARBON_FACTORS[0];
}

export function calculateReduction(factor: CarbonFactor, amount: number): number {
  return Math.max(0, amount) * factor.reductionKgPerUnit;
}

export function calculatePoints(factor: CarbonFactor, amount: number): number {
  return Math.max(1, Math.round(Math.max(0, amount) * factor.pointsPerUnit));
}

export function recordDate(record: CarbonRecord): Date | null {
  const value: string = record.occurredAt || record.createdAt;
  const parsed: Date = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function pad(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}

function dateKey(date: Date): string {
  return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate());
}

export function getPeriodBounds(period: RecordPeriod, anchor: Date): PeriodBounds {
  const year: number = anchor.getFullYear();
  const month: number = anchor.getMonth();
  if (period === 'day') {
    const start: Date = new Date(year, month, anchor.getDate());
    return { start, end: new Date(year, month, anchor.getDate() + 1) };
  }
  if (period === 'week') {
    const start: Date = new Date(year, month, anchor.getDate());
    const mondayOffset: number = (start.getDay() + 6) % 7;
    start.setDate(start.getDate() - mondayOffset);
    return { start, end: new Date(start.getFullYear(), start.getMonth(), start.getDate() + 7) };
  }
  if (period === 'month') {
    return { start: new Date(year, month, 1), end: new Date(year, month + 1, 1) };
  }
  return { start: new Date(year, 0, 1), end: new Date(year + 1, 0, 1) };
}

export function filterRecordsForPeriod(records: CarbonRecord[], period: RecordPeriod, anchor: Date, factorId?: string): CarbonRecord[] {
  const bounds = getPeriodBounds(period, anchor);
  return records.filter((record: CarbonRecord) => {
    if (factorId !== undefined && record.factorId !== factorId) {
      return false;
    }
    const date: Date | null = recordDate(record);
    return date !== null && date.getTime() >= bounds.start.getTime() && date.getTime() < bounds.end.getTime();
  }).sort((left: CarbonRecord, right: CarbonRecord) => {
    const leftDate: Date | null = recordDate(left);
    const rightDate: Date | null = recordDate(right);
    return (rightDate?.getTime() ?? 0) - (leftDate?.getTime() ?? 0);
  });
}

export function buildTrendBuckets(records: CarbonRecord[], period: RecordPeriod, anchor: Date, factorId?: string): RecordBucket[] {
  const bounds = getPeriodBounds(period, anchor);
  const buckets: RecordBucket[] = [];
  if (period === 'day') {
    for (let hour: number = 0; hour < 24; hour += 1) {
      const key: string = dateKey(bounds.start) + 'T' + pad(hour);
      buckets.push({ key, label: pad(hour), reductionKg: 0, points: 0, count: 0 });
    }
  } else if (period === 'week' || period === 'month') {
    for (let day: Date = new Date(bounds.start); day.getTime() < bounds.end.getTime(); day.setDate(day.getDate() + 1)) {
      const key: string = dateKey(day);
      const label: string = period === 'week'
        ? ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][day.getDay()]
        : '' + day.getDate();
      buckets.push({ key, label, reductionKg: 0, points: 0, count: 0 });
    }
  } else {
    for (let month: number = 0; month < 12; month += 1) {
      const date: Date = new Date(bounds.start.getFullYear(), month, 1);
      const key: string = date.getFullYear() + '-' + pad(date.getMonth() + 1);
      buckets.push({ key, label: (month + 1) + '月', reductionKg: 0, points: 0, count: 0 });
    }
  }

  const bucketIndex: Map<string, number> = new Map<string, number>();
  for (let index: number = 0; index < buckets.length; index += 1) {
    bucketIndex.set(buckets[index].key, index);
  }
  const scopedRecords: CarbonRecord[] = filterRecordsForPeriod(records, period, anchor, factorId);
  for (const record of scopedRecords) {
    const date: Date | null = recordDate(record);
    if (date === null) {
      continue;
    }
    const key: string = period === 'day'
      ? dateKey(date) + 'T' + pad(date.getHours())
      : period === 'year'
        ? date.getFullYear() + '-' + pad(date.getMonth() + 1)
        : dateKey(date);
    const index: number | undefined = bucketIndex.get(key);
    if (index !== undefined) {
      buckets[index].reductionKg += record.reductionKg;
      buckets[index].points += record.points;
      buckets[index].count += 1;
    }
  }
  const rounded: RecordBucket[] = [];
  for (const bucket of buckets) {
    rounded.push({ key: bucket.key, label: bucket.label, reductionKg: Number(bucket.reductionKg.toFixed(4)), points: bucket.points, count: bucket.count });
  }
  return rounded;
}

export function periodDescription(period: RecordPeriod, anchor: Date): string {
  if (period === 'day') {
    return anchor.getFullYear() + '年' + (anchor.getMonth() + 1) + '月' + anchor.getDate() + '日';
  }
  if (period === 'week') {
    const bounds = getPeriodBounds(period, anchor);
    const last: Date = new Date(bounds.end);
    last.setDate(last.getDate() - 1);
    return (bounds.start.getMonth() + 1) + '月' + bounds.start.getDate() + '日—' +
      (last.getMonth() + 1) + '月' + last.getDate() + '日';
  }
  if (period === 'month') {
    return anchor.getFullYear() + '年' + (anchor.getMonth() + 1) + '月';
  }
  return anchor.getFullYear() + '年';
}

export function formatKg(value: number): string {
  const safeValue: number = Number.isFinite(value) ? value : 0;
  return safeValue.toFixed(2);
}
