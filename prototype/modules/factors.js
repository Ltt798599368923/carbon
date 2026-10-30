export const ICONS = {
  walk: '🚲',
  transit: '🚌',
  recycle: '♻',
  energy: '⚡',
  reusable: '🥤',
  water: '💧',
  meal: '🍽️',
};

export const LOCAL_FACTORS = {
  walk: { label: '步行 / 骑行出行', unit: '公里', reductionKgPerUnit: 0.2, pointsPerUnit: 2, calculationStatus: 'estimated_demo' },
  transit: { label: '公交 / 地铁出行', unit: '公里', reductionKgPerUnit: 0.08, pointsPerUnit: 1, calculationStatus: 'estimated_demo' },
  recycle: { label: '旧物回收', unit: '公斤', reductionKgPerUnit: 0.45, pointsPerUnit: 4, calculationStatus: 'estimated_demo' },
  energy: { label: '节约用电', unit: '度', reductionKgPerUnit: 0.57, pointsPerUnit: 3, calculationStatus: 'estimated_demo' },
  reusable: { label: '减少一次性用品', unit: '次', reductionKgPerUnit: 0.06, pointsPerUnit: 6, calculationStatus: 'estimated_demo' },
  water: { label: '节约用水', unit: '次', reductionKgPerUnit: 0, pointsPerUnit: 1, calculationStatus: 'behavior_only' },
  meal: { label: '光盘行动', unit: '次', reductionKgPerUnit: 0, pointsPerUnit: 2, calculationStatus: 'behavior_only' },
};
