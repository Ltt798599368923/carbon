import { preferences } from '@kit.ArkData';
import {
  AppointmentType,
  CicrsActionResult,
  CicrsAppointment,
  CicrsFactor,
  CicrsFactorCatalog,
  CicrsItem,
  CicrsItemDraft,
  CicrsItemStatus,
  CicrsScoreRecord,
  CicrsSnapshot,
  CicrsStation,
  CicrsStatusEvent,
  TransferMethod,
  CicrsAccountSummary,
  CicrsCountSummary,
  CICRS_STATIONS,
  findCicrsFactor
} from '../model/CicrsModel';

const SNAPSHOT_KEY: string = 'cicrs_snapshot_v1';
const ACTOR_STUDENT: string = 'student-demo';
const ACTOR_RECYCLER: string = 'recycler-east-demo';
const ACTOR_ADMIN: string = 'admin-demo';

function nowIso(): string {
  return new Date().toISOString();
}

function dayEndIso(reference: string = ''): string {
  const date = reference.length > 0 ? new Date(reference) : new Date();
  date.setHours(23, 59, 59, 999);
  return date.toISOString();
}

function codeText(seed: number): string {
  const codeNumber: number = 10000000 + (seed % 90000000);
  return `${codeNumber}`;
}

function makeEvent(status: CicrsItemStatus, actor: string, note: string, at: string): CicrsStatusEvent {
  const event: CicrsStatusEvent = { status, actor, note, createdAt: at };
  return event;
}

export class CicrsRepository {
  private store: preferences.Preferences | null = null;
  private catalog: CicrsFactorCatalog | null = null;
  private snapshot: CicrsSnapshot = { items: [], scoreRecords: [], nextCodeSeed: 31000000, accessViolationCount: 0 };

  public initialize(store: preferences.Preferences | null, catalog: CicrsFactorCatalog): void {
    this.store = store;
    this.catalog = catalog;
    let loaded: boolean = false;
    if (this.store !== null) {
      const saved: preferences.ValueType = this.store.getSync(SNAPSHOT_KEY, '');
      if (typeof saved === 'string' && saved.length > 0) {
        try {
          const parsed: CicrsSnapshot = JSON.parse(saved) as CicrsSnapshot;
          if (Array.isArray(parsed.items) && Array.isArray(parsed.scoreRecords)) {
            this.snapshot = {
              items: parsed.items,
              scoreRecords: parsed.scoreRecords,
              nextCodeSeed: parsed.nextCodeSeed ?? 31000000,
              accessViolationCount: parsed.accessViolationCount ?? 0
            };
            loaded = true;
          }
        } catch (error) {
          console.error(`CICRS local snapshot could not be parsed: ${error}`);
        }
      }
    }
    if (!loaded) {
      this.snapshot = this.createDemoSnapshot();
      this.save();
    }
    this.refreshExpirations();
  }

  public getCatalog(): CicrsFactorCatalog {
    if (this.catalog === null) {
      throw new Error('CICRS 碳因子配置尚未载入');
    }
    return this.catalog;
  }

  public getItems(): CicrsItem[] {
    return this.snapshot.items.slice();
  }

  public getScoreRecords(): CicrsScoreRecord[] {
    return this.snapshot.scoreRecords.slice();
  }

  public getItem(itemId: string): CicrsItem | null {
    return this.findItem(itemId);
  }

  public getItemByCode(code: string): CicrsItem | null {
    return this.findItemByCode(code.trim());
  }

  public getAccessViolationCount(): number {
    return this.snapshot.accessViolationCount;
  }

  public getStation(stationId: string): CicrsStation {
    for (const station of CICRS_STATIONS) {
      if (station.id === stationId) {
        return station;
      }
    }
    return CICRS_STATIONS[0];
  }

  public refreshExpirations(): void {
    const now: number = Date.now();
    let changed: boolean = false;
    for (const item of this.snapshot.items) {
      const appointment: CicrsAppointment | null = item.appointment;
      if (appointment !== null && appointment.state === 'active' && Date.parse(appointment.expiresAt) < now) {
        appointment.state = 'expired';
        appointment.usedAt = '';
        if (appointment.type === 'delivery' && item.status === 'BOOKED') {
          this.transition(item, 'APPROVED', 'system', '投递预约过期，物品退回可预约状态');
        } else if (appointment.type === 'pickup' && item.status === 'RESERVED') {
          this.transition(item, 'IN_STOCK', 'system', '领取预约过期，库存已释放');
        }
        changed = true;
      }
    }
    if (changed) {
      this.save();
    }
  }

  public createItem(draft: CicrsItemDraft): CicrsActionResult {
    if (this.catalog === null) {
      return this.result(false, '碳因子配置不可用，请重启应用。', '');
    }
    const title: string = draft.title.trim();
    if (title.length < 2 || title.length > 40) {
      return this.result(false, '物品名称需为 2–40 个字符。', '');
    }
    if (draft.imageUris.length < 1 || draft.imageUris.length > 6) {
      return this.result(false, '请添加 1–6 张物品照片。', '');
    }
    if (!Number.isFinite(draft.quantity) || draft.quantity < 1) {
      return this.result(false, '数量至少为 1。', '');
    }
    if (draft.estimatedWeightKg < 0) {
      return this.result(false, '估计重量不能为负数。', '');
    }
    const activeCount: number = this.countStatuses(draft.ownerId, ['DRAFT', 'PENDING', 'APPROVED']);
    if (activeCount >= this.catalog.rules.maxPendingItems) {
      return this.result(false, `待处理物品已达 ${this.catalog.rules.maxPendingItems} 件上限。`, '');
    }
    const factor: CicrsFactor = findCicrsFactor(this.catalog, draft.factorId);
    const id: string = `item-${Date.now()}-${this.snapshot.nextCodeSeed}`;
    const item: CicrsItem = {
      id,
      ownerId: draft.ownerId,
      ownerName: draft.ownerName,
      factorId: factor.id,
      factorValue: factor.value,
      factorSource: factor.source,
      factorUnit: factor.unit,
      factorVersion: 'catalog-demo-v1',
      stationId: '',
      title,
      category: factor.category,
      conditionLevel: draft.conditionLevel,
      verifiedConditionLevel: 0,
      transferMethod: draft.transferMethod,
      quantity: draft.quantity,
      estimatedWeightKg: draft.estimatedWeightKg,
      actualWeightKg: 0,
      description: draft.description.trim().slice(0, 300),
      imageUris: draft.imageUris.slice(),
      status: 'DRAFT',
      statusEvents: [makeEvent('DRAFT', draft.ownerName, '保存发布信息', nowIso())],
      appointment: null,
      verificationRemark: '',
      shelfLocation: '',
      scrapReason: '',
      carbonSavedKg: 0,
      score: 0,
      scoreAwarded: false,
      createdAt: nowIso(),
      updatedAt: nowIso()
    };
    this.snapshot.items = [item, ...this.snapshot.items];
    this.snapshot.nextCodeSeed += 1;
    this.transition(item, 'PENDING', draft.ownerName, '提交管理员核验');
    this.save();
    return this.result(true, '发布成功，物品已进入待核验队列。', item.id);
  }

  public approveItem(itemId: string): CicrsActionResult {
    const item: CicrsItem | null = this.findItem(itemId);
    if (item === null || item.status !== 'PENDING') {
      return this.result(false, '仅待核验物品可以通过审核。', itemId);
    }
    item.verificationRemark = '内容与图片已完成体验审核。';
    this.transition(item, 'APPROVED', '体验管理员', item.verificationRemark);
    this.save();
    return this.result(true, `${item.title} 已通过核验，可以预约投递。`, itemId);
  }

  public rejectItem(itemId: string, reason: string): CicrsActionResult {
    const item: CicrsItem | null = this.findItem(itemId);
    const remark: string = reason.trim();
    if (item === null || item.status !== 'PENDING') {
      return this.result(false, '仅待核验物品可以驳回。', itemId);
    }
    if (remark.length < 2) {
      return this.result(false, '请填写驳回意见。', itemId);
    }
    item.verificationRemark = remark;
    this.transition(item, 'REJECTED', '体验管理员', remark);
    this.save();
    return this.result(true, `${item.title} 已驳回，并记录了审核意见。`, itemId);
  }

  public book(itemId: string, type: AppointmentType, stationId: string, slot: string, slotStart: string): CicrsActionResult {
    const item: CicrsItem | null = this.findItem(itemId);
    if (item === null) {
      return this.result(false, '未找到这件物品。', itemId);
    }
    if (type === 'delivery' && item.status !== 'APPROVED') {
      return this.result(false, '只有已通过核验的物品可以预约投递。', itemId);
    }
    if (type === 'pickup' && item.status !== 'IN_STOCK') {
      return this.result(false, '这件物品暂不可预约领取。', itemId);
    }
    const station: CicrsStation = this.getStation(stationId);
    if (!station.enabled) {
      return this.result(false, '该驿站暂未开放预约。', itemId);
    }
    const capacity: number = this.countSlotAppointments(stationId, slot);
    if (this.catalog !== null && capacity >= this.catalog.rules.appointmentCapacity) {
      return this.result(false, '该时段预约已满，请选择其他时段。', itemId);
    }
    const code: string = this.nextUniqueCode();
    const appointment: CicrsAppointment = {
      type,
      code,
      stationId,
      stationName: station.name,
      slot,
      slotStartsAt: slotStart,
      expiresAt: dayEndIso(),
      state: 'active',
      usedAt: ''
    };
    item.appointment = appointment;
    item.stationId = stationId;
    if (type === 'delivery') {
      this.transition(item, 'BOOKED', '学生端', '预约投递，已生成 8 位核销码');
    } else {
      this.transition(item, 'RESERVED', '学生端', '预约领取，库存已锁定');
    }
    this.save();
    return this.result(true, `${type === 'delivery' ? '投递' : '领取'}预约成功，核销码 ${code}。`, itemId);
  }

  public cancelItem(itemId: string, actor: string): CicrsActionResult {
    const item: CicrsItem | null = this.findItem(itemId);
    if (item === null) {
      return this.result(false, '未找到这件物品。', itemId);
    }
    if (item.status === 'RESERVED' && item.appointment !== null && item.appointment.type === 'pickup') {
      if (item.appointment.state !== 'active') {
        return this.result(false, '该领取预约已结束，无法取消。', itemId);
      }
      item.appointment.state = 'canceled';
      this.transition(item, 'IN_STOCK', actor, '学生取消领取预约，库存已释放');
      this.save();
      return this.result(true, `${item.title} 已取消预约并重新上架。`, itemId);
    }
    if (item.status !== 'PENDING' && item.status !== 'APPROVED' && item.status !== 'BOOKED') {
      return this.result(false, '当前状态不可撤回。', itemId);
    }
    if (item.appointment !== null && item.appointment.type === 'delivery' && Date.now() >= Date.parse(item.appointment.slotStartsAt)) {
      return this.result(false, '投递时段开始后不能取消预约。', itemId);
    }
    if (item.appointment !== null && item.appointment.state === 'active') {
      item.appointment.state = 'canceled';
    }
    this.transition(item, 'CANCELED', actor, '用户主动撤回');
    this.save();
    return this.result(true, `${item.title} 已取消，操作已记录。`, itemId);
  }

  public verifyCode(codeInput: string, operatorStationId: string, actualWeightKg: number, verifiedCondition: number): CicrsActionResult {
    const code: string = codeInput.trim();
    if (!/^\d{8}$/.test(code)) {
      return this.result(false, '请输入 8 位数字核销码。', '');
    }
    const item: CicrsItem | null = this.findItemByCode(code);
    if (item === null || item.appointment === null) {
      return this.result(false, '核销码无效，请核对后重试。', '');
    }
    const appointment: CicrsAppointment = item.appointment;
    if (appointment.state === 'used') {
      return this.result(false, `该核销码已于 ${appointment.usedAt} 核销，不会重复处理。`, item.id);
    }
    if (appointment.state !== 'active') {
      return this.result(false, '核销码已取消或过期。', item.id);
    }
    if (Date.parse(appointment.expiresAt) < Date.now()) {
      this.refreshExpirations();
      return this.result(false, '核销码已过期，物品已退回可预约状态。', item.id);
    }
    if (appointment.stationId !== operatorStationId) {
      this.snapshot.accessViolationCount += 1;
      this.save();
      return this.result(false, '该预约不属于当前驿站，已拒绝并记录越权尝试。', item.id);
    }
    if (appointment.type === 'delivery') {
      if (item.status !== 'BOOKED') {
        return this.result(false, '物品状态不允许收货核销。', item.id);
      }
      if (!Number.isFinite(actualWeightKg) || actualWeightKg <= 0) {
        return this.result(false, '请输入大于 0 的现场复核重量（kg）。', item.id);
      }
      if (verifiedCondition < 1 || verifiedCondition > 5) {
        return this.result(false, '请选择 1–5 档复核成色。', item.id);
      }
      item.actualWeightKg = actualWeightKg;
      item.verifiedConditionLevel = verifiedCondition;
      appointment.state = 'used';
      appointment.usedAt = nowIso();
      this.transition(item, 'RECEIVED', '东区驿站回收员', `扫码收货；复核重量 ${actualWeightKg} kg，成色 ${verifiedCondition} 档`);
      this.save();
      return this.result(true, `${item.title} 收货完成，进入待处置队列。`, item.id);
    }
    if (item.status !== 'RESERVED') {
      return this.result(false, '物品状态不允许领取核销。', item.id);
    }
    appointment.state = 'used';
    appointment.usedAt = nowIso();
    this.transition(item, 'COMPLETED', '东区驿站回收员', '预约领取核销完成');
    const award: CicrsActionResult = this.awardOnce(item, '循环完成');
    if (!award.ok) {
      return award;
    }
    this.save();
    return this.result(true, `${item.title} 已完成流转，获得 ${item.score} 积分。`, item.id);
  }

  public refuseDelivery(codeInput: string, operatorStationId: string, reason: string): CicrsActionResult {
    const item: CicrsItem | null = this.findItemByCode(codeInput.trim());
    const detail: string = reason.trim();
    if (item === null || item.appointment === null || item.appointment.type !== 'delivery') {
      return this.result(false, '该核销码不是有效的投递预约码。', '');
    }
    if (item.appointment.stationId !== operatorStationId) {
      this.snapshot.accessViolationCount += 1;
      this.save();
      return this.result(false, '该预约不属于当前驿站，已拒绝并记录越权尝试。', item.id);
    }
    if (item.status !== 'BOOKED' || item.appointment.state !== 'active') {
      return this.result(false, '该预约已完成、取消或过期，不能重复拒收。', item.id);
    }
    if (detail.length < 2) {
      return this.result(false, '请填写拒收原因。', item.id);
    }
    item.appointment.state = 'used';
    item.appointment.usedAt = nowIso();
    item.verificationRemark = detail;
    this.transition(item, 'CANCELED', '东区驿站回收员', `现场拒收：${detail}`);
    this.save();
    return this.result(true, `${item.title} 已拒收，学生端可查看原因。`, item.id);
  }

  public shelveItem(itemId: string, shelf: string): CicrsActionResult {
    const item: CicrsItem | null = this.findItem(itemId);
    const location: string = shelf.trim().slice(0, 30);
    if (item === null || item.status !== 'RECEIVED') {
      return this.result(false, '仅已收货物品可以上架。', itemId);
    }
    if (location.length < 1) {
      return this.result(false, '请填写货位号。', itemId);
    }
    for (const other of this.snapshot.items) {
      if (other.id !== item.id && other.status === 'IN_STOCK' && other.stationId === item.stationId && other.shelfLocation === location) {
        return this.result(false, '该货位已被占用，请选择其他货位。', itemId);
      }
    }
    item.shelfLocation = location;
    this.transition(item, 'IN_STOCK', '东区驿站回收员', `完成上架，货位 ${location}`);
    this.save();
    return this.result(true, `${item.title} 已上架，在学生端可预约领取。`, item.id);
  }

  public scrapItem(itemId: string, reason: string): CicrsActionResult {
    const item: CicrsItem | null = this.findItem(itemId);
    const detail: string = reason.trim();
    if (item === null || item.status !== 'RECEIVED') {
      return this.result(false, '仅已收货物品可以报废处置。', itemId);
    }
    if (detail.length < 2) {
      return this.result(false, '报废原因必填，至少输入 2 个字符。', itemId);
    }
    item.scrapReason = detail;
    this.transition(item, 'SCRAPPED', '东区驿站回收员', `报废处置：${detail}`);
    const award: CicrsActionResult = this.awardOnce(item, '报废处置');
    if (!award.ok) {
      return award;
    }
    this.save();
    return this.result(true, `${item.title} 已报废，碳账户获得 ${item.score} 积分。`, item.id);
  }

  public getAccount(ownerId: string): CicrsAccountSummary {
    let points: number = 0;
    let carbonSavedKg: number = 0;
    let completedCount: number = 0;
    for (const record of this.snapshot.scoreRecords) {
      if (record.ownerId === ownerId) {
        points += record.points;
        carbonSavedKg += record.carbonSavedKg;
        completedCount += 1;
      }
    }
    const absorption: number = this.catalog !== null ? this.catalog.rules.treeAbsorptionKgPerYear : 18.3;
    return { points, carbonSavedKg, completedCount, treeEquivalent: absorption > 0 ? carbonSavedKg / absorption : 0 };
  }

  public getCounts(): CicrsCountSummary {
    let pending: number = 0;
    let stock: number = 0;
    let booked: number = 0;
    let received: number = 0;
    let completed: number = 0;
    for (const item of this.snapshot.items) {
      if (item.status === 'PENDING') pending += 1;
      if (item.status === 'IN_STOCK') stock += 1;
      if (item.status === 'BOOKED' || item.status === 'RESERVED') booked += 1;
      if (item.status === 'RECEIVED') received += 1;
      if (item.status === 'COMPLETED' || item.status === 'SCRAPPED') completed += 1;
    }
    return { pending, stock, booked, received, completed };
  }

  private createDemoSnapshot(): CicrsSnapshot {
    const items: CicrsItem[] = [];
    const scores: CicrsScoreRecord[] = [];
    const now: Date = new Date();
    const current: string = now.toISOString();
    const future: Date = new Date(now.getTime() + 2 * 60 * 60 * 1000);
    const slot: string = this.formatSlot(future);
    const slotStart: string = this.roundToHalfHour(future).toISOString();
    const booked: CicrsItem = this.makeSeedItem('demo-book', '教材与图书包', 'book', 'BOOKED', 1, 'donate', 3, 0, 0, [
      'DRAFT', 'PENDING', 'APPROVED', 'BOOKED'
    ], current);
    booked.stationId = CICRS_STATIONS[0].id;
    booked.appointment = this.makeSeedAppointment('delivery', '38294176', CICRS_STATIONS[0], slot, slotStart);
    items.push(booked);

    const received: CicrsItem = this.makeSeedItem('demo-received', '毕业教材一套', 'book', 'RECEIVED', 3, 'donate', 1, 2.4, 0, [
      'DRAFT', 'PENDING', 'APPROVED', 'BOOKED', 'RECEIVED'
    ], current);
    received.stationId = CICRS_STATIONS[0].id;
    received.verifiedConditionLevel = 3;
    items.push(received);

    const shelf: CicrsItem = this.makeSeedItem('demo-stock', '节能台灯', 'appliance', 'IN_STOCK', 2, 'transfer', 1, 0, 0, [
      'DRAFT', 'PENDING', 'APPROVED', 'BOOKED', 'RECEIVED', 'IN_STOCK'
    ], current);
    shelf.stationId = CICRS_STATIONS[0].id;
    shelf.ownerId = 'student-previous-owner';
    shelf.ownerName = '周同学';
    shelf.shelfLocation = 'A-03';
    shelf.actualWeightKg = 1.2;
    shelf.verifiedConditionLevel = 2;
    items.push(shelf);

    const reserved: CicrsItem = this.makeSeedItem('demo-reserved', '高等数学教材', 'book', 'RESERVED', 3, 'donate', 1, 0.8, 0, [
      'DRAFT', 'PENDING', 'APPROVED', 'BOOKED', 'RECEIVED', 'IN_STOCK', 'RESERVED'
    ], current);
    reserved.stationId = CICRS_STATIONS[0].id;
    reserved.shelfLocation = 'B-02';
    reserved.actualWeightKg = 0.8;
    reserved.verifiedConditionLevel = 3;
    reserved.appointment = this.makeSeedAppointment('pickup', '72510483', CICRS_STATIONS[0], slot, slotStart);
    items.push(reserved);

    const completed: CicrsItem = this.makeSeedItem('demo-completed', '旧书循环示例', 'book', 'COMPLETED', 3, 'donate', 1, 2.4, 32, [
      'DRAFT', 'PENDING', 'APPROVED', 'BOOKED', 'RECEIVED', 'IN_STOCK', 'RESERVED', 'COMPLETED'
    ], current);
    completed.stationId = CICRS_STATIONS[0].id;
    completed.actualWeightKg = 2.4;
    completed.verifiedConditionLevel = 3;
    completed.carbonSavedKg = 2.64;
    completed.scoreAwarded = true;
    items.push(completed);
    const seedScore: CicrsScoreRecord = {
      id: 'score-demo-completed',
      itemId: completed.id,
      ownerId: completed.ownerId,
      points: 32,
      carbonSavedKg: 2.64,
      balanceAfter: 32,
      factorId: 'book',
      factorValue: 1.10,
      quantity: 2.4,
      conditionMultiplier: 1.0,
      transferMultiplier: 1.2,
      createdAt: current
    };
    scores.push(seedScore);
    return { items, scoreRecords: scores, nextCodeSeed: 31000005, accessViolationCount: 0 };
  }

  private makeSeedItem(id: string, title: string, factorId: string, status: CicrsItemStatus, condition: number,
    method: TransferMethod, quantity: number, weight: number, points: number, path: CicrsItemStatus[], createdAt: string): CicrsItem {
    const factor: CicrsFactor = findCicrsFactor(this.getCatalog(), factorId);
    const history: CicrsStatusEvent[] = [];
    for (const state of path) {
      let actor: string = '体验学生';
      if (state === 'APPROVED') actor = '体验管理员';
      if (state === 'BOOKED' || state === 'RECEIVED' || state === 'IN_STOCK' || state === 'RESERVED' || state === 'COMPLETED' || state === 'SCRAPPED') actor = '体验驿站回收员';
      history.push(makeEvent(state, actor, `演示流转记录：${state}`, createdAt));
    }
    const item: CicrsItem = {
      id: `item-${id}`,
      ownerId: ACTOR_STUDENT,
      ownerName: '林同学',
      factorId: factor.id,
      factorValue: factor.value,
      factorSource: factor.source,
      factorUnit: factor.unit,
      factorVersion: 'catalog-demo-v1',
      stationId: '',
      title,
      category: factor.category,
      conditionLevel: condition,
      verifiedConditionLevel: condition,
      transferMethod: method,
      quantity,
      estimatedWeightKg: weight,
      actualWeightKg: weight,
      description: '青碳汇体验数据，用于演示学生与驿站闭环。',
      imageUris: [],
      status,
      statusEvents: history,
      appointment: null,
      verificationRemark: '',
      shelfLocation: '',
      scrapReason: '',
      carbonSavedKg: points > 0 && factor.id === 'book' ? 2.64 : 0,
      score: points,
      scoreAwarded: points > 0,
      createdAt,
      updatedAt: createdAt
    };
    return item;
  }

  private makeSeedAppointment(type: AppointmentType, code: string, station: CicrsStation, slot: string, slotStartsAt: string): CicrsAppointment {
    const appointment: CicrsAppointment = {
      type,
      code,
      stationId: station.id,
      stationName: station.name,
      slot,
      slotStartsAt,
      expiresAt: dayEndIso(slotStartsAt),
      state: 'active',
      usedAt: ''
    };
    return appointment;
  }

  private transition(item: CicrsItem, next: CicrsItemStatus, actor: string, note: string): void {
    if (!this.isAllowedTransition(item.status, next)) {
      throw new Error(`非法状态流转：${item.status} -> ${next}`);
    }
    item.status = next;
    item.updatedAt = nowIso();
    item.statusEvents = [...item.statusEvents, makeEvent(next, actor, note, item.updatedAt)];
  }

  private isAllowedTransition(from: CicrsItemStatus, to: CicrsItemStatus): boolean {
    if (from === 'DRAFT') return to === 'PENDING';
    if (from === 'PENDING') return to === 'APPROVED' || to === 'REJECTED' || to === 'CANCELED';
    if (from === 'APPROVED') return to === 'BOOKED' || to === 'CANCELED' || to === 'PENDING';
    if (from === 'BOOKED') return to === 'RECEIVED' || to === 'APPROVED' || to === 'CANCELED';
    if (from === 'RECEIVED') return to === 'IN_STOCK' || to === 'SCRAPPED';
    if (from === 'IN_STOCK') return to === 'RESERVED' || to === 'SCRAPPED';
    if (from === 'RESERVED') return to === 'COMPLETED' || to === 'IN_STOCK';
    return false;
  }

  private awardOnce(item: CicrsItem, reason: string): CicrsActionResult {
    if (item.scoreAwarded || this.hasScoreRecord(item.id)) {
      return this.result(false, '该物品已结算过积分，系统已阻止重复发放。', item.id);
    }
    if (this.catalog === null) {
      return this.result(false, '碳因子配置不可用，无法结算。', item.id);
    }
    const factor: CicrsFactor = findCicrsFactor(this.catalog, item.factorId);
    const actualQuantity: number = factor.unit === 'kg' ? item.actualWeightKg : item.quantity;
    if (!Number.isFinite(actualQuantity) || actualQuantity <= 0) {
      return this.result(false, '缺少有效的现场重量或物品数量，暂不能结算。', item.id);
    }
    const completionDate: number = Date.now();
    const savedFactorValue: number = item.factorValue > 0 ? item.factorValue : factor.value;
    const reduction: number = Number((actualQuantity * savedFactorValue).toFixed(4));
    const conditionIndex: number = Math.max(0, Math.min(4, item.verifiedConditionLevel > 0 ? item.verifiedConditionLevel - 1 : item.conditionLevel - 1));
    const methodIndex: number = item.status === 'SCRAPPED' ? 2 : this.methodIndex(item.transferMethod);
    const conditionMultiplier: number = this.catalog.conditionMultipliers[conditionIndex];
    const transferMultiplier: number = this.catalog.transferMultipliers[methodIndex];
    const points: number = Math.round(reduction * conditionMultiplier * transferMultiplier * this.catalog.rules.basePointsPerKg);
    const balance: number = this.accountBalance(item.ownerId) + points;
    const record: CicrsScoreRecord = {
      id: `score-${Date.now()}-${this.snapshot.nextCodeSeed}`,
      itemId: item.id,
      ownerId: item.ownerId,
      points,
      carbonSavedKg: reduction,
      balanceAfter: balance,
      factorId: factor.id,
      factorValue: savedFactorValue,
      quantity: actualQuantity,
      conditionMultiplier,
      transferMultiplier,
      createdAt: new Date(completionDate).toISOString()
    };
    item.factorValue = savedFactorValue;
    item.factorSource = factor.source;
    item.factorVersion = 'catalog-demo-v1';
    item.carbonSavedKg = reduction;
    item.score = points;
    item.scoreAwarded = true;
    this.snapshot.scoreRecords = [record, ...this.snapshot.scoreRecords];
    this.snapshot.nextCodeSeed += 1;
    console.info(`CICRS demo score settled once for ${item.id}: ${reason}`);
    return this.result(true, '碳积分已记入本机演示账本。', item.id);
  }

  private methodIndex(method: TransferMethod): number {
    if (method === 'donate') return 0;
    if (method === 'transfer') return 1;
    return 2;
  }

  private accountBalance(ownerId: string): number {
    let balance: number = 0;
    for (const record of this.snapshot.scoreRecords) {
      if (record.ownerId === ownerId) balance += record.points;
    }
    return balance;
  }

  private hasScoreRecord(itemId: string): boolean {
    for (const record of this.snapshot.scoreRecords) {
      if (record.itemId === itemId) return true;
    }
    return false;
  }

  private countStatuses(ownerId: string, statuses: CicrsItemStatus[]): number {
    let count: number = 0;
    for (const item of this.snapshot.items) {
      if (item.ownerId === ownerId && statuses.includes(item.status)) count += 1;
    }
    return count;
  }

  private countSlotAppointments(stationId: string, slot: string): number {
    let count: number = 0;
    for (const item of this.snapshot.items) {
      const appointment: CicrsAppointment | null = item.appointment;
      if (appointment !== null && appointment.stationId === stationId && appointment.slot === slot && appointment.state === 'active') {
        count += 1;
      }
    }
    return count;
  }

  private findItem(itemId: string): CicrsItem | null {
    for (const item of this.snapshot.items) {
      if (item.id === itemId) return item;
    }
    return null;
  }

  private findItemByCode(code: string): CicrsItem | null {
    for (const item of this.snapshot.items) {
      if (item.appointment !== null && item.appointment.code === code) return item;
    }
    return null;
  }

  private nextUniqueCode(): string {
    let code: string = codeText(this.snapshot.nextCodeSeed);
    let exists: boolean = true;
    while (exists) {
      exists = false;
      for (const item of this.snapshot.items) {
        if (item.appointment !== null && item.appointment.code === code) {
          this.snapshot.nextCodeSeed += 1;
          code = codeText(this.snapshot.nextCodeSeed);
          exists = true;
          break;
        }
      }
    }
    this.snapshot.nextCodeSeed += 1;
    return code;
  }

  private formatSlot(date: Date): string {
    return `${date.getMonth() + 1}月${date.getDate()}日 ${date.getHours()}:00–${date.getHours()}:30`;
  }

  private roundToHalfHour(date: Date): Date {
    const result: Date = new Date(date);
    result.setMinutes(result.getMinutes() >= 30 ? 30 : 0, 0, 0);
    return result;
  }

  private result(ok: boolean, message: string, itemId: string): CicrsActionResult {
    const response: CicrsActionResult = { ok, message, itemId };
    return response;
  }

  private save(): void {
    if (this.store === null) return;
    const value: string = JSON.stringify(this.snapshot);
    this.store.putSync(SNAPSHOT_KEY, value);
    this.store.flush().catch((error: Error) => {
      console.error(`CICRS local demo snapshot could not be saved: ${error.message}`);
    });
  }
}

export const cicrsRepository: CicrsRepository = new CicrsRepository();
