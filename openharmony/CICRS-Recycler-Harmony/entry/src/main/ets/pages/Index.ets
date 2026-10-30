import { scanBarcode } from '@kit.ScanKit';
import {
  CicrsItem,
  CicrsStation,
  CicrsStatusEvent,
  CICRS_STATIONS,
  formatCicrsNumber,
  statusInfo,
  transferMethodLabel
} from '../model/CicrsModel';
import { cicrsRepository } from '../service/CicrsRepository';

@Entry
@Component
struct Index {
  @State loggedIn: boolean = false;
  @State tab: number = 0;
  @State page: string = '';
  @State items: CicrsItem[] = [];
  @State notice: string = '';
  @State codeInput: string = '';
  @State actualWeightText: string = '1';
  @State conditionLevel: number = 3;
  @State rejectReason: string = '';
  @State shelfText: string = 'A-04';
  @State scrapReason: string = '现场复核不满足再利用条件';
  @State selectedItemId: string = '';
  @State activeStationId: string = 'station-east';
  private readonly ink: string = '#20332F';
  private readonly accent: string = '#2C6B5D';
  private readonly muted: string = '#71807B';
  private readonly line: string = '#DCE5E1';
  private readonly pageColor: string = '#F7F8F5';

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    cicrsRepository.refreshExpirations();
    this.items = cicrsRepository.getItems();
  }

  private station(): CicrsStation {
    return cicrsRepository.getStation(this.activeStationId);
  }

  private loginAtStation(stationId: string): void {
    this.activeStationId = stationId;
    this.loggedIn = true;
    this.refresh();
  }

  private stationItems(): CicrsItem[] {
    return this.items.filter((item: CicrsItem) => item.stationId === this.activeStationId);
  }

  private receivedCount(): number {
    return this.stationItems().filter((item: CicrsItem) => item.status === 'RECEIVED').length;
  }

  private stockCount(): number {
    return this.stationItems().filter((item: CicrsItem) => item.status === 'IN_STOCK').length;
  }

  private bookedCount(): number {
    return this.stationItems().filter((item: CicrsItem) => item.status === 'BOOKED' || item.status === 'RESERVED').length;
  }

  private show(message: string): void {
    this.notice = message;
    setTimeout(() => { this.notice = ''; }, 4000);
  }

  private openPage(pageName: string): void {
    this.page = pageName;
    this.refresh();
  }

  private goBack(): void {
    this.page = '';
    this.selectedItemId = '';
    this.refresh();
  }

  private verify(type: string): void {
    const target = cicrsRepository.getItemByCode(this.codeInput);
    const expectedType: string = type === 'receive' ? 'delivery' : 'pickup';
    if (target === null || target.appointment === null || target.appointment.type !== expectedType) {
      this.show(type === 'receive' ? '请使用投递预约码进行收货核销。' : '请使用领取预约码进行取件核销。');
      return;
    }
    const result = cicrsRepository.verifyCode(this.codeInput, this.activeStationId, Number(this.actualWeightText), this.conditionLevel);
    this.show(result.message);
    if (result.ok) this.codeInput = '';
    this.refresh();
  }

  private refuse(): void {
    const result = cicrsRepository.refuseDelivery(this.codeInput, this.activeStationId, this.rejectReason);
    this.show(result.message);
    if (result.ok) {
      this.codeInput = '';
      this.rejectReason = '';
    }
    this.refresh();
  }

  private async scan(type: string): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        this.show('无法获取扫码页面上下文，请手动输入核销码。');
        return;
      }
      const result = await scanBarcode.startScanForResult(context);
      this.codeInput = result.originalValue.trim();
      this.verify(type);
    } catch (error) {
      this.show('扫码已取消或暂不可用，可手动输入 8 位核销码。');
      console.error(`CICRS recycler ScanKit: ${error}`);
    }
  }

  private shelve(item: CicrsItem): void {
    const result = cicrsRepository.shelveItem(item.id, this.shelfText, this.activeStationId);
    this.show(result.message);
    this.refresh();
    if (result.ok) this.goBack();
  }

  private scrap(item: CicrsItem): void {
    const result = cicrsRepository.scrapItem(item.id, this.scrapReason, this.activeStationId);
    this.show(result.message);
    this.refresh();
    if (result.ok) this.goBack();
  }

  @Builder
  private header(kicker: string, title: string, subtitle: string) {
    Column({ space: 5 }) {
      Text(kicker).fontSize(11).fontColor(this.accent).fontWeight(FontWeight.Bold).letterSpacing(1);
      Text(title).fontSize(27).fontColor(this.ink).fontWeight(FontWeight.Bold);
      Text(subtitle).fontSize(13).fontColor(this.muted);
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 18, bottom: 14 });
  }

  @Builder
  private subHeader(title: string, subtitle: string) {
    Row({ space: 10 }) {
      Button('‹').width(38).height(38).fontSize(22).backgroundColor('#E7F0EC').fontColor(this.accent).onClick(() => this.goBack());
      Column({ space: 3 }) {
        Text(title).fontSize(21).fontColor(this.ink).fontWeight(FontWeight.Bold);
        Text(subtitle).fontSize(11).fontColor(this.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
    }.width('100%').padding({ left: 18, right: 18, top: 12, bottom: 8 });
  }

  @Builder
  private statusPill(item: CicrsItem) {
    Text(statusInfo(item.status).label).fontSize(11).fontColor(statusInfo(item.status).color).backgroundColor('#E7F0EC').borderRadius(12).padding({ left: 9, right: 9, top: 5, bottom: 5 });
  }

  @Builder
  private itemCard(item: CicrsItem, mode: string) {
    Column({ space: 9 }) {
      Row() {
        Column({ space: 4 }) {
          Text(item.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.ink);
          Text(`${item.category} · ${item.quantity}${item.factorUnit === 'kg' ? ' kg' : ' 件'} · ${transferMethodLabel(item.transferMethod)}`).fontSize(12).fontColor(this.muted);
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        this.statusPill(item);
      }.width('100%');
      Text(`归属驿站：${item.stationId === this.activeStationId ? this.station().name : '其他驿站'}`).fontSize(11).fontColor(this.muted).width('100%');
      if (item.actualWeightKg > 0) Text(`复核重量 ${item.actualWeightKg} kg · 复核成色 ${item.verifiedConditionLevel} 档`).fontSize(11).fontColor(this.muted).width('100%');
      if (item.scoreAwarded) Text(`已结算 ${item.score} 分 · ${formatCicrsNumber(item.carbonSavedKg)} kg CO₂e`).fontSize(12).fontColor(this.accent).width('100%');
      Row({ space: 7 }) {
        Button('查看详情').fontSize(11).backgroundColor('#E7F0EC').fontColor(this.accent).onClick(() => { this.selectedItemId = item.id; this.openPage('detail'); });
        if (mode === 'received' && item.status === 'RECEIVED') {
          Button('上架').fontSize(11).onClick(() => { this.selectedItemId = item.id; this.openPage('shelve'); });
          Button('报废').fontSize(11).backgroundColor('#F4E9E5').fontColor('#A04D39').onClick(() => { this.selectedItemId = item.id; this.openPage('scrap'); });
        }
      }.width('100%');
    }.alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor('#FFFFFF').borderRadius(12).border({ width: 1, color: this.line });
  }

  @Builder
  private workbenchView() {
    Scroll() {
      Column({ space: 14 }) {
        this.header('CICRS · 回收员端', '驿站工作台', `${this.station().name} · ${this.station().openHours}`);
        Row({ space: 8 }) {
          Button('扫码收货').layoutWeight(1).height(48).onClick(() => this.openPage('scan-receive'));
          Button('扫码领取').layoutWeight(1).height(48).backgroundColor('#FFFFFF').fontColor(this.accent).onClick(() => this.openPage('scan-pickup'));
        }.width('100%');
        Row({ space: 8 }) {
          this.metric(`${this.receivedCount()}`, '待处置');
          this.metric(`${this.stockCount()}`, '在库');
          this.metric(`${this.bookedCount()}`, '预约中');
        }.width('100%');
        Text('工作入口').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
        this.workEntry('待处置物品', '上架或报废，货位与原因均需留痕', 'todo');
        this.workEntry('本驿站台账', '收货、库存、流转状态和操作记录', 'ledger');
        this.workEntry('我的回收员资料', '当前驿站和权限状态', 'mine');
        Text('回收员账号必须绑定驿站；数据隔离由服务端最终强制执行。').fontSize(11).fontColor(this.muted).width('100%');
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private loginView() {
    Column({ space: 14 }) {
      Blank();
      Text('CICRS · 青碳汇').fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.accent).letterSpacing(1);
      Text('回收员工作台').fontSize(29).fontWeight(FontWeight.Bold).fontColor(this.ink);
      Text('请使用回收员账号登录，业务数据按驿站隔离。').fontSize(13).fontColor(this.muted);
      Text('当前没有云端登录配置，以下仅进入本机体验账号：').fontSize(11).fontColor('#A04D39').width('100%').padding({ top: 15 });
      ForEach(CICRS_STATIONS, (station: CicrsStation) => {
        Column({ space: 6 }) {
          Text(`体验 ${station.name}`).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.ink).width('100%');
          Text(`${station.address} · ${station.openHours}`).fontSize(11).fontColor(this.muted).width('100%');
          Button('进入本机体验').width('100%').onClick(() => this.loginAtStation(station.id));
        }.width('100%').padding(14).backgroundColor('#FFFFFF').borderRadius(12);
      }, (station: CicrsStation) => station.id);
      Text('体验账号不是身份认证；生产环境需对接原 CICRS 鉴权，并由服务端绑定 station_id。').fontSize(10).fontColor(this.muted).width('100%');
      Blank();
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start).padding({ left: 24, right: 24 }).backgroundColor(this.pageColor);
  }

  @Builder
  private metric(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value).fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.ink);
      Text(label).fontSize(11).fontColor(this.muted);
    }.layoutWeight(1).padding(12).backgroundColor('#E7F0EC').borderRadius(10);
  }

  @Builder
  private workEntry(title: string, detail: string, pageName: string) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.ink);
        Text(detail).fontSize(10).fontColor(this.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Text('›').fontSize(22).fontColor(this.muted);
    }.width('100%').padding(13).backgroundColor('#FFFFFF').borderRadius(10).onClick(() => this.openPage(pageName));
  }

  @Builder
  private scanPage(type: string) {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader(type === 'receive' ? '扫码收货' : '扫码领取', type === 'receive' ? '扫描投递预约码并现场复核' : '扫描领取预约码完成流转');
        Row({ space: 8 }) {
          TextInput({ text: this.codeInput, placeholder: '输入 8 位核销码' }).layoutWeight(1).type(InputType.Number).onChange((value: string) => this.codeInput = value);
          Button('扫码').onClick(() => this.scan(type));
        }.width('100%');
        if (type === 'receive') {
          Text('现场复核重量').fontSize(13).fontColor(this.muted).width('100%');
          TextInput({ text: this.actualWeightText, placeholder: '实际重量 kg' }).type(InputType.Number).onChange((value: string) => this.actualWeightText = value);
          Row({ space: 7 }) {
            Button('成色 −').fontSize(11).onClick(() => this.conditionLevel = Math.max(1, this.conditionLevel - 1));
            Text(`${this.conditionLevel} 档`).fontSize(13).fontColor(this.ink);
            Button('成色 +').fontSize(11).onClick(() => this.conditionLevel = Math.min(5, this.conditionLevel + 1));
          }.width('100%');
          TextInput({ text: this.rejectReason, placeholder: '拒收原因（仅严重不符时填写）' }).onChange((value: string) => this.rejectReason = value);
        }
        Button(type === 'receive' ? '确认收货' : '确认领取核销').width('100%').height(46).onClick(() => this.verify(type));
        if (type === 'receive') Button('拒收并记录原因').width('100%').backgroundColor('#F4E9E5').fontColor('#A04D39').onClick(() => this.refuse());
        Text('校验项：存在、未核销、未过期、驿站一致；重复核销不会再次处理。').fontSize(11).fontColor(this.muted).width('100%');
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private todoView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('待处置', '已收货物品的上架与报废操作');
        ForEach(this.stationItems().filter((item: CicrsItem) => item.status === 'RECEIVED'), (item: CicrsItem) => this.itemCard(item, 'received'), (item: CicrsItem) => `todo-${item.id}`);
        if (this.stationItems().filter((item: CicrsItem) => item.status === 'RECEIVED').length === 0) Text('暂无待处置物品。').fontSize(13).fontColor(this.muted).width('100%').padding(18);
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private shelveView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('上架入库', '请登记唯一货位，保存操作人和时间');
        ForEach(this.items.filter((item: CicrsItem) => item.id === this.selectedItemId && item.status === 'RECEIVED'), (item: CicrsItem) => {
          Column({ space: 5 }) {
            Text(item.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
            Text(`收货复核 ${item.actualWeightKg} kg · 成色 ${item.verifiedConditionLevel} 档`).fontSize(11).fontColor(this.muted).width('100%');
          }.width('100%').padding(13).backgroundColor('#FFFFFF').borderRadius(10);
        }, (item: CicrsItem) => `shelve-${item.id}`);
        Text('货位号').fontSize(12).fontColor(this.muted).width('100%');
        TextInput({ text: this.shelfText, placeholder: '例如 A-04' }).onChange((value: string) => this.shelfText = value);
        Button('确认上架').width('100%').height(46).onClick(() => {
          const item = cicrsRepository.getItem(this.selectedItemId);
          if (item !== null) this.shelve(item);
        });
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private scrapView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('报废登记', '报废会立即终结该物品并进行一次性积分结算');
        ForEach(this.items.filter((item: CicrsItem) => item.id === this.selectedItemId && item.status === 'RECEIVED'), (item: CicrsItem) => {
          Column({ space: 5 }) {
            Text(item.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
            Text(`收货复核 ${item.actualWeightKg} kg · 成色 ${item.verifiedConditionLevel} 档`).fontSize(11).fontColor(this.muted).width('100%');
          }.width('100%').padding(13).backgroundColor('#FFFFFF').borderRadius(10);
        }, (item: CicrsItem) => `scrap-${item.id}`);
        Text('报废原因（必填）').fontSize(12).fontColor(this.muted).width('100%');
        TextInput({ text: this.scrapReason, placeholder: '描述无法再利用的原因' }).onChange((value: string) => this.scrapReason = value).height(90);
        Button('确认报废并结算').width('100%').height(46).backgroundColor('#A04D39').onClick(() => {
          const item = cicrsRepository.getItem(this.selectedItemId);
          if (item !== null) this.scrap(item);
        });
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private ledgerView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('驿站台账', `${this.station().name} · 行级隔离演示`);
        Text('库存').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
        ForEach(this.stationItems().filter((item: CicrsItem) => item.status === 'IN_STOCK'), (item: CicrsItem) => this.itemCard(item, 'ledger'), (item: CicrsItem) => `stock-${item.id}`);
        Text('近期收货 / 流转').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
        ForEach(this.stationItems().filter((item: CicrsItem) => item.status !== 'IN_STOCK'), (item: CicrsItem) => this.itemCard(item, 'ledger'), (item: CicrsItem) => `ledger-${item.id}`);
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private mineView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('我的', '回收员账号与驿站权限');
        Column({ space: 6 }) {
          Text('回收员体验账号').fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.ink);
          Text(`当前绑定：${this.station().name}`).fontSize(13).fontColor(this.muted);
          Text('生产环境需通过独立回收员登录和服务端 RBAC 绑定驿站。').fontSize(11).fontColor(this.muted);
        }.alignItems(HorizontalAlign.Start).width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(12);
        Button('退出体验账号').width('100%').backgroundColor('#FFFFFF').fontColor(this.accent).onClick(() => { this.loggedIn = false; this.page = ''; this.tab = 0; });
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private detailView(item: CicrsItem) {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('物品详情', '收货、处置和积分追溯');
        Column({ space: 6 }) {
          Text(item.title).fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
          Text(`${item.category} · ${statusInfo(item.status).label}`).fontSize(12).fontColor(this.muted).width('100%');
          Text(`发布者：${item.ownerName} · ${transferMethodLabel(item.transferMethod)}`).fontSize(12).fontColor(this.muted).width('100%');
          Text(`申报数量 ${item.quantity} · 估计重量 ${item.estimatedWeightKg > 0 ? `${item.estimatedWeightKg} kg` : '待称重'}`).fontSize(12).fontColor(this.muted).width('100%');
          Text(`当前驿站：${item.stationId === this.activeStationId ? this.station().name : '其他驿站'}`).fontSize(12).fontColor(this.muted).width('100%');
        }.alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor('#FFFFFF').borderRadius(12);
        Text('状态轨迹').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
        ForEach(item.statusEvents.slice().reverse(), (event: CicrsStatusEvent) => {
          Row({ space: 8 }) {
            Text('●').fontColor(statusInfo(event.status).color);
            Column({ space: 3 }) {
              Text(statusInfo(event.status).label).fontSize(13).fontColor(this.ink);
              Text(`${event.note} · ${event.actor}`).fontSize(11).fontColor(this.muted);
              Text(event.createdAt).fontSize(9).fontColor(this.muted);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          }.width('100%').padding(10).backgroundColor('#FFFFFF').borderRadius(9);
        }, (event: CicrsStatusEvent) => `${event.status}-${event.createdAt}`);
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  build() {
    Column() {
      if (!this.loggedIn) {
        this.loginView();
      } else {
        if (this.page.length === 0) {
          if (this.tab === 0) this.workbenchView();
          if (this.tab === 1) this.ledgerView();
          if (this.tab === 2) this.todoView();
          if (this.tab === 3) this.mineView();
          Row() {
            this.navItem('工作台', 0);
            this.navItem('台账', 1);
            this.navItem('待处理', 2);
            this.navItem('我的', 3);
          }.height(54).width('100%').backgroundColor('#FFFFFF').border({ width: { top: 1 }, color: this.line });
        } else {
          if (this.page === 'scan-receive') this.scanPage('receive');
          if (this.page === 'scan-pickup') this.scanPage('pickup');
          if (this.page === 'todo') this.todoView();
          if (this.page === 'ledger') this.ledgerView();
          if (this.page === 'mine') this.mineView();
          if (this.page === 'shelve') this.shelveView();
          if (this.page === 'scrap') this.scrapView();
          if (this.page === 'detail' && cicrsRepository.getItem(this.selectedItemId) === null) {
            Text('未找到物品。').fontSize(13).fontColor(this.muted).padding(20);
          }
          if (this.page === 'detail' && cicrsRepository.getItem(this.selectedItemId) !== null) {
            ForEach(this.items.filter((item: CicrsItem) => item.id === this.selectedItemId), (item: CicrsItem) => this.detailView(item), (item: CicrsItem) => `detail-${item.id}`);
          }
        }
      }
      if (this.notice.length > 0) Text(this.notice).fontSize(12).fontColor('#FFFFFF').backgroundColor(this.ink).borderRadius(8).padding(12).margin({ left: 18, right: 18, bottom: 7 }).width('calc(100% - 36vp)');
    }.backgroundColor(this.pageColor).width('100%').height('100%');
  }

  @Builder
  private navItem(label: string, index: number) {
    Text(label).fontSize(11).fontColor(this.tab === index ? this.accent : this.muted).layoutWeight(1).textAlign(TextAlign.Center).onClick(() => this.tab = index);
  }
}
