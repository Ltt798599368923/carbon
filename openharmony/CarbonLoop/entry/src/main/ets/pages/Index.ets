import {
  CARBON_FACTORS,
  CarbonFactor,
  CarbonRecord,
  calculatePoints,
  calculateReduction,
  findFactor,
  formatKg
} from '../model/CarbonModel';
import { carbonPreferences } from '../entryability/EntryAbility';
import { loadBackendToken, loadChallengeJoined, loadDeviceId, loadRecords, saveBackendToken, saveChallengeJoined, saveDeviceId, saveRecords } from '../storage/CarbonStorage';
import { ApiRecord, CarbonApiClient } from '../network/ApiClient';

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
  private api: CarbonApiClient = new CarbonApiClient();

  private readonly ink: string = '#20332F';
  private readonly accent: string = '#2C6B5D';
  private readonly muted: string = '#71807B';
  private readonly line: string = '#DCE5E1';
  private readonly page: string = '#F7F8F5';

  aboutToAppear(): void {
    const savedRecords: CarbonRecord[] | null = loadRecords(carbonPreferences);
    if (savedRecords === null) {
      saveRecords(carbonPreferences, this.records);
    } else {
      this.records = savedRecords;
    }
    this.challengeJoined = loadChallengeJoined(carbonPreferences);
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
      for (const localRecord of this.records) {
        await this.api.createRecord(localRecord.id, localRecord.factorId, localRecord.amount, new Date().toISOString());
      }
      const remoteRecords: ApiRecord[] = await this.api.getRecords();
      if (remoteRecords.length > 0) {
        this.records = remoteRecords.map((record: ApiRecord): CarbonRecord => ({
          id: record.clientRecordId.length > 0 ? record.clientRecordId : record.id,
          factorId: record.factorId,
          amount: record.amount,
          reductionKg: record.reductionKg,
          points: record.points,
          createdAt: record.createdAt
        }));
        saveRecords(carbonPreferences, this.records);
      }
    } catch (error) {
      this.backendStatus = '离线可用';
      console.error(`CarbonLoop backend sync skipped: ${error}`);
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

  private calculateTotalPoints(): number {
    let total: number = 0;
    for (const item of this.records) {
      total += item.points;
    }
    return total;
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

  private getPreviewAmount(): number {
    const value: number = Number(this.amountText);
    return Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  private getPreviewReduction(): number {
    return calculateReduction(this.getSelectedFactor(), this.getPreviewAmount());
  }

  private getPreviewPoints(): number {
    return calculatePoints(this.getSelectedFactor(), this.getPreviewAmount());
  }

  private openRecord(factorId: string, amount: string): void {
    this.selectedFactorId = factorId;
    this.amountText = amount;
    this.currentTab = 1;
  }

  @Builder
  private pageHeader(section: string, title: string, subtitle: string) {
    Column({ space: 6 }) {
      Text(section)
        .fontSize(11)
        .fontColor(this.accent)
        .fontWeight(FontWeight.Bold)
        .letterSpacing(0.5);
      Text(title)
        .fontSize(29)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.ink);
      Text(subtitle)
        .fontSize(13)
        .fontColor(this.muted);
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 16, bottom: 14 });
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
    .padding({ right: 12 });
  }

  @Builder
  private homeView() {
    Scroll() {
      Column({ space: 22 }) {
        this.pageHeader('碳账本', '今天的低碳记录', '把每天的绿色选择，留下可查看的记录。');

        Row() {
          this.flatMetric('累计减排', formatKg(this.calculateTotalReduction()), 'kg', 'CO₂e 估算');
          Divider().vertical(true).height(58).color(this.line);
          this.flatMetric('碳积分', `${this.calculateTotalPoints()}`, '分', '持续积累');
        }
        .width('100%')
        .padding({ top: 8, bottom: 18 })
        .border({ width: { bottom: 1 }, color: this.line });

        Column({ space: 0 }) {
          this.sectionTitle('今日建议', '01');
          Row({ space: 14 }) {
            Text('01').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.accent).width(24);
            Column({ space: 5 }) {
              Text('少用一次性用品').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.ink);
              Text('带上水杯或餐具，完成一次可记录 0.06 kg 减排。').fontSize(12).fontColor(this.muted);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Button('记录')
              .fontSize(12)
              .fontColor(this.accent)
              .backgroundColor('#E7F0EC')
              .borderRadius(4)
              .onClick(() => this.openRecord('reusable', '1'));
          }
          .width('100%')
          .padding({ top: 12, bottom: 15 })
          .border({ width: { bottom: 1 }, color: this.line });
        }

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
              .backgroundColor('#E7F0EC')
              .borderRadius(4)
              .onClick(() => this.currentTab = 2);
          }
          .width('100%');
          Progress({ value: this.getChallengeProgress(), total: 15 })
            .color(this.accent)
            .backgroundColor('#DDE6E2')
            .margin({ top: 12, bottom: 5 });
        }
        .padding({ top: 2, bottom: 16 })
        .border({ width: { bottom: 1 }, color: this.line });

        Column({ space: 0 }) {
          this.sectionTitle('最近记录', `${this.records.length} 笔`);
          ForEach(this.records.slice(0, 3), (record: CarbonRecord, index: number) => {
            this.recordRow(record, index === 0);
          }, (record: CarbonRecord) => `home-${record.id}`);
          Button('查看全部记录')
            .fontSize(12)
            .fontColor(this.accent)
            .backgroundColor('#E7F0EC')
            .borderRadius(4)
            .margin({ top: 10 })
            .onClick(() => this.currentTab = 1);
        }
      }
      .padding({ left: 22, right: 22, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private challengeView() {
    Scroll() {
      Column({ space: 22 }) {
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
            .backgroundColor('#DDE6E2')
            .margin({ top: 4, bottom: 4 });
          Text(this.challengeJoined ? '挑战已加入，完成记录会自动计入进度。' : '加入后，步行与骑行记录会自动计入本周进度。')
            .fontSize(12)
            .fontColor(this.muted);
          Button(this.challengeJoined ? '去记录一笔' : '加入本周挑战')
            .width('100%')
            .fontSize(14)
            .fontColor('#FFFFFF')
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
        .padding({ bottom: 18 })
        .border({ width: { bottom: 1 }, color: this.line });

        Column({ space: 0 }) {
          this.sectionTitle('挑战规则', '3 条');
          this.ruleRow('01', '仅步行与骑行出行会计入本次里程。');
          this.ruleRow('02', '每次记录同时获得碳积分与减排量。');
          this.ruleRow('03', '完成 15 公里后，解锁“绿色出发”徽章。');
        }
        .padding({ bottom: 12 })
        .border({ width: { bottom: 1 }, color: this.line });

        Column({ space: 0 }) {
          this.sectionTitle('相关记录', `${this.records.filter((record: CarbonRecord) => record.factorId === 'walk').length} 笔`);
          ForEach(this.records, (record: CarbonRecord) => {
            if (record.factorId === 'walk') {
              this.recordRow(record, true);
            }
          }, (record: CarbonRecord) => `challenge-${record.id}`);
        }
      }
      .padding({ left: 22, right: 22, bottom: 24 });
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
      Column({ space: 22 }) {
        this.pageHeader('新增记录', '记录低碳行为', '选择一项行为，输入数量，账本会自动计算。');

        Column({ space: 0 }) {
          this.sectionTitle('选择行为', '5 项');
          ForEach(CARBON_FACTORS, (factor: CarbonFactor) => {
            this.factorChoice(factor);
          }, (factor: CarbonFactor) => factor.id);
        }
        .padding({ bottom: 8 })
        .border({ width: { bottom: 1 }, color: this.line });

        Column({ space: 10 }) {
          Text(`数量（${this.getSelectedFactor().unit}）`).fontSize(13).fontColor(this.muted);
          TextInput({ text: this.amountText, placeholder: '请输入数量' })
            .type(InputType.Number)
            .fontSize(20)
            .fontColor(this.ink)
            .onChange((value: string) => this.amountText = value)
            .backgroundColor('#FFFFFF')
            .border({ width: 1, color: this.line })
            .borderRadius(4)
            .padding({ left: 14, right: 14 });
          Row() {
            Column({ space: 3 }) {
              Text('预计减排').fontSize(12).fontColor(this.muted);
              Text(`${formatKg(this.getPreviewReduction())} kg CO₂e`).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.accent);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Column({ space: 3 }) {
              Text('获得积分').fontSize(12).fontColor(this.muted);
              Text(`+${this.getPreviewPoints()} 分`).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#9A6528');
            }.alignItems(HorizontalAlign.End);
          }
          .padding({ top: 8, bottom: 6 });
          Button('保存到碳账本')
            .width('100%')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(this.accent)
            .borderRadius(4)
            .onClick(() => this.saveRecord());
          if (this.notice.length > 0) {
            Text(this.notice).fontSize(12).fontColor(this.accent);
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 18 })
        .border({ width: { bottom: 1 }, color: this.line });

        Column({ space: 0 }) {
          this.sectionTitle('最近记录', `${this.records.length} 笔`);
          ForEach(this.records, (record: CarbonRecord, index: number) => {
            this.recordRow(record, index === 0);
          }, (record: CarbonRecord) => `record-${record.id}`);
        }
      }
      .padding({ left: 22, right: 22, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private factorChoice(factor: CarbonFactor) {
    Row({ space: 12 }) {
      Text(factor.icon)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(factor.id === this.selectedFactorId ? '#FFFFFF' : this.accent)
        .backgroundColor(factor.id === this.selectedFactorId ? this.accent : '#E7F0EC')
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .borderRadius(4);
      Column({ space: 3 }) {
        Text(factor.label).fontSize(14).fontColor(this.ink).fontWeight(factor.id === this.selectedFactorId ? FontWeight.Bold : FontWeight.Medium);
        Text(`每${factor.unit}减排 ${factor.reductionKgPerUnit.toFixed(2)} kg · ${factor.pointsPerUnit} 分`)
          .fontSize(11)
          .fontColor(this.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Text(factor.id === this.selectedFactorId ? '已选' : '选择')
        .fontSize(11)
        .fontColor(factor.id === this.selectedFactorId ? this.accent : this.muted);
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: this.line })
    .onClick(() => this.selectedFactorId = factor.id);
  }

  @Builder
  private recordRow(record: CarbonRecord, first: boolean) {
    Row({ space: 12 }) {
      Text(findFactor(record.factorId).icon)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accent)
        .backgroundColor('#E7F0EC')
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .borderRadius(4);
      Column({ space: 3 }) {
        Text(findFactor(record.factorId).label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.ink);
        Text(`${record.amount} ${findFactor(record.factorId).unit} · ${record.createdAt}`).fontSize(11).fontColor(this.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Column({ space: 3 }) {
        Text(`-${formatKg(record.reductionKg)} kg`).fontSize(13).fontColor(this.accent);
        Text(`+${record.points} 分`).fontSize(11).fontColor('#9A6528');
      }.alignItems(HorizontalAlign.End);
    }
    .width('100%')
    .padding({ top: 11, bottom: 11 })
    .border({ width: { bottom: 1 }, color: this.line });
  }

  @Builder
  private profileView() {
    Scroll() {
      Column({ space: 22 }) {
        this.pageHeader('我的', '我的碳账本', '所有数据都来自你记录的低碳行为。');

        Row() {
          this.flatMetric('累计减排', formatKg(this.calculateTotalReduction()), 'kg', 'CO₂e 估算');
          Divider().vertical(true).height(58).color(this.line);
          this.flatMetric('碳积分', `${this.calculateTotalPoints()}`, '分', '可持续累积');
        }
        .width('100%')
        .padding({ top: 8, bottom: 18 })
        .border({ width: { bottom: 1 }, color: this.line });

        Column({ space: 0 }) {
          this.sectionTitle('记录概览', '当前状态');
          this.summaryRow('数据连接', this.backendStatus);
          this.summaryRow('行为记录', `${this.records.length} 笔`);
          this.summaryRow('挑战状态', this.challengeJoined ? '已加入本周挑战' : '尚未加入挑战');
          this.summaryRow('步行与骑行', `${this.getChallengeProgress()} / 15 km`);
        }
        .padding({ bottom: 10 })
        .border({ width: { bottom: 1 }, color: this.line });

        Column({ space: 0 }) {
          this.sectionTitle('低碳徽章', '记录进度');
          this.badgeRow('01', '绿色起点', '完成第一笔低碳行为', this.records.length >= 1);
          this.badgeRow('02', '减排新星', '累计减排达到 1 kg CO₂e', this.calculateTotalReduction() >= 1);
          this.badgeRow('03', '校园挑战者', '加入一次校园低碳挑战', this.challengeJoined);
          this.badgeRow('04', '持续行动', '累计完成 5 次记录', this.records.length >= 5);
        }
        .padding({ bottom: 10 })
        .border({ width: { bottom: 1 }, color: this.line });

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
      }
      .padding({ left: 22, right: 22, bottom: 24 });
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

  private saveRecord(): void {
    if (this.getPreviewAmount() <= 0) {
      this.notice = '请输入大于 0 的数量';
      return;
    }
    const factor: CarbonFactor = this.getSelectedFactor();
    const record: CarbonRecord = {
      id: `${Date.now()}`,
      factorId: factor.id,
      amount: this.getPreviewAmount(),
      reductionKg: this.getPreviewReduction(),
      points: this.getPreviewPoints(),
      createdAt: '刚刚'
    };
    this.records = [record, ...this.records];
    saveRecords(carbonPreferences, this.records);
    this.notice = `已记录 ${factor.label}，正在同步云端…`;
    this.syncRecord(record);
  }

  private async syncRecord(record: CarbonRecord): Promise<void> {
    try {
      const remote: ApiRecord = await this.api.createRecord(record.id, record.factorId, record.amount, new Date().toISOString());
      this.backendStatus = '云端已连接';
      this.notice = `已同步 ${findFactor(record.factorId).label}，获得 ${remote.points} 个积分`;
    } catch (error) {
      this.backendStatus = '离线可用';
      this.notice = `已保存在本机，联网后会自动同步`;
      console.error(`CarbonLoop record sync skipped: ${error}`);
    }
  }

  build() {
    Column() {
      if (this.currentTab === 0) {
        this.homeView();
      } else if (this.currentTab === 1) {
        this.recordView();
      } else if (this.currentTab === 2) {
        this.challengeView();
      } else {
        this.profileView();
      }
      Row() {
        this.tabButton('首页', 0);
        this.tabButton('记录', 1);
        this.tabButton('挑战', 2);
        this.tabButton('我的', 3);
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 12 })
      .border({ width: { top: 1 }, color: this.line })
      .backgroundColor('#FCFCFA');
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
      .backgroundColor(this.currentTab === tab ? '#E7F0EC' : '#FCFCFA')
      .borderRadius(4)
      .onClick(() => this.currentTab = tab);
  }
}
