import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { CarbonRecord, findFactor } from '../model/CarbonModel';

export interface CarbonBackup {
  format: string;
  schemaVersion: number;
  exportedAt: string;
  data: CarbonBackupData;
}

export interface CarbonBackupData {
  records: CarbonRecord[];
  challengeJoined: boolean;
}

export function createCarbonBackup(records: CarbonRecord[], challengeJoined: boolean): string {
  const backup: CarbonBackup = {
    format: 'carbonloop-backup',
    schemaVersion: 1,
    exportedAt: new Date().toISOString(),
    data: {
      records,
      challengeJoined
    }
  };
  return JSON.stringify(backup, null, 2);
}

export function parseCarbonBackup(text: string): CarbonBackup {
  const parsed: Object = JSON.parse(text) as Object;
  const candidate: CarbonBackup = parsed as CarbonBackup;
  if (candidate.format !== 'carbonloop-backup' || candidate.schemaVersion !== 1 || candidate.data === undefined || !Array.isArray(candidate.data.records)) {
    throw new Error('不是可识别的 CarbonLoop 备份文件');
  }
  const records: CarbonRecord[] = [];
  for (const record of candidate.data.records) {
    if (record === undefined || typeof record.id !== 'string' || typeof record.factorId !== 'string' || typeof record.amount !== 'number' || !Number.isFinite(record.amount) || record.amount <= 0) {
      throw new Error('备份中包含无效行为记录');
    }
    const factor = findFactor(record.factorId);
    if (factor.id !== record.factorId) {
      throw new Error(`备份包含未知行为类型：${record.factorId}`);
    }
    records.push({
      id: record.id,
      factorId: record.factorId,
      factorVersion: typeof record.factorVersion === 'string' ? record.factorVersion : factor.version,
      amount: record.amount,
      occurredAt: typeof record.occurredAt === 'string' ? record.occurredAt : record.createdAt,
      createdAt: typeof record.createdAt === 'string' ? record.createdAt : new Date().toISOString(),
      reductionKg: Number.isFinite(record.reductionKg) ? record.reductionKg : 0,
      points: Number.isFinite(record.points) ? record.points : 0,
      verificationStatus: record.verificationStatus === 'location_verified' ? 'location_verified' : 'self_reported',
      locationId: record.locationId,
      syncStatus: 'pending',
      syncOperation: 'create'
    });
  }
  return {
    format: 'carbonloop-backup',
    schemaVersion: 1,
    exportedAt: typeof candidate.exportedAt === 'string' ? candidate.exportedAt : new Date().toISOString(),
    data: {
      records,
      challengeJoined: candidate.data.challengeJoined === true
    }
  };
}

export function mergeCarbonRecords(existing: CarbonRecord[], incoming: CarbonRecord[]): CarbonRecord[] {
  const merged: Map<string, CarbonRecord> = new Map<string, CarbonRecord>();
  for (const record of existing) {
    merged.set(record.id, record);
  }
  for (const record of incoming) {
    if (!merged.has(record.id)) {
      merged.set(record.id, record);
    }
  }
  return Array.from(merged.values()).sort((left: CarbonRecord, right: CarbonRecord) => {
    return new Date(right.occurredAt || right.createdAt).getTime() - new Date(left.occurredAt || left.createdAt).getTime();
  });
}

function csvCell(value: string | number): string {
  const text: string = '' + value;
  return '"' + text.replace(/"/g, '""') + '"';
}

export function createRecordsCsv(records: CarbonRecord[]): string {
  const header: string[] = ['记录编号', '发生时间', '行为类别', '数量', '单位', '估算减排量(kg CO2e)', '积分', '因子版本', '数据状态'];
  const rows: string[] = [header.map((value: string) => csvCell(value)).join(',')];
  for (const record of records) {
    const factor = findFactor(record.factorId);
    const status: string = record.verificationStatus === 'location_verified' ? '点位确认' : '用户自报';
    const fields: Array<string | number> = [
      record.id,
      record.occurredAt || record.createdAt,
      factor.label,
      record.amount,
      factor.unit,
      Number(record.reductionKg.toFixed(4)),
      record.points,
      record.factorVersion,
      status
    ];
    rows.push(fields.map((value: string | number) => csvCell(value)).join(','));
  }
  return '\uFEFF' + rows.join('\r\n');
}

export async function saveTextWithPicker(
  context: common.UIAbilityContext,
  fileName: string,
  suffix: string,
  content: string
): Promise<boolean> {
  const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
  options.newFileNames = [fileName];
  options.fileSuffixChoices = [suffix.toUpperCase() + ' (*.' + suffix + ')|' + suffix];
  const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
  const uris: Array<string> = await documentPicker.save(options);
  if (uris.length === 0) {
    return false;
  }
  const file = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(file.fd, content, { encoding: 'utf-8' });
  } finally {
    fileIo.closeSync(file);
  }
  return true;
}

export async function readBackupWithPicker(context: common.UIAbilityContext): Promise<string | null> {
  const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
  options.fileSuffixFilters = ['.json'];
  const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
  const uris: Array<string> = await documentPicker.select(options);
  if (uris.length === 0) {
    return null;
  }
  return fileIo.readTextSync(uris[0], { encoding: 'utf-8' });
}
