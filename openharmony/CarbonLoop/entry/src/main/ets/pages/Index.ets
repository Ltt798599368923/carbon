import {
  CARBON_FACTORS,
  CarbonFactor,
  CarbonRecord,
  RecordBucket,
  RecordPeriod,
  buildTrendBuckets,
  calculatePoints,
  calculateReduction,
  filterRecordsForPeriod,
  findFactor,
  formatKg
} from '../model/CarbonModel';
import { KnowledgeArticle, KNOWLEDGE_ARTICLES, findArticle } from '../model/KnowledgeModel';
import { carbonContext, carbonPreferences } from '../entryability/EntryAbility';
import { loadBackendToken, loadChallengeJoined, loadDeletedRecordIds, loadDeviceId, loadItems, loadPendingItemCreates, loadPendingItemEvents, loadRecords, PendingItemCreate, PendingItemEvent, saveBackendToken, saveChallengeJoined, saveDeletedRecordIds, saveDeviceId, saveItems, savePendingItemCreates, savePendingItemEvents, saveRecords } from '../storage/CarbonStorage';
import { createCarbonBackup, createRecordsCsv, mergeCarbonRecords, parseCarbonBackup, readBackupWithPicker, saveTextWithPicker } from '../storage/CarbonExport';
import { ApiItem, ApiPointsLedgerEntry, ApiRecord, ApiReward, ApiStation, ApiTask, CarbonApiClient } from '../network/ApiClient';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State selectedFactorId: string = 'walk';
  @State amountText: string = '3';
  // 初次启动不注入演示记录；所有数据都来自真实用户操作或后端同步。
  @State records: CarbonRecord[] = [];
  @State notice: string = '';
  @State challengeJoined: boolean = false;
  @State challengeNotice: string = '';
  @State backendStatus: string = '本地待同步';
  @State pendingSyncCount: number = 0;
  @State pendingItemSyncCount: number = 0;
  @State taskLedger: ApiPointsLedgerEntry[] = [];
  @State rewards: ApiReward[] = [];
  @State rewardNotice: string = '';
  @State cloudPoints: number = 0;
  @State dailyTasks: ApiTask[] = [];
  @State items: ApiItem[] = [];
  @State stations: ApiStation[] = [];
  @State itemTitle: string = '';
  @State itemType: string = '书籍';
  @State itemWeightText: string = '1';
  @State itemFlow: string = 'exchange';
  @State itemNotice: string = '';
  @State recordPeriod: RecordPeriod = 'week';
  @State recordFactorFilter: string = 'all';
  @State trendFilterOpen: boolean = false;
  @State recordComposerOpen: boolean = false;
  @State recordScenarioIndex: number = -1;
  @State recordManualAmount: boolean = false;
  @State knowledgeCategory: string = '全部';
  @State selectedArticleId: string = '';
  @State occurredDateText: string = '';
  @State editingRecordId: string = '';
  @State deletedRecordIds: string[] = [];
  private api: CarbonApiClient = new CarbonApiClient();

  // Native CarbonLoop follows the approved Web visual language: deep campus green,
  // mint highlights and translucent panels, while keeping the existing ArkUI layout.
  private readonly ink: string = '#F1F8F4';
  private readonly accent: string = '#9DE4BD';
  private readonly muted: string = '#A7C3BA';
  private readonly line: string = '#2ADAF4EA';
  private readonly page: string = '#0B2020';
  private readonly panel: string = '#18FFFFFF';
  private readonly panelStrong: string = '#25FFFFFF';
  private readonly mint: string = '#243F5F56';

  aboutToAppear(): void {
    const savedRecords: CarbonRecord[] | null = loadRecords(carbonPreferences);
    if (savedRecords === null) {
      saveRecords(carbonPreferences, this.records);
    } else {
      this.records = savedRecords;
    }
    this.challengeJoined = loadChallengeJoined(carbonPreferences);
    this.deletedRecordIds = loadDeletedRecordIds(carbonPreferences);
    this.items = loadItems(carbonPreferences);
    this.refreshPendingItemSyncCount();
    this.occurredDateText = this.todayDateText();
    this.refreshPendingSyncCount();
    let deviceId: string | null = loadDeviceId(carbonPreferences);
    if (deviceId === null) {
      deviceId = `device-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
      saveDeviceId(carbonPreferences, deviceId);
    }
    this.initializeBackend(deviceId);
  }

  private async initializeBackend(deviceId: string): Promise<void> {
    try {
      const savedToken: string | null = loadBackendToken(carbonPreferences);
      if (savedToken !== null) {
        this.api.setToken(savedToken);
      }
      const login = await this.api.guestLogin(deviceId);
      if (login.token === undefined) {
        throw new Error('登录响应缺少 token');
      }
      this.api.setToken(login.token);
      saveBackendToken(carbonPreferences, login.token);
      this.backendStatus = '云端已连接';
      await this.syncPendingItemChanges();
      await this.syncPendingChanges();
      const remoteRecords: ApiRecord[] = await this.api.getRecords();
      if (remoteRecords.length > 0) {
        this.records = remoteRecords.map((record: ApiRecord): CarbonRecord => ({
          id: record.clientRecordId.length > 0 ? record.clientRecordId : record.id,
          factorId: record.factorId,
          amount: record.amount,
          reductionKg: record.reductionKg,
          points: record.points,
          createdAt: record.createdAt,
          factorVersion: record.factorVersion,
          occurredAt: record.occurredAt,
          verificationStatus: record.verificationStatus ?? 'self_reported',
          locationId: record.locationId ?? undefined,
          syncStatus: 'synced',
          syncOperation: 'create'
        })).filter((record: CarbonRecord) => !this.deletedRecordIds.includes(record.id));
        saveRecords(carbonPreferences, this.records);
      }
      await this.refreshItems();
      await this.refreshStations();
      const dashboard = await this.api.getDashboard();
      this.dailyTasks = dashboard.tasks ?? [];
      this.taskLedger = (dashboard.pointsLedger ?? []).filter((entry: ApiPointsLedgerEntry) => entry.taskId !== undefined);
      this.cloudPoints = dashboard.summary === undefined ? this.calculateLocalPoints() : dashboard.summary.totalPoints;
      await this.refreshRewards();
      this.refreshPendingSyncCount();
    } catch (error) {
      this.backendStatus = '离线可用';
      console.error(`CarbonLoop backend sync skipped: ${error}`);
    }
  }

  private async refreshItems(): Promise<void> {
    try {
      const remoteItems: ApiItem[] = await this.api.getItems();
      const pendingCreates: PendingItemCreate[] = loadPendingItemCreates(carbonPreferences);
      const pendingEvents: PendingItemEvent[] = loadPendingItemEvents(carbonPreferences);
      if (remoteItems.length > 0 || (pendingCreates.length === 0 && pendingEvents.length === 0)) {
        const localPendingItems: ApiItem[] = this.items.filter((item: ApiItem) => pendingCreates.some((pending: PendingItemCreate) => pending.clientItemId === item.clientItemId));
        this.items = [...remoteItems, ...localPendingItems];
        saveItems(carbonPreferences, this.items);
      }
    } catch (error) {
      console.error(`CarbonLoop item sync skipped: ${error}`);
    }
  }

  private async refreshRewards(): Promise<void> {
    try {
      const rewardCatalog = await this.api.getRewards();
      this.rewards = rewardCatalog.rewards ?? [];
      if (rewardCatalog.totalPoints !== undefined) {
        this.cloudPoints = rewardCatalog.totalPoints;
      }
    } catch (error) {
      console.error(`CarbonLoop reward catalog skipped: ${error}`);
    }
  }

  private async refreshStations(): Promise<void> {
    try {
      this.stations = await this.api.getStations();
    } catch (error) {
      console.error(`CarbonLoop station sync skipped: ${error}`);
    }
  }

  private getSelectedFactor(): CarbonFactor {
    return findFactor(this.selectedFactorId);
  }

  private calculateTotalReduction(): number {
    let total: number = 0;
    for (const item of this.records) {
      total += item.reductionKg;
    }
    return total;
  }

  private calculateLocalPoints(): number {
    let total: number = 0;
    for (const item of this.records) {
      total += item.points;
    }
    for (const entry of this.taskLedger) {
      total += entry.points;
    }
    return total;
  }

  private calculateTotalPoints(): number {
    return this.backendStatus === '云端已连接' ? this.cloudPoints : this.calculateLocalPoints();
  }

  private todayDateText(): string {
    const date: Date = new Date();
    const month: string = date.getMonth() + 1 < 10 ? '0' + (date.getMonth() + 1) : '' + (date.getMonth() + 1);
    const day: string = date.getDate() < 10 ? '0' + date.getDate() : '' + date.getDate();
    return `${date.getFullYear()}-${month}-${day}`;
  }

  private parseOccurredAt(): string | null {
    const value: string = this.occurredDateText.trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      return null;
    }
    const parts: string[] = value.split('-');
    const date: Date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0);
    if (Number.isNaN(date.getTime()) || date.getFullYear() !== Number(parts[0]) || date.getMonth() !== Number(parts[1]) - 1 || date.getDate() !== Number(parts[2])) {
      return null;
    }
    return date.toISOString();
  }

  private refreshPendingSyncCount(): void {
    let count: number = 0;
    for (const record of this.records) {
      if (record.syncStatus !== 'synced') {
        count += 1;
      }
    }
    this.pendingSyncCount = count;
  }

  private refreshPendingItemSyncCount(): void {
    this.pendingItemSyncCount = loadPendingItemCreates(carbonPreferences).length + loadPendingItemEvents(carbonPreferences).length;
  }

  private getDailyTask(): ApiTask | null {
    return this.dailyTasks.length > 0 ? this.dailyTasks[0] : null;
  }

  private getDailyTaskProgress(): number {
    const task: ApiTask | null = this.getDailyTask();
    if (task !== null && task.day === this.todayDateText()) {
      return task.progress;
    }
    let progress: number = 0;
    for (const record of this.records) {
      if (record.occurredAt.slice(0, 10) === this.todayDateText() && record.factorId === 'reusable') {
        progress += record.amount;
      }
    }
    return Math.min(1, progress);
  }

  private calculateChallengeDistance(): number {
    let total: number = 0;
    for (const item of this.records) {
      if (item.factorId === 'walk') {
        total += item.amount;
      }
    }
    return total;
  }

  private getChallengeProgress(): number {
    return Math.min(15, this.calculateChallengeDistance());
  }

  private itemFlowLabel(flow: string): string {
    if (flow === 'exchange') {
      return '交换';
    }
    if (flow === 'donate') {
      return '捐赠';
    }
    if (flow === 'repair') {
      return '维修';
    }
    return '回收';
  }

  private itemWeight(): number {
    const value: number = Number(this.itemWeightText);
    return Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  private itemStatusLabel(flow: string): string {
    if (flow === 'exchange') {
      return '等待交换';
    }
    if (flow === 'donate') {
      return '已捐赠';
    }
    if (flow === 'repair') {
      return '维修中';
    }
    return '已进入回收流程';
  }

  private async createItem(): Promise<void> {
    const title: string = this.itemTitle.trim();
    const itemType: string = this.itemType.trim();
    const weightKg: number = this.itemWeight();
    if (title.length === 0 || itemType.length === 0) {
      this.itemNotice = '请填写物品名称和类型。';
      return;
    }
    if (weightKg <= 0 || weightKg > 1000) {
      this.itemNotice = '请输入大于 0 且不超过 1000 kg 的物品重量。';
      return;
    }
    const clientItemId: string = `item-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    this.itemNotice = '正在生成第二人生卡片…';
    try {
      const item: ApiItem = await this.api.createItem(clientItemId, title, itemType, weightKg, this.itemFlow);
      this.items = [item, ...this.items.filter((candidate: ApiItem) => candidate.id !== item.id && candidate.clientItemId !== item.clientItemId)];
      saveItems(carbonPreferences, this.items);
      const itemRecordId: string = item.clientItemId.length > 0 ? `item:${item.clientItemId}` : item.id;
      const itemRecord: CarbonRecord = {
        id: itemRecordId,
        factorId: 'recycle',
        factorVersion: findFactor('recycle').version,
        amount: item.weightKg,
        reductionKg: item.reductionKg,
        points: item.points,
        occurredAt: item.createdAt,
        createdAt: item.createdAt,
        verificationStatus: 'self_reported',
        syncStatus: 'synced',
        syncOperation: 'create'
      };
      this.records = [itemRecord, ...this.records.filter((record: CarbonRecord) => record.id !== itemRecordId)];
      saveRecords(carbonPreferences, this.records);
      this.refreshPendingSyncCount();
      this.refreshPendingItemSyncCount();
      this.itemTitle = '';
      this.itemWeightText = '1';
      this.backendStatus = '云端已连接';
      await this.refreshRewards();
      this.itemNotice = `已登记“${item.title}”，获得 ${item.points} 个积分。减排为当前因子口径下的估算值。`;
    } catch (error) {
      const now: string = new Date().toISOString();
      const factor: CarbonFactor = findFactor('recycle');
      const localItem: ApiItem = {
        id: `local_${clientItemId}`,
        clientItemId,
        title,
        itemType,
        weightKg,
        flow: this.itemFlow,
        status: this.itemStatusLabel(this.itemFlow),
        cycleCount: 1,
        reductionKg: Number(calculateReduction(factor, weightKg).toFixed(4)),
        points: calculatePoints(factor, weightKg),
        events: [{ id: `local_event_${clientItemId}`, type: this.itemFlow, label: this.itemStatusLabel(this.itemFlow), note: '', createdAt: now }],
        updatedAt: now,
        createdAt: now
      };
      this.items = [localItem, ...this.items.filter((candidate: ApiItem) => candidate.clientItemId !== clientItemId)];
      saveItems(carbonPreferences, this.items);
      const creates: PendingItemCreate[] = loadPendingItemCreates(carbonPreferences);
      if (!creates.some((candidate: PendingItemCreate) => candidate.clientItemId === clientItemId)) {
        creates.push({ clientItemId, title, itemType, weightKg, flow: this.itemFlow });
        savePendingItemCreates(carbonPreferences, creates);
      }
      const itemRecord: CarbonRecord = {
        id: `item:${clientItemId}`,
        factorId: 'recycle',
        factorVersion: factor.version,
        amount: weightKg,
        reductionKg: localItem.reductionKg,
        points: localItem.points,
        occurredAt: now,
        createdAt: now,
        verificationStatus: 'self_reported',
        syncStatus: 'pending',
        syncOperation: 'create'
      };
      this.records = [itemRecord, ...this.records.filter((record: CarbonRecord) => record.id !== itemRecord.id)];
      saveRecords(carbonPreferences, this.records);
      this.refreshPendingSyncCount();
      this.refreshPendingItemSyncCount();
      this.backendStatus = '离线可用';
      this.itemTitle = '';
      this.itemWeightText = '1';
      this.itemNotice = '已保存在本机，联网后会自动同步旧物卡片和首次积分。';
      console.error(`CarbonLoop item create queued: ${error}`);
    }
  }

  private nextSlotLabel(): string {
    const date: Date = new Date(Date.now() + 60 * 60 * 1000);
    const hour: number = date.getHours();
    const nextHour: number = (hour + 1) % 24;
    return `今日 ${hour}:00-${nextHour}:00`;
  }

  private nextSlotStart(): string {
    return new Date(Date.now() + 60 * 60 * 1000).toISOString();
  }

  private async bookDelivery(item: ApiItem): Promise<void> {
    const station: ApiStation | undefined = this.stations.length > 0 ? this.stations[0] : undefined;
    if (station === undefined) {
      this.itemNotice = '暂无可用旧物驿站，请稍后重试。';
      return;
    }
    try {
      const updated: ApiItem = await this.api.bookItem(item.id, 'delivery', station.id, this.nextSlotLabel(), this.nextSlotStart());
      this.items = this.items.map((candidate: ApiItem) => candidate.id === updated.id ? updated : candidate);
      this.itemNotice = `已预约${station.name}投递，请在到站时出示 8 位核销码。`;
    } catch (error) {
      this.itemNotice = '预约投递失败，请确认物品已通过核验。';
      console.error(`CarbonLoop delivery booking skipped: ${error}`);
    }
  }

  private async reservePickup(item: ApiItem): Promise<void> {
    const station: ApiStation | undefined = this.stations.length > 0 ? this.stations[0] : undefined;
    if (station === undefined) {
      this.itemNotice = '暂无可用旧物驿站，请稍后重试。';
      return;
    }
    try {
      const updated: ApiItem = await this.api.reserveItem(item.id, station.id, this.nextSlotLabel(), this.nextSlotStart());
      this.items = this.items.map((candidate: ApiItem) => candidate.id === updated.id ? updated : candidate);
      this.itemNotice = `已预约在${station.name}领取，请按预约时间到站。`;
    } catch (error) {
      this.itemNotice = '预约领取失败，这件物品可能已被其他同学预约。';
      console.error(`CarbonLoop pickup booking skipped: ${error}`);
    }
  }

  private async advanceItem(item: ApiItem, flow: string): Promise<void> {
    if (item.flow === flow) {
      this.itemNotice = `“${item.title}”已经是${this.itemFlowLabel(flow)}状态。`;
      return;
    }
    try {
      const updated: ApiItem = await this.api.addItemCycleEvent(item.id, flow);
      this.items = this.items.map((candidate: ApiItem) => candidate.id === updated.id ? updated : candidate);
      saveItems(carbonPreferences, this.items);
      this.backendStatus = '云端已连接';
      this.itemNotice = `已更新“${updated.title}”的流转状态：${updated.status}。后续流转不会重复发放首次登记积分。`;
    } catch (error) {
      const now: string = new Date().toISOString();
      const updated: ApiItem = {
        id: item.id,
        clientItemId: item.clientItemId,
        title: item.title,
        itemType: item.itemType,
        weightKg: item.weightKg,
        flow,
        status: this.itemStatusLabel(flow),
        cycleCount: item.cycleCount + 1,
        reductionKg: item.reductionKg,
        points: item.points,
        events: [...(item.events ?? []), { id: `local_event_${Date.now()}`, type: flow, label: this.itemStatusLabel(flow), note: '', createdAt: now }],
        updatedAt: now,
        createdAt: item.createdAt
      };
      this.items = this.items.map((candidate: ApiItem) => candidate.id === item.id ? updated : candidate);
      saveItems(carbonPreferences, this.items);
      const itemKey: string = item.clientItemId.length > 0 ? item.clientItemId : item.id;
      const events: PendingItemEvent[] = loadPendingItemEvents(carbonPreferences);
      if (!events.some((candidate: PendingItemEvent) => candidate.itemKey === itemKey && candidate.type === flow)) {
        events.push({ itemKey, type: flow });
        savePendingItemEvents(carbonPreferences, events);
      }
      this.refreshPendingItemSyncCount();
      this.backendStatus = '离线可用';
      this.itemNotice = '已保存在本机，联网后会自动同步流转状态。';
      console.error(`CarbonLoop item event queued: ${error}`);
    }
  }

  private async redeemReward(reward: ApiReward): Promise<void> {
    if (reward.redeemed || !reward.canRedeem) {
      this.rewardNotice = reward.redeemed ? '这个奖励已经兑换过了。' : '当前积分不足，完成更多低碳任务后再来兑换。';
      return;
    }
    try {
      const response = await this.api.redeemReward(reward.id);
      this.rewards = this.rewards.map((candidate: ApiReward) => candidate.id === reward.id
        ? { id: candidate.id, name: candidate.name, description: candidate.description, cost: candidate.cost, kind: candidate.kind, code: candidate.code, limitPerUser: candidate.limitPerUser, redeemed: true, canRedeem: false }
        : candidate);
      this.cloudPoints = response.totalPoints === undefined ? Math.max(0, this.cloudPoints - reward.cost) : response.totalPoints;
      this.rewardNotice = `已兑换“${reward.name}”，扣除 ${reward.cost} 分。`;
    } catch (error) {
      this.rewardNotice = '奖励兑换失败，请确认网络连接后重试。';
      console.error(`CarbonLoop reward redeem skipped: ${error}`);
    }
  }

  private workflowActionLabel(item: ApiItem): string {
    if (item.workflowStatus === 'PENDING') return '等待管理员核验';
    if (item.workflowStatus === 'APPROVED') return '预约投递';
    if (item.workflowStatus === 'BOOKED') return '已预约投递';
    if (item.workflowStatus === 'RECEIVED') return '等待驿站上架';
    if (item.workflowStatus === 'IN_STOCK') return '预约领取';
    if (item.workflowStatus === 'RESERVED') return '已预约领取';
    return item.workflowStatusLabel;
  }

  private async joinChallenge(): Promise<void> {
    try {
      await this.api.joinChallenge('walk-week-2026-10');
      this.backendStatus = '云端已连接';
      this.challengeNotice = '已加入云端挑战。记录步行或骑行后，进度会自动更新。';
    } catch (error) {
      this.backendStatus = '离线可用';
      this.challengeNotice = '已在本机加入，联网后会自动同步。';
      console.error(`CarbonLoop challenge sync skipped: ${error}`);
    }
    this.challengeJoined = true;
    saveChallengeJoined(carbonPreferences, true);
  }

  private async syncPendingItemChanges(): Promise<void> {
    let creates: PendingItemCreate[] = loadPendingItemCreates(carbonPreferences);
    let events: PendingItemEvent[] = loadPendingItemEvents(carbonPreferences);
    for (const pending of creates) {
      try {
        const remote: ApiItem = await this.api.createItem(pending.clientItemId, pending.title, pending.itemType, pending.weightKg, pending.flow);
        const localItem: ApiItem | undefined = this.items.find((item: ApiItem) => item.clientItemId === pending.clientItemId);
        this.items = localItem === undefined
          ? [remote, ...this.items]
          : this.items.map((item: ApiItem) => item.id === localItem.id ? remote : item);
        const itemRecordId: string = `item:${pending.clientItemId}`;
        this.records = this.records.map((record: CarbonRecord): CarbonRecord => record.id === itemRecordId
          ? {
            id: record.id,
            factorId: record.factorId,
            factorVersion: record.factorVersion,
            amount: record.amount,
            reductionKg: remote.reductionKg,
            points: remote.points,
            occurredAt: record.occurredAt,
            createdAt: record.createdAt,
            verificationStatus: record.verificationStatus,
            locationId: record.locationId,
            syncStatus: 'synced',
            syncOperation: 'create'
          }
          : record);
        creates = creates.filter((candidate: PendingItemCreate) => candidate.clientItemId !== pending.clientItemId);
        savePendingItemCreates(carbonPreferences, creates);
        saveItems(carbonPreferences, this.items);
        saveRecords(carbonPreferences, this.records);
        const localItemKey: string = localItem === undefined ? '' : localItem.id;
        const matchingEvents: PendingItemEvent[] = events.filter((event: PendingItemEvent) => event.itemKey === pending.clientItemId || event.itemKey === localItemKey);
        events = events.filter((event: PendingItemEvent) => event.itemKey !== pending.clientItemId && event.itemKey !== localItemKey);
        for (const event of matchingEvents) {
          const updated: ApiItem = await this.api.addItemCycleEvent(remote.id, event.type);
          this.items = this.items.map((item: ApiItem) => item.id === updated.id ? updated : item);
        }
        savePendingItemEvents(carbonPreferences, events);
        saveItems(carbonPreferences, this.items);
      } catch (error) {
        console.error(`CarbonLoop pending item create skipped: ${error}`);
        break;
      }
    }
    const pendingEventsSnapshot: PendingItemEvent[] = [...events];
    for (const event of pendingEventsSnapshot) {
      const target: ApiItem | undefined = this.items.find((item: ApiItem) => item.clientItemId === event.itemKey || item.id === event.itemKey);
      if (target === undefined || target.id.startsWith('local_')) {
        continue;
      }
      try {
        const updated: ApiItem = await this.api.addItemCycleEvent(target.id, event.type);
        this.items = this.items.map((item: ApiItem) => item.id === updated.id ? updated : item);
        events = events.filter((candidate: PendingItemEvent) => candidate !== event);
        savePendingItemEvents(carbonPreferences, events);
        saveItems(carbonPreferences, this.items);
      } catch (error) {
        console.error(`CarbonLoop pending item event skipped: ${error}`);
      }
    }
    this.refreshPendingItemSyncCount();
  }

  private async syncPendingChanges(): Promise<void> {
    for (const deletedId of this.deletedRecordIds) {
      try {
        await this.api.deleteRecord(deletedId);
        this.deletedRecordIds = this.deletedRecordIds.filter((id: string) => id !== deletedId);
        saveDeletedRecordIds(carbonPreferences, this.deletedRecordIds);
      } catch (error) {
        console.error(`CarbonLoop pending delete skipped: ${error}`);
      }
    }
    for (const record of this.records) {
      if (record.syncStatus === 'synced') {
        continue;
      }
      try {
        const remote: ApiRecord = record.syncOperation === 'update'
          ? await this.api.updateRecord(record.id, record.factorId, record.amount, record.occurredAt)
          : await this.api.createRecord(record.id, record.factorId, record.amount, record.occurredAt, record.locationId);
        this.records = this.records.map((candidate: CarbonRecord): CarbonRecord => candidate.id === record.id
          ? this.syncedRecord(candidate, remote)
          : candidate);
        saveRecords(carbonPreferences, this.records);
      } catch (error) {
        console.error(`CarbonLoop pending record skipped: ${error}`);
      }
    }
    this.refreshPendingSyncCount();
  }

  private async retrySync(): Promise<void> {
    const deviceId: string | null = loadDeviceId(carbonPreferences);
    if (deviceId === null) {
      this.notice = '设备身份尚未准备好，请稍后重试。';
      return;
    }
    await this.initializeBackend(deviceId);
    const pendingTotal: number = this.pendingSyncCount + this.pendingItemSyncCount;
    this.notice = pendingTotal === 0 ? '同步已完成。' : `仍有 ${pendingTotal} 条数据待同步。`;
  }

  private getPreviewAmount(): number {
    const value: number = Number(this.amountText);
    return Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  private getPreviewReduction(): number {
    return calculateReduction(this.getSelectedFactor(), this.getPreviewAmount());
  }

  private getPreviewIsBehaviorOnly(): boolean {
    return this.getSelectedFactor().calculationStatus === 'behavior_only';
  }

  private getPreviewPoints(): number {
    return calculatePoints(this.getSelectedFactor(), this.getPreviewAmount());
  }

  private scenarioLabels(): string[] {
    if (this.selectedFactorId === 'walk') return ['校内短途步行（约 1 公里）', '校内往返步行（约 3 公里）', '我知道距离，自己填写'];
    if (this.selectedFactorId === 'transit') return ['短途公交 / 地铁（约 3 公里）', '日常通勤（约 8 公里）', '我知道距离，自己填写'];
    if (this.selectedFactorId === 'recycle') return ['小件或小袋（约 1 公斤）', '中件或一袋（约 3 公斤）', '我知道重量，自己填写'];
    if (this.selectedFactorId === 'energy') return ['离开时关灯', '提前关闭空调或电脑', '关闭宿舍空闲电器'];
    if (this.selectedFactorId === 'reusable') return ['自带水杯', '自带餐具', '拒绝一次性袋或吸管'];
    if (this.selectedFactorId === 'water') return ['洗手或刷牙时及时关水', '淋浴主动缩短一次', '发现漏水并及时报修'];
    if (this.selectedFactorId === 'meal') return ['完成光盘', '少取一份吃不完的食物', '把剩余餐食打包带走'];
    return [];
  }

  private scenarioAmount(index: number): string {
    if (this.selectedFactorId === 'walk') return index === 0 ? '1' : '3';
    if (this.selectedFactorId === 'transit') return index === 0 ? '3' : '8';
    if (this.selectedFactorId === 'recycle') return index === 0 ? '1' : '3';
    return '1';
  }

  private scenarioHint(): string {
    if (this.selectedFactorId === 'walk' || this.selectedFactorId === 'transit') return '先按出行情境估算，不需要现在填写公里；后续接入定位后再自动校准。';
    if (this.selectedFactorId === 'recycle') return '可以按物品实际称重，也可以先用常见大小估算。';
    if (this.selectedFactorId === 'energy') return '节电先记录真实行为，不把一次关灯虚构成精确的“几度电”。';
    return '选择最接近你今天实际做法的一项即可。';
  }

  private chooseScenario(index: number): void {
    this.recordScenarioIndex = index;
    this.recordManualAmount = (this.selectedFactorId === 'walk' || this.selectedFactorId === 'transit' || this.selectedFactorId === 'recycle') && index === 2;
    if (!this.recordManualAmount) this.amountText = this.scenarioAmount(index);
  }

  private chooseRecordFactor(factor: CarbonFactor): void {
    this.selectedFactorId = factor.id;
    this.recordScenarioIndex = -1;
    this.recordManualAmount = false;
    this.amountText = '1';
  }

  private getRecordFilter(): string | undefined {
    return this.recordFactorFilter === 'all' ? undefined : this.recordFactorFilter;
  }

  private getTrendBuckets(): RecordBucket[] {
    return buildTrendBuckets(this.records, this.recordPeriod, new Date(), this.getRecordFilter());
  }

  private getVisibleRecords(): CarbonRecord[] {
    return filterRecordsForPeriod(this.records, this.recordPeriod, new Date(), this.getRecordFilter());
  }

  private getTrendTotalReduction(): number {
    let total: number = 0;
    for (const bucket of this.getTrendBuckets()) {
      total += bucket.reductionKg;
    }
    return total;
  }

  private getTrendTotalPoints(): number {
    let total: number = 0;
    for (const bucket of this.getTrendBuckets()) {
      total += bucket.points;
    }
    return total;
  }

  private getTrendMaxReduction(): number {
    let max: number = 0;
    for (const bucket of this.getTrendBuckets()) {
      if (bucket.reductionKg > max) {
        max = bucket.reductionKg;
      }
    }
    return max;
  }

  private periodLabel(): string {
    if (this.recordPeriod === 'day') {
      return '今日';
    }
    if (this.recordPeriod === 'month') {
      return '本月';
    }
    if (this.recordPeriod === 'year') {
      return '今年';
    }
    return '本周';
  }

  private async exportBackup(): Promise<void> {
    if (carbonContext === null) {
      this.notice = '当前没有可用的系统文件选择器。';
      return;
    }
    try {
      const saved: boolean = await saveTextWithPicker(carbonContext, 'carbonloop-backup.json', 'json', createCarbonBackup(this.records, this.challengeJoined));
      this.notice = saved ? 'JSON 备份已保存。' : '已取消备份保存。';
    } catch (error) {
      this.notice = '备份失败，请检查文件权限或存储空间。';
      console.error('CarbonLoop backup failed: ' + error);
    }
  }

  private async exportCsv(): Promise<void> {
    if (carbonContext === null) {
      this.notice = '当前没有可用的系统文件选择器。';
      return;
    }
    try {
      const saved: boolean = await saveTextWithPicker(carbonContext, 'carbonloop-records.csv', 'csv', createRecordsCsv(this.records));
      this.notice = saved ? 'CSV 明细已保存。' : '已取消明细导出。';
    } catch (error) {
      this.notice = '导出失败，请检查文件权限或存储空间。';
      console.error('CarbonLoop CSV export failed: ' + error);
    }
  }

  private async importBackup(): Promise<void> {
    if (carbonContext === null) {
      this.notice = '当前没有可用的系统文件选择器。';
      return;
    }
    try {
      const text: string | null = await readBackupWithPicker(carbonContext);
      if (text === null) {
        this.notice = '已取消备份恢复。';
        return;
      }
      const backup = parseCarbonBackup(text);
      this.records = mergeCarbonRecords(this.records, backup.data.records);
      for (const record of this.records) {
        record.syncStatus = 'pending';
        record.syncOperation = 'create';
      }
      this.challengeJoined = this.challengeJoined || backup.data.challengeJoined;
      saveRecords(carbonPreferences, this.records);
      saveChallengeJoined(carbonPreferences, this.challengeJoined);
      this.refreshPendingSyncCount();
      this.notice = `已恢复 ${backup.data.records.length} 条记录，联网后会自动同步。`;
    } catch (error) {
      this.notice = '恢复失败：备份文件格式或内容无效。';
      console.error('CarbonLoop backup restore failed: ' + error);
    }
  }

  private getVisibleArticles(): KnowledgeArticle[] {
    if (this.knowledgeCategory === '全部') {
      return KNOWLEDGE_ARTICLES;
    }
    return KNOWLEDGE_ARTICLES.filter((article: KnowledgeArticle) => article.category === this.knowledgeCategory);
  }

  private openRecord(factorId: string, amount: string): void {
    this.selectedFactorId = factorId;
    this.amountText = amount;
    this.recordComposerOpen = true;
    this.recordManualAmount = false;
    this.recordScenarioIndex = factorId === 'walk' && amount === '3' ? 1 : 0;
    this.occurredDateText = this.todayDateText();
    this.editingRecordId = '';
    this.currentTab = 2;
  }

  private openArticle(article: KnowledgeArticle): void {
    this.selectedArticleId = article.id;
    this.currentTab = 6;
  }

  @Builder
  private pageHeader(section: string, title: string, subtitle: string) {
    Column({ space: 6 }) {
      Text(section)
        .fontSize(14)
        .fontColor('#D9F99D')
        .fontWeight(FontWeight.Bold)
        .letterSpacing(0);
      Text(title)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.ink);
      Text(subtitle)
        .fontSize(13)
        .fontColor('#D7EFDF');
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(20)
    .backgroundColor('#B828715F')
    .borderRadius(24);
  }

  @Builder
  private brandBar() {
    Row({ space: 12 }) {
      Text('C')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor('#17443D')
        .backgroundColor('#9DE4BD')
        .width(42)
        .height(42)
        .textAlign(TextAlign.Center)
        .borderRadius(15);
      Column({ space: 2 }) {
        Text('CarbonLoop').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink);
        Text('碳行校园 · 低碳生活闭环助手').fontSize(11).fontColor(this.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Button('林')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#17443D')
        .backgroundColor('#D6F59A')
        .width(40)
        .height(40)
        .borderRadius(20)
        .onClick(() => this.currentTab = 5);
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 14, bottom: 10 });
  }

  @Builder
  private sectionTitle(title: string, detail: string) {
    Row() {
      Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.ink);
      Blank();
      Text(detail).fontSize(11).fontColor(this.muted);
    }
    .width('100%')
    .padding({ top: 4, bottom: 10 });
  }

  @Builder
  private flatMetric(label: string, value: string, unit: string, note: string) {
    Column({ space: 5 }) {
      Text(label).fontSize(12).fontColor(this.muted);
      Row({ space: 4 }) {
        Text(value).fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.ink);
        Text(unit).fontSize(12).fontColor(this.muted).margin({ top: 8 });
      }
      Text(note).fontSize(11).fontColor(this.accent);
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(14)
    .backgroundColor(this.panel)
    .borderRadius(18);
  }

  @Builder
  private homeView() {
    Scroll() {
      Column({ space: 16 }) {
        this.pageHeader('碳账本', '今天的低碳记录', '把每天的绿色选择，留下可查看的记录。');

        Row() {
          this.flatMetric('累计减排', formatKg(this.calculateTotalReduction()), 'kg', 'CO₂e 估算');
          Divider().vertical(true).height(58).color(this.line);
          this.flatMetric('碳积分', `${this.calculateTotalPoints()}`, '分', '持续积累');
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 });

        Column({ space: 0 }) {
          this.sectionTitle('今日任务', this.getDailyTaskProgress() >= 1 ? '已完成' : '可完成');
          Row({ space: 14 }) {
            Text('01').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.accent).width(24);
            Column({ space: 5 }) {
              Text('今日少用一次性用品').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.ink);
              Text(`${this.getDailyTaskProgress()} / 1 次 · 完成任务可获得额外积分`).fontSize(12).fontColor(this.muted);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Button('记录')
              .fontSize(12)
              .fontColor(this.accent)
              .backgroundColor(this.mint)
              .borderRadius(4)
              .onClick(() => this.openRecord('reusable', '1'));
          }
          .width('100%')
          .padding({ top: 12, bottom: 15 })
          .border({ width: { bottom: 1 }, color: this.line });
        }
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);

        Column({ space: 0 }) {
          this.sectionTitle('本周挑战', this.challengeJoined ? '进行中' : '可加入');
          Row({ space: 14 }) {
            Text('15').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.accent).width(40);
            Column({ space: 4 }) {
              Text('步行与骑行 15 公里').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.ink);
              Text(`${this.getChallengeProgress()} km 已完成`).fontSize(12).fontColor(this.muted);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Button('查看')
              .fontSize(12)
              .fontColor(this.accent)
              .backgroundColor(this.mint)
              .borderRadius(4)
              .onClick(() => this.currentTab = 3);
          }
          .width('100%');
          Progress({ value: this.getChallengeProgress(), total: 15 })
            .color(this.accent)
            .backgroundColor('#2B4A45')
            .margin({ top: 12, bottom: 5 });
        }
        .padding({ top: 2, bottom: 16 })
        .backgroundColor(this.panel)
        .borderRadius(20)
        .padding(18);

        Column({ space: 0 }) {
          this.sectionTitle('旧物第二人生', `${this.items.length} 件在流转`);
          Row({ space: 14 }) {
            Text('物').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.ink).backgroundColor(this.accent).width(30).height(30).textAlign(TextAlign.Center).borderRadius(8);
            Column({ space: 4 }) {
              Text('登记一件旧物，给它新的去处').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.ink);
              Text('交换、捐赠、维修或回收，形成可追踪的流转卡片').fontSize(12).fontColor(this.muted);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Button('进入')
              .fontSize(12)
              .fontColor(this.accent)
              .backgroundColor(this.mint)
              .borderRadius(4)
              .onClick(() => this.currentTab = 4);
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 });
        }
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);

        Column({ space: 0 }) {
          this.sectionTitle('个人趋势', '日 / 周 / 月 / 年');
          Row({ space: 14 }) {
            Text('趋').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.ink).backgroundColor(this.accent).width(30).height(30).textAlign(TextAlign.Center).borderRadius(4);
            Column({ space: 4 }) {
              Text('近期估算减排').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.ink);
              Text(formatKg(this.getTrendTotalReduction()) + ' kg CO₂e · ' + this.getVisibleRecords().length + ' 笔行为').fontSize(12).fontColor(this.muted);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Button('查看')
              .fontSize(12)
              .fontColor(this.accent)
              .backgroundColor(this.mint)
              .borderRadius(4)
              .onClick(() => this.currentTab = 1);
          }
          .width('100%')
          .padding({ top: 12, bottom: 15 })
          .border({ width: { bottom: 1 }, color: this.line });
        }
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);

        Column({ space: 0 }) {
          this.sectionTitle('最近记录', `${this.records.length} 笔`);
          ForEach(this.records.slice(0, 3), (record: CarbonRecord, index: number) => {
            this.recordRow(record, index === 0);
          }, (record: CarbonRecord) => `home-${record.id}`);
          Button('查看全部记录')
            .fontSize(12)
            .fontColor(this.accent)
            .backgroundColor(this.mint)
            .borderRadius(4)
            .margin({ top: 10 })
            .onClick(() => this.currentTab = 2);
        }
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);
      }
      .padding({ left: 16, right: 16, top: 16, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private challengeView() {
    Scroll() {
      Column({ space: 16 }) {
        this.pageHeader('校园挑战', '步行与骑行周', '用 15 公里的绿色出行，换一枚低碳徽章。');

        Column({ space: 12 }) {
          Row() {
            Column({ space: 3 }) {
              Text('已完成').fontSize(12).fontColor(this.muted);
              Text(`${this.getChallengeProgress()} km`).fontSize(34).fontWeight(FontWeight.Bold).fontColor(this.ink);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Column({ space: 3 }) {
              Text('目标').fontSize(12).fontColor(this.muted);
              Text('15 km').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.accent);
            }.alignItems(HorizontalAlign.End);
          }
          Progress({ value: this.getChallengeProgress(), total: 15 })
            .color(this.accent)
            .backgroundColor('#2B4A45')
            .margin({ top: 4, bottom: 4 });
          Text(this.challengeJoined ? '挑战已加入，完成记录会自动计入进度。' : '加入后，步行与骑行记录会自动计入本周进度。')
            .fontSize(12)
            .fontColor(this.muted);
          Button(this.challengeJoined ? '去记录一笔' : '加入本周挑战')
            .width('100%')
            .fontSize(14)
            .fontColor(this.ink)
            .backgroundColor(this.accent)
            .borderRadius(4)
            .margin({ top: 6 })
            .onClick(() => {
              if (this.challengeJoined) {
                this.openRecord('walk', '3');
              } else {
                this.joinChallenge();
              }
            });
          if (this.challengeNotice.length > 0) {
            Text(this.challengeNotice).fontSize(12).fontColor(this.accent);
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);

        Column({ space: 0 }) {
          this.sectionTitle('挑战规则', '3 条');
          this.ruleRow('01', '仅步行与骑行出行会计入本次里程。');
          this.ruleRow('02', '每次记录同时获得碳积分与减排量。');
          this.ruleRow('03', '完成 15 公里后，解锁“绿色出发”徽章。');
        }
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);

        Column({ space: 0 }) {
          this.sectionTitle('相关记录', `${this.records.filter((record: CarbonRecord) => record.factorId === 'walk').length} 笔`);
          ForEach(this.records, (record: CarbonRecord) => {
            if (record.factorId === 'walk') {
              this.recordRow(record, true);
            }
          }, (record: CarbonRecord) => `challenge-${record.id}`);
        }
      }
        .padding({ left: 16, right: 16, top: 16, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private itemFlowButton(label: string, flow: string) {
    Button(label)
      .layoutWeight(1)
      .fontSize(11)
      .fontColor(this.itemFlow === flow ? '#FFFFFF' : this.accent)
      .backgroundColor(this.itemFlow === flow ? this.accent : '#E7F0EC')
      .borderRadius(4)
      .onClick(() => this.itemFlow = flow);
  }

  @Builder
  private itemCard(item: ApiItem) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Text('物')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.ink)
          .backgroundColor(this.accent)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .borderRadius(8);
        Column({ space: 3 }) {
          Text(item.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.ink);
          Text(`${item.itemType} · ${item.weightKg} kg · ${item.status}`).fontSize(11).fontColor(this.muted);
          Text(item.workflowStatusLabel).fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.accent);
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Text(`${item.cycleCount} 次`).fontSize(12).fontColor(this.accent);
      }
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text('累计估算减排').fontSize(10).fontColor(this.muted);
          Text(`${formatKg(item.reductionKg)} kg`).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.accent);
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Column({ space: 3 }) {
          Text('首次登记积分').fontSize(10).fontColor(this.muted);
          Text(`+${item.points} 分`).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#9A6528');
        }.alignItems(HorizontalAlign.End);
      }
      if (item.events.length > 0) {
        Text(`最近：${item.events[0].label} · ${item.events[0].createdAt.slice(0, 10)}`)
          .fontSize(11)
          .fontColor(this.muted);
      }
      if (item.appointment !== null && item.appointment !== undefined) {
        Text(`${item.appointment.type === 'delivery' ? '投递' : '领取'} · ${item.appointment.stationName} · ${item.appointment.slot}`)
          .fontSize(11)
          .fontColor(this.muted);
        if (item.appointment.state === 'active') {
          Text(`核销码 ${item.appointment.code}`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#9A6528')
            .letterSpacing(2);
        }
      }
      if (item.workflowStatus === 'APPROVED') {
        Button('预约投递')
          .width('100%')
          .fontSize(12)
          .fontColor(this.ink)
          .backgroundColor(this.accent)
          .borderRadius(4)
          .onClick(() => this.bookDelivery(item));
      } else if (item.workflowStatus === 'IN_STOCK') {
        Button('预约领取')
          .width('100%')
          .fontSize(12)
          .fontColor(this.ink)
          .backgroundColor(this.accent)
          .borderRadius(4)
          .onClick(() => this.reservePickup(item));
      } else {
        Text(this.workflowActionLabel(item)).fontSize(11).fontColor(this.muted);
      }
      Row({ space: 6 }) {
        this.itemEventButton(item, '交换', 'exchange');
        this.itemEventButton(item, '捐赠', 'donate');
        this.itemEventButton(item, '维修', 'repair');
        this.itemEventButton(item, '回收', 'recycle');
      }
      .width('100%');
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(this.panel)
    .borderRadius(20);
  }

  @Builder
  private itemEventButton(item: ApiItem, label: string, flow: string) {
    Button(label)
      .layoutWeight(1)
      .fontSize(10)
      .fontColor(item.flow === flow ? '#153A34' : this.accent)
      .backgroundColor(item.flow === flow ? this.accent : this.mint)
      .borderRadius(4)
      .onClick(() => this.advanceItem(item, flow));
  }

  @Builder
  private itemView() {
    Scroll() {
      Column({ space: 16 }) {
        this.pageHeader('旧物第二人生', '让一件物品继续被需要', '登记、交换、捐赠、维修或回收，留下可追踪的流转记录。');

        Column({ space: 8 }) {
          this.sectionTitle('登记一件旧物', '生成第二人生卡片');
          Text('首次登记会按旧物回收因子生成一笔碳账本行动；后续流转只更新状态，不重复增加积分。')
            .fontSize(11)
            .fontColor(this.muted)
            .lineHeight(18);
          TextInput({ text: this.itemTitle, placeholder: '物品名称，例如：大一教材' })
            .fontSize(14)
            .fontColor(this.ink)
            .onChange((value: string) => this.itemTitle = value)
            .backgroundColor(this.panel)
            .border({ width: 1, color: this.line })
            .borderRadius(4)
            .padding({ left: 14, right: 14 });
          TextInput({ text: this.itemType, placeholder: '物品类型，例如：书籍、衣物、小家电' })
            .fontSize(14)
            .fontColor(this.ink)
            .onChange((value: string) => this.itemType = value)
            .backgroundColor(this.panel)
            .border({ width: 1, color: this.line })
            .borderRadius(4)
            .padding({ left: 14, right: 14 });
          Row({ space: 10 }) {
            Column({ space: 3 }) {
              Text('重量（kg）').fontSize(12).fontColor(this.muted);
              TextInput({ text: this.itemWeightText, placeholder: '例如 1.5' })
                .type(InputType.Number)
                .fontSize(14)
                .fontColor(this.ink)
                .onChange((value: string) => this.itemWeightText = value)
                .backgroundColor(this.panel)
                .border({ width: 1, color: this.line })
                .borderRadius(4)
                .padding({ left: 12, right: 12 });
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Column({ space: 3 }) {
              Text('首个去向').fontSize(12).fontColor(this.muted);
              Text(this.itemFlowLabel(this.itemFlow)).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.accent);
            }.alignItems(HorizontalAlign.End).layoutWeight(1);
          }
          Row({ space: 6 }) {
            this.itemFlowButton('交换', 'exchange');
            this.itemFlowButton('捐赠', 'donate');
            this.itemFlowButton('维修', 'repair');
            this.itemFlowButton('回收', 'recycle');
          }
          .width('100%');
          Button('登记并生成卡片')
            .width('100%')
            .fontSize(14)
            .fontColor(this.ink)
            .backgroundColor(this.accent)
            .borderRadius(4)
            .onClick(() => this.createItem());
          if (this.itemNotice.length > 0) {
            Text(this.itemNotice).fontSize(11).fontColor(this.accent).lineHeight(18);
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);

        Column({ space: 10 }) {
          this.sectionTitle('我的旧物卡片', `${this.items.length} 件`);
          if (this.items.length === 0) {
            Text('还没有旧物记录，先登记一件物品，让它获得新的去处。')
              .fontSize(12)
              .fontColor(this.muted)
              .padding({ top: 10, bottom: 10 });
          }
          ForEach(this.items, (item: ApiItem) => {
            this.itemCard(item);
          }, (item: ApiItem) => `item-${item.id}`);
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#142B2A')
        .borderRadius(20);
      }
      .padding({ left: 16, right: 16, top: 16, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private ruleRow(number: string, text: string) {
    Row({ space: 14 }) {
      Text(number).fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.accent).width(24);
      Text(text).fontSize(13).fontColor(this.ink).layoutWeight(1);
    }
    .width('100%')
    .padding({ top: 11, bottom: 11 })
    .border({ width: { bottom: 1 }, color: this.line });
  }

  @Builder
  private recordView() {
    Scroll() {
      Column({ space: 16 }) {
        this.pageHeader('碳账本', '记录与趋势', '记录低碳行为，按时间和类别回看自己的行动。');

        Row({ space: 8 }) {
          this.periodButton('日', 'day');
          this.periodButton('周', 'week');
          this.periodButton('月', 'month');
          this.periodButton('年', 'year');
        }
        .width('100%')
        .padding({ bottom: 2 });

        Row({ space: 10 }) {
          this.statChip('区间减排', formatKg(this.getTrendTotalReduction()) + ' kg');
          this.statChip('区间积分', this.getTrendTotalPoints() + ' 分');
          this.statChip('记录数', this.getVisibleRecords().length + ' 笔');
        }
        .width('100%');

        Button(this.recordComposerOpen ? '收起记录入口' : '＋ 新增一笔低碳行为')
          .width('100%')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#153A34')
          .backgroundColor(this.accent)
          .borderRadius(14)
          .onClick(() => this.recordComposerOpen = !this.recordComposerOpen);

        Column({ space: 8 }) {
          this.sectionTitle('减排趋势', '估算值');
          ForEach(this.getTrendBuckets(), (bucket: RecordBucket) => {
            Row({ space: 8 }) {
              Text(bucket.label).fontSize(10).fontColor(this.muted).width(34);
              Progress({ value: bucket.reductionKg, total: Math.max(0.01, this.getTrendMaxReduction()) })
                .color(this.accent)
                .backgroundColor(this.mint)
                .layoutWeight(1)
                .height(8);
              Text(formatKg(bucket.reductionKg)).fontSize(10).fontColor(this.muted).width(40).textAlign(TextAlign.End);
            }
            .height(18);
          }, (bucket: RecordBucket) => 'trend-' + bucket.key);
          Text('减排量均为基于当前因子口径的估算，不等同于核证碳资产。')
            .fontSize(10)
            .fontColor(this.muted)
            .padding({ top: 4 });
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);

        if (this.recordComposerOpen) {
          Column({ space: 12 }) {
            this.sectionTitle('今天做了什么？', '先选行为');
            ForEach(CARBON_FACTORS, (factor: CarbonFactor) => {
              this.factorChoice(factor);
            }, (factor: CarbonFactor) => 'choice-' + factor.id);
            Text(this.scenarioHint()).fontSize(11).fontColor(this.muted).lineHeight(18);
            if (this.recordScenarioIndex >= 0) {
              Text('具体情境').fontSize(13).fontColor(this.muted);
              ForEach(this.scenarioLabels(), (label: string, index: number) => {
                Button(label)
                  .width('100%')
                  .fontSize(13)
                  .fontColor(index === this.recordScenarioIndex ? '#153A34' : this.accent)
                  .backgroundColor(index === this.recordScenarioIndex ? this.accent : this.mint)
                  .borderRadius(10)
                  .onClick(() => this.chooseScenario(index));
              }, (label: string, index: number) => `scenario-${index}-${label}`);
            }
            if (this.recordManualAmount) {
              Text(`实际${this.getSelectedFactor().unit}`).fontSize(13).fontColor(this.muted);
              TextInput({ text: this.amountText, placeholder: `填写${this.getSelectedFactor().unit}` })
                .type(InputType.Number)
                .fontSize(18)
                .fontColor(this.ink)
                .onChange((value: string) => this.amountText = value)
                .backgroundColor(this.panel)
                .border({ width: 1, color: this.line })
                .borderRadius(10)
                .padding({ left: 14, right: 14 });
            }
            Text('发生日期（YYYY-MM-DD）').fontSize(13).fontColor(this.muted);
            TextInput({ text: this.occurredDateText, placeholder: '今天' })
              .fontSize(15)
              .fontColor(this.ink)
              .onChange((value: string) => this.occurredDateText = value)
              .backgroundColor(this.panel)
              .border({ width: 1, color: this.line })
              .borderRadius(10)
              .padding({ left: 14, right: 14 });
            Row() {
              Column({ space: 3 }) {
                Text('系统估算').fontSize(12).fontColor(this.muted);
                if (this.getPreviewIsBehaviorOnly()) {
                  Text('记录行为').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.accent);
                } else {
                  Text(`${formatKg(this.getPreviewReduction())} kg CO₂e`).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.accent);
                }
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);
              Column({ space: 3 }) {
                Text('获得积分').fontSize(12).fontColor(this.muted);
                Text(`+${this.getPreviewPoints()} 分`).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#F2BF75');
              }.alignItems(HorizontalAlign.End);
            }
            .padding({ top: 8, bottom: 6 });
            Button('保存到碳账本')
              .width('100%')
              .fontSize(14)
              .fontColor('#153A34')
              .backgroundColor(this.accent)
              .borderRadius(10)
              .enabled(this.recordScenarioIndex >= 0)
              .onClick(() => this.saveRecord());
            if (this.recordScenarioIndex < 0) {
              Text('先选择一个具体情境，系统会自动带入记录数量。').fontSize(11).fontColor(this.muted);
            }
            if (this.notice.length > 0) {
              Text(this.notice).fontSize(12).fontColor(this.accent);
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(18)
          .backgroundColor(this.panel)
          .borderRadius(20);
        }

        Column({ space: 0 }) {
          this.sectionTitle('最近记录', `${this.records.length} 笔`);
          ForEach(this.records, (record: CarbonRecord, index: number) => {
            this.recordRow(record, index === 0);
          }, (record: CarbonRecord) => `record-${record.id}`);
        }
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);
      }
        .padding({ left: 16, right: 16, top: 16, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private historyView() {
    Scroll() {
      Column({ space: 16 }) {
        this.pageHeader('个人趋势', '减排与积分', '按日、周、月、年回顾低碳行动。');
        Row({ space: 8 }) {
          this.periodButton('日', 'day');
          this.periodButton('周', 'week');
          this.periodButton('月', 'month');
          this.periodButton('年', 'year');
        }
        .width('100%');

        Row({ space: 10 }) {
          this.statChip('区间减排', formatKg(this.getTrendTotalReduction()) + ' kg');
          this.statChip('区间积分', this.getTrendTotalPoints() + ' 分');
          this.statChip('行为次数', this.getVisibleRecords().length + ' 次');
        }
        .width('100%');

        Column({ space: 8 }) {
          this.sectionTitle('减排趋势', 'kg CO₂e 估算');
          ForEach(this.getTrendBuckets(), (bucket: RecordBucket) => {
            Row({ space: 8 }) {
              Text(bucket.label).fontSize(10).fontColor(this.muted).width(34);
              Progress({ value: bucket.reductionKg, total: Math.max(0.01, this.getTrendMaxReduction()) })
                .color(this.accent)
                .backgroundColor(this.mint)
                .layoutWeight(1)
                .height(8);
              Text(formatKg(bucket.reductionKg)).fontSize(10).fontColor(this.muted).width(40).textAlign(TextAlign.End);
            }
            .height(18);
          }, (bucket: RecordBucket) => 'trend-' + bucket.key);
          Text('所有减排量均为估算值；因子来源和适用边界仍需正式复核。')
            .fontSize(10)
            .fontColor(this.muted)
            .padding({ top: 4 });
        }
        .padding({ top: 8, bottom: 10 })
        .border({ width: { bottom: 1 }, color: this.line });

        Scroll() {
          Row({ space: 8 }) {
            this.factorFilterButton('全部', 'all');
            ForEach(CARBON_FACTORS, (factor: CarbonFactor) => {
              this.factorFilterButton(factor.label, factor.id);
            }, (factor: CarbonFactor) => 'history-filter-' + factor.id);
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .width('100%')
        .height(40);

        Column({ space: 0 }) {
          this.sectionTitle(this.periodLabel() + '记录', this.getVisibleRecords().length + ' 笔');
          ForEach(this.getVisibleRecords(), (record: CarbonRecord, index: number) => {
            this.recordRow(record, index === 0);
          }, (record: CarbonRecord) => 'history-' + record.id);
          if (this.getVisibleRecords().length === 0) {
            Text('这个时间范围内还没有记录，记下第一笔低碳行动吧。')
              .fontSize(12)
              .fontColor(this.muted)
              .padding({ top: 14, bottom: 14 });
          }
        }
      }
      .padding({ left: 16, right: 16, top: 16, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private knowledgeView() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.selectedArticleId.length > 0) {
          this.pageHeader(findArticle(this.selectedArticleId).category, findArticle(this.selectedArticleId).title, findArticle(this.selectedArticleId).updatedAt + ' 更新 · 离线可读');
          Text(findArticle(this.selectedArticleId).body)
            .fontSize(14)
            .fontColor(this.ink)
            .lineHeight(26)
            .width('100%');
          Text(findArticle(this.selectedArticleId).source)
            .fontSize(11)
            .fontColor(this.muted)
            .lineHeight(20)
            .width('100%')
            .padding({ top: 14, bottom: 14 })
            .border({ width: { top: 1 }, color: this.line });
          Button('返回科普列表')
            .fontSize(13)
            .fontColor(this.accent)
            .backgroundColor(this.mint)
            .borderRadius(4)
            .onClick(() => this.selectedArticleId = '');
        } else {
          this.pageHeader('双碳科普', '低碳生活指南', '把每一次选择背后的原因讲清楚。');
          Scroll() {
            Row({ space: 8 }) {
              this.knowledgeCategoryButton('全部');
              this.knowledgeCategoryButton('双碳科普');
              this.knowledgeCategoryButton('绿色出行');
              this.knowledgeCategoryButton('节能节水');
              this.knowledgeCategoryButton('光盘行动');
              this.knowledgeCategoryButton('旧物循环');
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .width('100%')
          .height(40);
          ForEach(this.getVisibleArticles(), (article: KnowledgeArticle) => {
            Column({ space: 6 }) {
              Text(article.category).fontSize(11).fontColor(this.accent).fontWeight(FontWeight.Bold);
              Text(article.title).fontSize(16).fontColor(this.ink).fontWeight(FontWeight.Medium);
              Text(article.summary).fontSize(12).fontColor(this.muted).lineHeight(19);
              Text(article.updatedAt + ' · 查看全文').fontSize(10).fontColor(this.muted);
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ top: 14, bottom: 14 })
            .border({ width: { bottom: 1 }, color: this.line })
            .onClick(() => this.openArticle(article));
          }, (article: KnowledgeArticle) => 'article-' + article.id);
        }
      }
      .padding({ left: 22, right: 22, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private knowledgeCategoryButton(category: string) {
    Button(category)
      .fontSize(11)
      .fontColor(this.knowledgeCategory === category ? '#FFFFFF' : this.accent)
      .backgroundColor(this.knowledgeCategory === category ? this.accent : '#E7F0EC')
      .borderRadius(4)
      .padding({ left: 10, right: 10 })
      .onClick(() => this.knowledgeCategory = category);
  }

  @Builder
  private periodButton(label: string, period: RecordPeriod) {
    Button(label)
      .layoutWeight(1)
      .fontSize(12)
      .fontColor(this.recordPeriod === period ? '#FFFFFF' : this.accent)
      .backgroundColor(this.recordPeriod === period ? this.accent : '#E7F0EC')
      .borderRadius(4)
      .onClick(() => this.recordPeriod = period);
  }

  @Builder
  private factorFilterButton(label: string, factorId: string) {
    Button(label)
      .fontSize(11)
      .fontColor(this.recordFactorFilter === factorId ? '#FFFFFF' : this.accent)
      .backgroundColor(this.recordFactorFilter === factorId ? this.accent : '#E7F0EC')
      .borderRadius(4)
      .padding({ left: 10, right: 10 })
      .onClick(() => this.recordFactorFilter = factorId);
  }

  @Builder
  private statChip(label: string, value: string) {
    Column({ space: 3 }) {
      Text(label).fontSize(10).fontColor(this.muted);
      Text(value).fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.ink);
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8, left: 8, right: 8 })
    .backgroundColor(this.panel)
    .borderRadius(4);
  }

  @Builder
  private factorChoice(factor: CarbonFactor) {
    Row({ space: 12 }) {
      Text(factor.icon)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(factor.id === this.selectedFactorId ? '#153A34' : this.accent)
        .backgroundColor(factor.id === this.selectedFactorId ? this.accent : this.mint)
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .borderRadius(4);
      Column({ space: 3 }) {
        Text(factor.label).fontSize(14).fontColor(this.ink).fontWeight(factor.id === this.selectedFactorId ? FontWeight.Bold : FontWeight.Medium);
        Text(factor.calculationStatus === 'behavior_only'
          ? `仅记录行为 · 每${factor.unit} ${factor.pointsPerUnit} 分`
          : `每${factor.unit}减排 ${factor.reductionKgPerUnit.toFixed(2)} kg · ${factor.pointsPerUnit} 分`)
          .fontSize(11)
          .fontColor(this.muted);
        Text(factor.baseline)
          .fontSize(10)
          .fontColor(this.muted)
          .maxLines(1);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Text(factor.id === this.selectedFactorId ? '已选' : '选择')
        .fontSize(11)
        .fontColor(factor.id === this.selectedFactorId ? this.accent : this.muted);
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: this.line })
    .onClick(() => this.chooseRecordFactor(factor));
  }

  @Builder
  private recordRow(record: CarbonRecord, first: boolean) {
    Row({ space: 12 }) {
      Text(findFactor(record.factorId).icon)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accent)
        .backgroundColor(this.mint)
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .borderRadius(4);
      Column({ space: 3 }) {
        Text(findFactor(record.factorId).label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.ink);
        Text(`${record.amount} ${findFactor(record.factorId).unit} · ${record.occurredAt.length > 0 ? record.occurredAt : '日期待补'}`).fontSize(11).fontColor(this.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Column({ space: 3 }) {
        Text(findFactor(record.factorId).calculationStatus === 'behavior_only' ? '行为记录' : `-${formatKg(record.reductionKg)} kg`).fontSize(13).fontColor(this.accent);
        Text(`+${record.points} 分`).fontSize(11).fontColor('#9A6528');
      }.alignItems(HorizontalAlign.End);
    }
    .width('100%')
    .padding({ top: 11, bottom: 11 })
    .border({ width: { bottom: 1 }, color: this.line });
    Row({ space: 8 }) {
      Text(record.syncStatus === 'synced' ? '已同步' : '待同步').fontSize(10).fontColor(this.muted).layoutWeight(1);
      Button('修改').fontSize(10).fontColor(this.accent).backgroundColor(this.mint).borderRadius(4).onClick(() => this.editRecord(record));
      Button('删除').fontSize(10).fontColor('#9A4B3D').backgroundColor('#4A2A2A').borderRadius(4).onClick(() => this.deleteRecord(record));
    }
    .width('100%')
    .padding({ bottom: 9 });
  }

  @Builder
  private profileView() {
    Scroll() {
      Column({ space: 16 }) {
        this.pageHeader('我的', '我的碳账本', '所有数据都来自你记录的低碳行为。');

        Row() {
          this.flatMetric('累计减排', formatKg(this.calculateTotalReduction()), 'kg', 'CO₂e 估算');
          Divider().vertical(true).height(58).color(this.line);
          this.flatMetric('碳积分', `${this.calculateTotalPoints()}`, '分', '可持续累积');
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 });

        Column({ space: 0 }) {
          this.sectionTitle('本地数据管理', '离线可用');
          Text('导出包括行为明细、因子版本和自报状态；恢复采用去重合并，不覆盖当前记录。')
            .fontSize(11)
            .fontColor(this.muted)
            .lineHeight(18)
            .padding({ top: 6, bottom: 10 });
          Row({ space: 10 }) {
            Button('JSON 备份')
              .layoutWeight(1)
              .fontSize(12)
              .fontColor(this.accent)
              .backgroundColor(this.mint)
              .borderRadius(4)
              .onClick(() => this.exportBackup());
            Button('恢复 JSON')
              .layoutWeight(1)
              .fontSize(12)
              .fontColor(this.accent)
              .backgroundColor(this.mint)
              .borderRadius(4)
              .onClick(() => this.importBackup());
            Button('CSV 明细')
              .layoutWeight(1)
              .fontSize(12)
              .fontColor(this.accent)
              .backgroundColor(this.mint)
              .borderRadius(4)
              .onClick(() => this.exportCsv());
          }
          if (this.notice.length > 0) {
            Text(this.notice).fontSize(11).fontColor(this.accent).padding({ top: 8 });
          }
        }
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);

        Column({ space: 0 }) {
          this.sectionTitle('记录概览', '当前状态');
          this.summaryRow('数据连接', this.backendStatus);
          this.summaryRow('待同步数据', `${this.pendingSyncCount + this.pendingItemSyncCount} 条`);
          this.summaryRow('行为记录', `${this.records.length} 笔`);
          this.summaryRow('挑战状态', this.challengeJoined ? '已加入本周挑战' : '尚未加入挑战');
          this.summaryRow('步行与骑行', `${this.getChallengeProgress()} / 15 km`);
        }
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);

        Button('重试同步')
          .width('100%')
          .fontSize(12)
          .fontColor(this.accent)
          .backgroundColor(this.mint)
          .borderRadius(14)
          .onClick(() => this.retrySync());

        Column({ space: 0 }) {
          this.sectionTitle('低碳徽章', '记录进度');
          this.badgeRow('01', '绿色起点', '完成第一笔低碳行为', this.records.length >= 1);
          this.badgeRow('02', '减排新星', '累计减排达到 1 kg CO₂e', this.calculateTotalReduction() >= 1);
          this.badgeRow('03', '校园挑战者', '加入一次校园低碳挑战', this.challengeJoined);
          this.badgeRow('04', '持续行动', '累计完成 5 次记录', this.records.length >= 5);
        }
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);

        Column({ space: 0 }) {
          this.sectionTitle('积分兑换', '虚拟权益');
          Text('兑换结果会写入云端积分流水，徽章和证书不会重复扣分。')
            .fontSize(11)
            .fontColor(this.muted)
            .lineHeight(18)
            .padding({ top: 6, bottom: 8 });
          ForEach(this.rewards, (reward: ApiReward) => {
            Row({ space: 8 }) {
              Column({ space: 3 }) {
                Text(reward.name).fontSize(13).fontColor(this.ink).fontWeight(FontWeight.Medium);
                Text(`${reward.description} · ${reward.cost} 分`).fontSize(11).fontColor(this.muted);
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);
              Button(reward.redeemed ? '已兑换' : reward.canRedeem ? '兑换' : '积分不足')
                .fontSize(11)
                .fontColor(reward.redeemed || !reward.canRedeem ? this.muted : this.accent)
                .backgroundColor(reward.redeemed || !reward.canRedeem ? '#EEF1EF' : '#E7F0EC')
                .borderRadius(4)
                .enabled(!reward.redeemed && reward.canRedeem)
                .onClick(() => this.redeemReward(reward));
            }
            .padding({ top: 10, bottom: 10 })
            .border({ width: { bottom: 1 }, color: this.line });
          }, (reward: ApiReward) => `reward-${reward.id}`);
          if (this.rewardNotice.length > 0) {
            Text(this.rewardNotice).fontSize(11).fontColor(this.accent).padding({ top: 8 });
          }
        }
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(20);

        Column({ space: 0 }) {
          this.sectionTitle('积分明细', '按记录累计');
          ForEach(this.records.slice(0, 5), (record: CarbonRecord) => {
            Row() {
              Text(findFactor(record.factorId).label).fontSize(13).fontColor(this.ink).layoutWeight(1);
              Text(`+${record.points} 分`).fontSize(13).fontColor('#9A6528');
            }
            .padding({ top: 10, bottom: 10 })
            .border({ width: { bottom: 1 }, color: this.line });
          }, (record: CarbonRecord) => `points-${record.id}`);
        }
        .padding(18)
        .backgroundColor(this.panel)
        .borderRadius(20);
      }
        .padding({ left: 16, right: 16, top: 16, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private summaryRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor(this.muted).layoutWeight(1);
      Text(value).fontSize(13).fontColor(this.ink).fontWeight(FontWeight.Medium);
    }
    .padding({ top: 11, bottom: 11 })
    .border({ width: { bottom: 1 }, color: this.line });
  }

  @Builder
  private badgeRow(number: string, title: string, description: string, unlocked: boolean) {
    Row({ space: 12 }) {
      Text(number)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(unlocked ? '#FFFFFF' : this.muted)
        .backgroundColor(unlocked ? this.accent : '#E8ECEA')
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .borderRadius(4);
      Column({ space: 3 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(unlocked ? this.ink : this.muted);
        Text(description).fontSize(11).fontColor(this.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Text(unlocked ? '已解锁' : '未解锁').fontSize(11).fontColor(unlocked ? this.accent : this.muted);
    }
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: this.line });
  }

  private editRecord(record: CarbonRecord): void {
    this.selectedFactorId = record.factorId;
    this.amountText = '' + record.amount;
    this.occurredDateText = record.occurredAt.slice(0, 10);
    this.editingRecordId = record.id;
    this.recordComposerOpen = true;
    this.recordScenarioIndex = 0;
    this.recordManualAmount = true;
    this.currentTab = 2;
    this.notice = '已载入记录，请修改后保存。';
  }

  private async deleteRecord(record: CarbonRecord): Promise<void> {
    this.records = this.records.filter((candidate: CarbonRecord) => candidate.id !== record.id);
    saveRecords(carbonPreferences, this.records);
    if (record.syncStatus === 'synced') {
      this.deletedRecordIds = this.deletedRecordIds.includes(record.id) ? this.deletedRecordIds : [...this.deletedRecordIds, record.id];
      saveDeletedRecordIds(carbonPreferences, this.deletedRecordIds);
    }
    this.refreshPendingSyncCount();
    this.notice = `已删除 ${findFactor(record.factorId).label}`;
    if (record.syncStatus === 'synced') {
      try {
        await this.api.deleteRecord(record.id);
        this.deletedRecordIds = this.deletedRecordIds.filter((id: string) => id !== record.id);
        saveDeletedRecordIds(carbonPreferences, this.deletedRecordIds);
        this.notice = '记录已从云端撤销，积分和任务已回算。';
      } catch (error) {
        this.notice = '已从本机删除，云端撤销会在联网后重试。';
        console.error(`CarbonLoop delete skipped: ${error}`);
      }
    }
  }

  private saveRecord(): void {
    if (this.getPreviewAmount() <= 0) {
      this.notice = '请输入大于 0 的数量';
      return;
    }
    const occurredAt: string | null = this.parseOccurredAt();
    if (occurredAt === null) {
      this.notice = '请输入有效的发生日期（YYYY-MM-DD）';
      return;
    }
    const factor: CarbonFactor = this.getSelectedFactor();
    const now: string = new Date().toISOString();
    if (this.editingRecordId.length > 0) {
      const existing: CarbonRecord | undefined = this.records.find((record: CarbonRecord) => record.id === this.editingRecordId);
      if (existing !== undefined) {
        const updated: CarbonRecord = {
          id: existing.id,
          createdAt: existing.createdAt,
          verificationStatus: existing.verificationStatus,
          locationId: existing.locationId,
          factorId: factor.id,
          factorVersion: factor.version,
          amount: this.getPreviewAmount(),
          reductionKg: this.getPreviewReduction(),
          points: this.getPreviewPoints(),
          occurredAt,
          syncStatus: 'pending',
          syncOperation: 'update'
        };
        this.records = this.records.map((record: CarbonRecord) => record.id === existing.id ? updated : record);
        saveRecords(carbonPreferences, this.records);
        this.editingRecordId = '';
        this.refreshPendingSyncCount();
        this.notice = `已修改 ${factor.label}，等待同步…`;
        this.syncRecord(updated);
        return;
      }
    }
    const record: CarbonRecord = {
      id: `${Date.now()}`,
      factorId: factor.id,
      factorVersion: factor.version,
      amount: this.getPreviewAmount(),
      reductionKg: this.getPreviewReduction(),
      points: this.getPreviewPoints(),
      occurredAt,
      createdAt: now,
      verificationStatus: 'self_reported',
      locationId: undefined,
      syncStatus: 'pending',
      syncOperation: 'create'
    };
    this.records = [record, ...this.records];
    saveRecords(carbonPreferences, this.records);
    this.refreshPendingSyncCount();
    this.notice = `已记录 ${factor.label}，正在同步云端…`;
    this.syncRecord(record);
  }

  private syncedRecord(record: CarbonRecord, remote: ApiRecord): CarbonRecord {
    return {
      id: record.id,
      factorId: record.factorId,
      factorVersion: remote.factorVersion,
      amount: record.amount,
      reductionKg: remote.reductionKg,
      points: remote.points,
      occurredAt: record.occurredAt,
      createdAt: record.createdAt,
      verificationStatus: remote.verificationStatus ?? record.verificationStatus,
      locationId: record.locationId,
      syncStatus: 'synced',
      syncOperation: 'create'
    };
  }

  private async syncRecord(record: CarbonRecord): Promise<void> {
    try {
      const remote: ApiRecord = record.syncOperation === 'update'
        ? await this.api.updateRecord(record.id, record.factorId, record.amount, record.occurredAt)
        : await this.api.createRecord(record.id, record.factorId, record.amount, record.occurredAt, record.locationId);
      this.records = this.records.map((candidate: CarbonRecord): CarbonRecord => candidate.id === record.id
        ? this.syncedRecord(candidate, remote)
        : candidate);
      saveRecords(carbonPreferences, this.records);
      this.refreshPendingSyncCount();
      this.backendStatus = '云端已连接';
      const dashboard = await this.api.getDashboard();
      this.dailyTasks = dashboard.tasks ?? [];
      this.taskLedger = (dashboard.pointsLedger ?? []).filter((entry: ApiPointsLedgerEntry) => entry.taskId !== undefined);
      this.cloudPoints = dashboard.summary === undefined ? this.calculateLocalPoints() : dashboard.summary.totalPoints;
      await this.refreshRewards();
      this.notice = `已同步 ${findFactor(record.factorId).label}，获得 ${remote.points} 个积分`;
    } catch (error) {
      this.backendStatus = '离线可用';
      this.notice = `已保存在本机，联网后会自动同步`;
      console.error(`CarbonLoop record sync skipped: ${error}`);
    }
  }

  build() {
    Column() {
      this.brandBar();
      if (this.currentTab === 0) {
        this.homeView();
      } else if (this.currentTab === 1) {
        this.historyView();
      } else if (this.currentTab === 2) {
        this.recordView();
      } else if (this.currentTab === 3) {
        this.challengeView();
      } else if (this.currentTab === 4) {
        this.itemView();
      } else if (this.currentTab === 5) {
        this.profileView();
      } else if (this.currentTab === 6) {
        this.knowledgeView();
      }
      Row() {
        this.tabButton('首页', 0);
        this.tabButton('趋势', 1);
        this.tabButton('记录', 2);
        this.tabButton('挑战', 3);
        this.tabButton('旧物', 4);
        this.tabButton('我的', 5);
        this.tabButton('科普', 6);
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 12 })
      .border({ width: { top: 1 }, color: this.line })
      .backgroundColor('#101F1F');
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.page);
  }

  @Builder
  private tabButton(label: string, tab: number) {
    Button(label)
      .layoutWeight(1)
      .fontSize(13)
      .fontWeight(this.currentTab === tab ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.currentTab === tab ? this.accent : this.muted)
      .backgroundColor(this.currentTab === tab ? this.mint : '#101F1F')
      .borderRadius(4)
      .onClick(() => this.currentTab = tab);
  }
}
