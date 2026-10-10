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
}

export interface CarbonRecord {
  id: string;
  factorId: string;
  amount: number;
  reductionKg: number;
  points: number;
  createdAt: string;
}

export const CARBON_FACTORS: CarbonFactor[] = [
  { id: 'walk', label: '步行 / 骑行出行', unit: '公里', icon: '🚲', reductionKgPerUnit: 0.2, pointsPerUnit: 2 },
  { id: 'transit', label: '公交 / 地铁出行', unit: '公里', icon: '🚌', reductionKgPerUnit: 0.08, pointsPerUnit: 1 },
  { id: 'recycle', label: '旧物回收', unit: '公斤', icon: '♻', reductionKgPerUnit: 0.45, pointsPerUnit: 4 },
  { id: 'energy', label: '节约用电', unit: '度', icon: '⚡', reductionKgPerUnit: 0.57, pointsPerUnit: 3 },
  { id: 'reusable', label: '减少一次性用品', unit: '次', icon: '🥤', reductionKgPerUnit: 0.06, pointsPerUnit: 6 }
];

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

export function formatKg(value: number): string {
  const safeValue: number = Number.isFinite(value) ? value : 0;
  return safeValue.toFixed(2);
}
