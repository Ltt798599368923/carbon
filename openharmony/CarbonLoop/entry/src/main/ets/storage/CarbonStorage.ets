import { preferences } from '@kit.ArkData';
import { CarbonRecord, findFactor } from '../model/CarbonModel';

const RECORDS_KEY: string = 'carbon_records_v1';
const CHALLENGE_KEY: string = 'challenge_joined_v1';
const DEVICE_ID_KEY: string = 'backend_device_id_v1';
const TOKEN_KEY: string = 'backend_token_v1';
const DELETED_RECORDS_KEY: string = 'carbon_deleted_records_v1';

export function loadRecords(store: preferences.Preferences | null): CarbonRecord[] | null {
  if (store === null) {
    return null;
  }
  const value: preferences.ValueType = store.getSync(RECORDS_KEY, '');
  if (typeof value !== 'string' || value.length === 0) {
    return null;
  }
  try {
    const parsed: Object = JSON.parse(value);
    if (Array.isArray(parsed)) {
      const saved: CarbonRecord[] = parsed as CarbonRecord[];
      return saved.map((record: CarbonRecord): CarbonRecord => {
        const factor = findFactor(record.factorId);
        const recordedAt: string = typeof record.occurredAt === 'string' ? record.occurredAt :
          typeof record.createdAt === 'string' && !Number.isNaN(new Date(record.createdAt).getTime()) ? record.createdAt : '';
        return {
          id: record.id,
          factorId: record.factorId,
          amount: record.amount,
          reductionKg: record.reductionKg,
          points: record.points,
          createdAt: record.createdAt,
          factorVersion: typeof record.factorVersion === 'string' ? record.factorVersion : factor.version,
          occurredAt: recordedAt,
          verificationStatus: record.verificationStatus === 'location_verified' ? 'location_verified' : 'self_reported',
          locationId: record.locationId,
          syncStatus: record.syncStatus === 'synced' ? 'synced' : 'pending',
          syncOperation: record.syncOperation === 'update' ? 'update' : 'create'
        };
      });
    }
  } catch (error) {
    console.error(`CarbonLoop failed to parse saved records: ${error}`);
  }
  return null;
}

export function updateRecordSyncStatus(store: preferences.Preferences | null, records: CarbonRecord[], recordId: string, status: 'pending' | 'synced'): CarbonRecord[] {
  const updated: CarbonRecord[] = records.map((record: CarbonRecord): CarbonRecord => {
    if (record.id !== recordId) {
      return record;
    }
    return {
      id: record.id,
      factorId: record.factorId,
      factorVersion: record.factorVersion,
      amount: record.amount,
      reductionKg: record.reductionKg,
      points: record.points,
      occurredAt: record.occurredAt,
      createdAt: record.createdAt,
      verificationStatus: record.verificationStatus,
      locationId: record.locationId,
      syncStatus: status,
      syncOperation: record.syncOperation
    };
  });
  saveRecords(store, updated);
  return updated;
}

export function saveRecords(store: preferences.Preferences | null, records: CarbonRecord[]): void {
  if (store === null) {
    return;
  }
  store.putSync(RECORDS_KEY, JSON.stringify(records));
  store.flush().catch((error: Error) => {
    console.error(`CarbonLoop failed to flush records: ${error.message}`);
  });
}

export function loadDeletedRecordIds(store: preferences.Preferences | null): string[] {
  if (store === null) {
    return [];
  }
  const value: preferences.ValueType = store.getSync(DELETED_RECORDS_KEY, '[]');
  if (typeof value !== 'string') {
    return [];
  }
  try {
    const parsed: Object = JSON.parse(value);
    return Array.isArray(parsed) ? parsed as string[] : [];
  } catch {
    return [];
  }
}

export function saveDeletedRecordIds(store: preferences.Preferences | null, ids: string[]): void {
  if (store === null) {
    return;
  }
  store.putSync(DELETED_RECORDS_KEY, JSON.stringify(ids));
  store.flush().catch((error: Error) => {
    console.error(`CarbonLoop failed to flush deleted record ids: ${error.message}`);
  });
}

export function loadChallengeJoined(store: preferences.Preferences | null): boolean {
  if (store === null) {
    return false;
  }
  const value: preferences.ValueType = store.getSync(CHALLENGE_KEY, false);
  return typeof value === 'boolean' ? value : false;
}

export function saveChallengeJoined(store: preferences.Preferences | null, joined: boolean): void {
  if (store === null) {
    return;
  }
  store.putSync(CHALLENGE_KEY, joined);
  store.flush().catch((error: Error) => {
    console.error(`CarbonLoop failed to flush challenge state: ${error.message}`);
  });
}

export function loadDeviceId(store: preferences.Preferences | null): string | null {
  if (store === null) {
    return null;
  }
  const value: preferences.ValueType = store.getSync(DEVICE_ID_KEY, '');
  return typeof value === 'string' && value.length > 0 ? value : null;
}

export function saveDeviceId(store: preferences.Preferences | null, deviceId: string): void {
  if (store === null) {
    return;
  }
  store.putSync(DEVICE_ID_KEY, deviceId);
  store.flush().catch((error: Error) => {
    console.error(`CarbonLoop failed to flush device id: ${error.message}`);
  });
}

export function loadBackendToken(store: preferences.Preferences | null): string | null {
  if (store === null) {
    return null;
  }
  const value: preferences.ValueType = store.getSync(TOKEN_KEY, '');
  return typeof value === 'string' && value.length > 0 ? value : null;
}

export function saveBackendToken(store: preferences.Preferences | null, token: string): void {
  if (store === null) {
    return;
  }
  store.putSync(TOKEN_KEY, token);
  store.flush().catch((error: Error) => {
    console.error(`CarbonLoop failed to flush backend token: ${error.message}`);
  });
}
