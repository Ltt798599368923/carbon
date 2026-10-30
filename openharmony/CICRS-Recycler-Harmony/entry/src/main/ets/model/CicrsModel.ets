export type CicrsRole = 'student' | 'recycler' | 'admin';
export type CicrsItemStatus = 'DRAFT' | 'PENDING' | 'REJECTED' | 'APPROVED' | 'CANCELED' | 'BOOKED' | 'RECEIVED' | 'IN_STOCK' | 'RESERVED' | 'COMPLETED' | 'SCRAPPED';
export type TransferMethod = 'donate' | 'transfer' | 'recycle';
export type AppointmentType = 'delivery' | 'pickup';
export type AppointmentState = 'active' | 'used' | 'canceled' | 'expired';

export interface CicrsRules {
  basePointsPerKg: number;
  treeAbsorptionKgPerYear: number;
  maxPendingItems: number;
  appointmentCapacity: number;
}

export interface CicrsFactor {
  id: string;
  category: string;
  name: string;
  unit: string;
  value: number;
  source: string;
}

export interface CicrsFactorCatalog {
  rules: CicrsRules;
  conditionMultipliers: number[];
  transferMultipliers: number[];
  conditions: string[];
  transferMethods: string[];
  factors: CicrsFactor[];
}

export interface CicrsStatusEvent {
  status: CicrsItemStatus;
  actor: string;
  note: string;
  createdAt: string;
}

export interface CicrsAppointment {
  type: AppointmentType;
  code: string;
  stationId: string;
  stationName: string;
  slot: string;
  slotStartsAt: string;
  expiresAt: string;
  state: AppointmentState;
  usedAt: string;
}

export interface CicrsItem {
  id: string;
  ownerId: string;
  ownerName: string;
  factorId: string;
  factorValue: number;
  factorSource: string;
  factorUnit: string;
  factorVersion: string;
  stationId: string;
  title: string;
  category: string;
  conditionLevel: number;
  verifiedConditionLevel: number;
  transferMethod: TransferMethod;
  quantity: number;
  estimatedWeightKg: number;
  actualWeightKg: number;
  description: string;
  imageUris: string[];
  status: CicrsItemStatus;
  statusEvents: CicrsStatusEvent[];
  appointment: CicrsAppointment | null;
  verificationRemark: string;
  shelfLocation: string;
  scrapReason: string;
  carbonSavedKg: number;
  score: number;
  scoreAwarded: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CicrsScoreRecord {
  id: string;
  itemId: string;
  ownerId: string;
  points: number;
  carbonSavedKg: number;
  balanceAfter: number;
  factorId: string;
  factorValue: number;
  quantity: number;
  conditionMultiplier: number;
  transferMultiplier: number;
  createdAt: string;
}

export interface CicrsStation {
  id: string;
  name: string;
  address: string;
  openHours: string;
  enabled: boolean;
}

export interface CicrsSnapshot {
  items: CicrsItem[];
  scoreRecords: CicrsScoreRecord[];
  nextCodeSeed: number;
  accessViolationCount: number;
}

export interface CicrsItemDraft {
  ownerId: string;
  ownerName: string;
  title: string;
  factorId: string;
  conditionLevel: number;
  transferMethod: TransferMethod;
  quantity: number;
  estimatedWeightKg: number;
  description: string;
  imageUris: string[];
}

export interface CicrsActionResult {
  ok: boolean;
  message: string;
  itemId: string;
}

export interface CicrsAccountSummary {
  points: number;
  carbonSavedKg: number;
  completedCount: number;
  treeEquivalent: number;
}

export interface CicrsCountSummary {
  pending: number;
  stock: number;
  booked: number;
  received: number;
  completed: number;
}

export interface CicrsStatusInfo {
  code: CicrsItemStatus;
  label: string;
  color: string;
}

export const CICRS_STATUSES: CicrsStatusInfo[] = [
  { code: 'DRAFT', label: '草稿', color: '#7B8782' },
  { code: 'PENDING', label: '待核验', color: '#B87921' },
  { code: 'REJECTED', label: '核验不通过', color: '#B34132' },
  { code: 'APPROVED', label: '已通过', color: '#2E7D59' },
  { code: 'CANCELED', label: '已取消', color: '#77827D' },
  { code: 'BOOKED', label: '待投递', color: '#3767A0' },
  { code: 'RECEIVED', label: '已收货', color: '#4B65A8' },
  { code: 'IN_STOCK', label: '在库', color: '#247A62' },
  { code: 'RESERVED', label: '已预约', color: '#9B691D' },
  { code: 'COMPLETED', label: '已流转', color: '#1C7558' },
  { code: 'SCRAPPED', label: '已报废', color: '#85635B' }
];

export const CICRS_STATIONS: CicrsStation[] = [
  { id: 'station-east', name: '东区旧物驿站', address: '生活区东侧服务点', openHours: '周一至周六 09:00–20:00', enabled: true },
  { id: 'station-library', name: '图书馆共享驿站', address: '图书馆一层服务台', openHours: '周一至周五 10:00–18:00', enabled: true }
];

export function findCicrsFactor(catalog: CicrsFactorCatalog, factorId: string): CicrsFactor {
  for (const factor of catalog.factors) {
    if (factor.id === factorId) {
      return factor;
    }
  }
  return catalog.factors[0];
}

export function statusInfo(status: CicrsItemStatus): CicrsStatusInfo {
  for (const item of CICRS_STATUSES) {
    if (item.code === status) {
      return item;
    }
  }
  return CICRS_STATUSES[0];
}

export function formatCicrsNumber(value: number, digits: number = 2): string {
  const safeValue: number = Number.isFinite(value) ? value : 0;
  return safeValue.toFixed(digits);
}

export function transferMethodLabel(method: TransferMethod): string {
  if (method === 'donate') {
    return '无偿捐赠';
  }
  if (method === 'transfer') {
    return '站内转让';
  }
  return '回收处置';
}

export function appointmentTypeLabel(type: AppointmentType): string {
  return type === 'delivery' ? '预约投递' : '预约领取';
}
