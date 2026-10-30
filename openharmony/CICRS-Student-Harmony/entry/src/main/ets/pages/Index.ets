import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { cicrsFactorCatalog } from '../entryability/EntryAbility';
import {
  AppointmentType,
  CicrsAccountSummary,
  CicrsFactor,
  CicrsItem,
  CicrsScoreRecord,
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
  @State enteredDemo: boolean = false;
  @State tab: number = 0;
  @State page: string = '';
  @State items: CicrsItem[] = [];
  @State notice: string = '';
  @State selectedItemId: string = '';
  @State titleText: string = '';
  @State descriptionText: string = '';
  @State weightText: string = '';
  @State quantityText: string = '1';
  @State selectedFactorId: string = 'book';
  @State selectedCondition: number = 2;
  @State selectedMethod: string = 'donate';
  @State imageUris: string[] = [];
  @State searchText: string = '';
  @State selectedCategory: string = '全部';
  @State selectedStationId: string = 'station-east';
  @State selectedSlotStart: string = '';
  @State bookingSlots: string[] = [];
  @State bookingType: AppointmentType = 'delivery';
  @State account: CicrsAccountSummary = { points: 0, carbonSavedKg: 0, completedCount: 0, treeEquivalent: 0 };
  @State nickname: string = '林同学';
  @State questionText: string = '';
  @State answerText: string = '';

  private readonly ink: string = '#20332F';
  private readonly accent: string = '#2C6B5D';
  private readonly muted: string = '#71807B';
  private readonly line: string = '#DCE5E1';
  private readonly pageColor: string = '#F7F8F5';
  private readonly ownerId: string = 'student-demo';

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    cicrsRepository.refreshExpirations();
    this.items = cicrsRepository.getItems();
    this.account = cicrsRepository.getAccount(this.ownerId);
  }

  private factors(): CicrsFactor[] {
    if (cicrsFactorCatalog === null) return [];
    return cicrsFactorCatalog.factors;
  }

  private categories(): string[] {
    const result: string[] = ['全部'];
    for (const factor of this.factors()) {
      if (!result.includes(factor.category)) result.push(factor.category);
    }
    return result;
  }

  private factor(): CicrsFactor {
    for (const factor of this.factors()) {
      if (factor.id === this.selectedFactorId) return factor;
    }
    if (this.factors().length > 0) return this.factors()[0];
    return { id: 'book', category: '图书文娱', name: '教材 / 图书', unit: 'kg', value: 1.1, source: '演示配置' };
  }

  private filteredItems(): CicrsItem[] {
    const result: CicrsItem[] = [];
    for (const item of this.items) {
      if (item.status !== 'IN_STOCK') continue;
      if (this.selectedCategory !== '全部' && item.category !== this.selectedCategory) continue;
      if (this.searchText.trim().length > 0 && item.title.indexOf(this.searchText.trim()) < 0) continue;
      result.push(item);
    }
    return result;
  }

  private myItems(): CicrsItem[] {
    return this.items.filter((item: CicrsItem) => item.ownerId === this.ownerId);
  }

  private activeAppointments(): CicrsItem[] {
    return this.myItems().filter((item: CicrsItem) => item.appointment !== null && item.appointment.state === 'active');
  }

  private selectedItem(): CicrsItem | null {
    return cicrsRepository.getItem(this.selectedItemId);
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

  private openDetail(item: CicrsItem): void {
    this.selectedItemId = item.id;
    this.openPage('detail');
  }

  private generateSlots(): void {
    const first = new Date();
    first.setSeconds(0, 0);
    if (first.getMinutes() < 30) first.setMinutes(30);
    else {
      first.setHours(first.getHours() + 1);
      first.setMinutes(0);
    }
    const values: string[] = [];
    for (let index = 0; index < 6; index += 1) {
      const slot = new Date(first.getTime() + index * 30 * 60 * 1000);
      values.push(slot.toISOString());
    }
    this.bookingSlots = values;
    this.selectedSlotStart = values[0];
  }

  private openBooking(item: CicrsItem, type: AppointmentType): void {
    this.selectedItemId = item.id;
    this.bookingType = type;
    this.selectedStationId = CICRS_STATIONS[0].id;
    this.generateSlots();
    this.openPage('booking');
  }

  private slotLabel(iso: string): string {
    if (iso.length === 0) return '选择时段';
    const date = new Date(iso);
    const end = new Date(date.getTime() + 30 * 60 * 1000);
    return `${date.getMonth() + 1}月${date.getDate()}日 ${this.twoDigits(date.getHours())}:${this.twoDigits(date.getMinutes())}–${this.twoDigits(end.getHours())}:${this.twoDigits(end.getMinutes())}`;
  }

  private twoDigits(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private confirmBooking(): void {
    const item = this.selectedItem();
    if (item === null) {
      this.show('预约物品不存在，请返回列表刷新。');
      return;
    }
    const station = cicrsRepository.getStation(this.selectedStationId);
    const result = cicrsRepository.book(item.id, this.bookingType, station.id, this.slotLabel(this.selectedSlotStart), this.selectedSlotStart);
    this.show(result.message);
    if (result.ok) {
      this.selectedItemId = result.itemId;
      this.page = 'appointment-detail';
    }
    this.refresh();
  }

  private cancelItem(item: CicrsItem): void {
    this.show(cicrsRepository.cancelItem(item.id, this.nickname).message);
    this.refresh();
  }

  private async pickPhotos(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = {
        maxSelectNumber: 6,
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      };
      const result = await picker.select(options);
      this.imageUris = result.photoUris;
      this.show(`已选择 ${this.imageUris.length} 张照片`);
    } catch (error) {
      this.show('未选择照片，可稍后重试。');
      console.error(`CICRS student photo picker: ${error}`);
    }
  }

  private submitItem(): void {
    const weight: number = this.weightText.trim().length > 0 ? Number(this.weightText) : 0;
    const result = cicrsRepository.createItem({
      ownerId: this.ownerId,
      ownerName: this.nickname,
      title: this.titleText,
      factorId: this.selectedFactorId,
      conditionLevel: this.selectedCondition,
      transferMethod: this.selectedMethod as 'donate' | 'transfer' | 'recycle',
      quantity: Number(this.quantityText),
      estimatedWeightKg: weight,
      description: this.descriptionText,
      imageUris: this.imageUris
    });
    this.show(result.message);
    if (result.ok) {
      this.titleText = '';
      this.descriptionText = '';
      this.weightText = '';
      this.imageUris = [];
      this.page = '';
      this.tab = 0;
      this.refresh();
    }
  }

  private runLocalQuery(): void {
    const query: string = this.questionText.trim();
    if (query.length === 0) {
      this.answerText = '请先输入一个问题。';
      return;
    }
    if (query.indexOf('积分') >= 0 || query.indexOf('碳账户') >= 0) {
      this.answerText = `本机演示账户当前有 ${this.account.points} 分，累计减排 ${formatCicrsNumber(this.account.carbonSavedKg)} kg CO₂e。`;
    } else if (query.indexOf('物品') >= 0 || query.indexOf('发布') >= 0) {
      this.answerText = `你的发布记录共 ${this.myItems().length} 件，其中待核验 ${this.myItems().filter((item: CicrsItem) => item.status === 'PENDING').length} 件、已完成 ${this.myItems().filter((item: CicrsItem) => item.status === 'COMPLETED').length} 件。`;
    } else {
      this.answerText = '本机模式只支持查询个人碳账户和发布数量；AI 云端自然语言查询尚未接入。';
    }
  }

  private enterDemo(): void {
    this.enteredDemo = true;
    this.refresh();
  }

  @Builder
  private sectionHeader(kicker: string, title: string, subtitle: string) {
    Column({ space: 5 }) {
      Text(kicker).fontSize(11).fontColor(this.accent).fontWeight(FontWeight.Bold).letterSpacing(1);
      Text(title).fontSize(27).fontColor(this.ink).fontWeight(FontWeight.Bold);
      Text(subtitle).fontSize(13).fontColor(this.muted);
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 18, bottom: 14 });
  }

  @Builder
  private subHeader(title: string, subtitle: string) {
    Row({ space: 10 }) {
      Button('‹').width(38).height(38).fontSize(22).backgroundColor('#E7F0EC').fontColor(this.accent).onClick(() => this.goBack());
      Column({ space: 3 }) {
        Text(title).fontSize(21).fontColor(this.ink).fontWeight(FontWeight.Bold);
        Text(subtitle).fontSize(11).fontColor(this.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 8 });
  }

  @Builder
  private labelPill(label: string, color: string) {
    Text(label).fontSize(11).fontColor(color).backgroundColor('#E7F0EC').borderRadius(12).padding({ left: 9, right: 9, top: 5, bottom: 5 });
  }

  @Builder
  private itemCard(item: CicrsItem, mode: string) {
    Column({ space: 9 }) {
      Row() {
        Column({ space: 4 }) {
          Text(item.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.ink);
          Text(`${item.category} · ${item.quantity}${item.factorUnit === 'kg' ? ' kg' : ' 件'} · ${transferMethodLabel(item.transferMethod)}`).fontSize(12).fontColor(this.muted);
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        this.labelPill(statusInfo(item.status).label, statusInfo(item.status).color);
      }
      if (item.appointment !== null && item.appointment.state === 'active') {
        Row() {
          Column({ space: 4 }) {
            Text(item.appointment.type === 'delivery' ? '预约投递码' : '预约领取码').fontSize(11).fontColor(this.muted);
            Text(item.appointment.code).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.accent).letterSpacing(2);
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          QRCode(item.appointment.code).width(64).height(64);
        }.width('100%');
        Text(`${item.appointment.stationName} · ${item.appointment.slot}`).fontSize(11).fontColor(this.muted);
      }
      if (item.scoreAwarded) {
        Text(`+${item.score} 分 · 减排 ${formatCicrsNumber(item.carbonSavedKg)} kg CO₂e`).fontSize(12).fontColor(this.accent);
      }
      Row({ space: 7 }) {
        Button('查看详情').fontSize(11).backgroundColor('#E7F0EC').fontColor(this.accent).onClick(() => this.openDetail(item));
        if (mode === 'discover' && item.status === 'IN_STOCK') {
          Button('预约领取').fontSize(11).onClick(() => this.openBooking(item, 'pickup'));
        }
        if (mode === 'mine' && item.status === 'APPROVED') {
          Button('预约投递').fontSize(11).onClick(() => this.openBooking(item, 'delivery'));
        }
        if (mode === 'mine' && (item.status === 'PENDING' || item.status === 'APPROVED' || item.status === 'BOOKED')) {
          Button('撤回').fontSize(11).backgroundColor('#F4E9E5').fontColor('#A04D39').onClick(() => this.cancelItem(item));
        }
        if (mode === 'appointment' && item.appointment !== null && item.appointment.state === 'active') {
          Button('预约详情').fontSize(11).onClick(() => { this.selectedItemId = item.id; this.openPage('appointment-detail'); });
          Button('取消预约').fontSize(11).backgroundColor('#F4E9E5').fontColor('#A04D39').onClick(() => this.cancelItem(item));
        }
      }.width('100%');
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .border({ width: 1, color: this.line });
  }

  @Builder
  private homeView() {
    Scroll() {
      Column({ space: 15 }) {
        this.sectionHeader('CICRS · 青碳汇', '让旧物再走一程', '校园闲置共享，每一次循环都留下碳足迹。');
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text(`${this.account.points}`).fontSize(25).fontWeight(FontWeight.Bold).fontColor(this.ink);
            Text('碳积分').fontSize(11).fontColor(this.muted);
          }.layoutWeight(1);
          Column({ space: 3 }) {
            Text(formatCicrsNumber(this.account.carbonSavedKg)).fontSize(25).fontWeight(FontWeight.Bold).fontColor(this.ink);
            Text('kg CO₂e').fontSize(11).fontColor(this.muted);
          }.layoutWeight(1);
          Column({ space: 3 }) {
            Text(`${this.account.completedCount}`).fontSize(25).fontWeight(FontWeight.Bold).fontColor(this.ink);
            Text('已完成循环').fontSize(11).fontColor(this.muted);
          }.layoutWeight(1);
        }.width('100%').padding(16).backgroundColor('#E7F0EC').borderRadius(14);
        Row({ space: 8 }) {
          Button('发布闲置').layoutWeight(1).height(44).onClick(() => this.tab = 2);
          Button('找旧物').layoutWeight(1).height(44).backgroundColor('#FFFFFF').fontColor(this.accent).onClick(() => this.tab = 1);
          Button('我的发布').layoutWeight(1).height(44).backgroundColor('#FFFFFF').fontColor(this.accent).onClick(() => this.openPage('my-items'));
        }.width('100%');
        Row() {
          Text('共享货架').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink);
          Blank();
          Text('查看全部 ›').fontSize(12).fontColor(this.accent).onClick(() => this.tab = 1);
        }.width('100%');
        ForEach(this.items.filter((item: CicrsItem) => item.status === 'IN_STOCK').slice(0, 3), (item: CicrsItem) => {
          this.itemCard(item, 'discover');
        }, (item: CicrsItem) => `home-${item.id}`);
        if (this.items.filter((item: CicrsItem) => item.status === 'IN_STOCK').length === 0) {
          Text('货架正在等候下一件旧物。').fontSize(13).fontColor(this.muted).width('100%');
        }
        Row({ space: 8 }) {
          Button('我的预约').layoutWeight(1).backgroundColor('#FFFFFF').fontColor(this.accent).onClick(() => this.openPage('appointments'));
          Button('消息与动态').layoutWeight(1).backgroundColor('#FFFFFF').fontColor(this.accent).onClick(() => this.openPage('messages'));
        }.width('100%');
        Text('本机演示模式 · 未连接 CICRS 云端').fontSize(11).fontColor(this.muted).width('100%').textAlign(TextAlign.Center).padding({ top: 8, bottom: 5 });
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private discoverView() {
    Scroll() {
      Column({ space: 12 }) {
        this.sectionHeader('M-02 浏览与检索', '找一件合适的旧物', '按品类或名称筛选驿站在库物品。');
        TextInput({ text: this.searchText, placeholder: '搜索教材、台灯、衣物…' }).onChange((value: string) => this.searchText = value);
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.categories(), (category: string) => {
              Button(category)
                .fontSize(11)
                .backgroundColor(this.selectedCategory === category ? this.accent : '#E7F0EC')
                .fontColor(this.selectedCategory === category ? '#FFFFFF' : this.accent)
                .onClick(() => this.selectedCategory = category);
            }, (category: string) => category);
          }
        }.height(42).scrollable(ScrollDirection.Horizontal);
        ForEach(this.filteredItems(), (item: CicrsItem) => {
          this.itemCard(item, 'discover');
        }, (item: CicrsItem) => `discover-${item.id}`);
        if (this.filteredItems().length === 0) {
          Text('没有符合条件的在库物品，试试其他品类或关键词。').fontSize(13).fontColor(this.muted).width('100%').padding(18);
        }
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private publishView() {
    Scroll() {
      Column({ space: 12 }) {
        this.sectionHeader('M-01 发布闲置', '发布一件旧物', '真实照片与信息将用于驿站核验。');
        TextInput({ text: this.titleText, placeholder: '物品名称，例如：大一教材' }).onChange((value: string) => this.titleText = value);
        Text('物品品类').fontSize(13).fontColor(this.muted).width('100%');
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.factors().slice(0, 8), (factor: CicrsFactor) => {
              Button(factor.name)
                .fontSize(11)
                .backgroundColor(this.selectedFactorId === factor.id ? this.accent : '#E7F0EC')
                .fontColor(this.selectedFactorId === factor.id ? '#FFFFFF' : this.accent)
                .onClick(() => this.selectedFactorId = factor.id);
            }, (factor: CicrsFactor) => factor.id);
          }
        }.height(46).scrollable(ScrollDirection.Horizontal);
        Text(`选中：${this.factor().name} · 因子依据：${this.factor().source}`).fontSize(11).fontColor(this.muted).width('100%');
        Row({ space: 8 }) {
          Button('从相册添加 1–6 张照片').layoutWeight(1).onClick(() => this.pickPhotos());
          Text(`${this.imageUris.length}/6`).fontSize(12).fontColor(this.accent);
        }.width('100%');
        if (this.imageUris.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.imageUris, (uri: string, index: number) => {
                Stack() {
                  Image(uri).width(74).height(74).objectFit(ImageFit.Cover).borderRadius(8);
                  Text(`${index + 1}`).fontSize(10).fontColor('#FFFFFF').backgroundColor(this.accent).borderRadius(9).padding({ left: 5, right: 5 }).align(Alignment.TopEnd);
                }
              }, (uri: string) => uri);
            }
          }.height(82).scrollable(ScrollDirection.Horizontal);
        }
        Text('成色').fontSize(13).fontColor(this.muted).width('100%');
        Row({ space: 5 }) {
          ForEach(['全新', '近新', '轻微使用', '明显使用', '破损可用'], (label: string, index: number) => {
            Button(label).fontSize(10).backgroundColor(this.selectedCondition === index + 1 ? this.accent : '#E7F0EC').fontColor(this.selectedCondition === index + 1 ? '#FFFFFF' : this.accent).onClick(() => this.selectedCondition = index + 1);
          }, (label: string) => label);
        }.width('100%');
        Text('流转方式').fontSize(13).fontColor(this.muted).width('100%');
        Row({ space: 6 }) {
          ForEach(['donate', 'transfer', 'recycle'], (method: string) => {
            Button(transferMethodLabel(method as 'donate' | 'transfer' | 'recycle')).fontSize(11).backgroundColor(this.selectedMethod === method ? this.accent : '#E7F0EC').fontColor(this.selectedMethod === method ? '#FFFFFF' : this.accent).onClick(() => this.selectedMethod = method);
          }, (method: string) => method);
        }.width('100%');
        Row({ space: 8 }) {
          TextInput({ text: this.quantityText, placeholder: '数量（必填）' }).layoutWeight(1).type(InputType.Number).onChange((value: string) => this.quantityText = value);
          TextInput({ text: this.weightText, placeholder: '估计重量 kg（选填）' }).layoutWeight(1).type(InputType.Number).onChange((value: string) => this.weightText = value);
        }.width('100%');
        TextInput({ text: this.descriptionText, placeholder: '补充描述（选填）' }).onChange((value: string) => this.descriptionText = value).height(90);
        Text('体验版暂未接入云端 AI 识物与语音录入。').fontSize(11).fontColor(this.muted).width('100%');
        Button('提交审核').width('100%').height(46).onClick(() => this.submitItem());
      }.padding({ left: 20, right: 20, bottom: 24 });
    }.layoutWeight(1);
  }

  @Builder
  private carbonView() {
    Scroll() {
      Column({ space: 14 }) {
        this.sectionHeader('M-04 我的碳账户', '每次循环都有回响', '积分只会在完成流转或报废处置后记入。');
        Row({ space: 10 }) {
          Column({ space: 5 }) {
            Text(`${this.account.points}`).fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.accent);
            Text('碳积分').fontSize(11).fontColor(this.muted);
          }.layoutWeight(1);
          Column({ space: 5 }) {
            Text(`${formatCicrsNumber(this.account.carbonSavedKg)} kg`).fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.ink);
            Text('累计减排 CO₂e').fontSize(11).fontColor(this.muted);
          }.layoutWeight(1);
        }.width('100%').padding(16).backgroundColor('#E7F0EC').borderRadius(14);
        Text(`等效树木吸收 ${formatCicrsNumber(this.account.treeEquivalent)} 年 · 完成循环 ${this.account.completedCount} 次`).fontSize(12).fontColor(this.muted).width('100%');
        Row({ space: 8 }) {
          Button('循环明细').layoutWeight(1).backgroundColor('#FFFFFF').fontColor(this.accent).onClick(() => this.openPage('my-items'));
          Button('校园排行榜').layoutWeight(1).backgroundColor('#FFFFFF').fontColor(this.accent).onClick(() => this.openPage('ranking'));
        }.width('100%');
        Text('积分明细').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
        ForEach(cicrsRepository.getScoreRecords().filter((record: CicrsScoreRecord) => record.ownerId === this.ownerId), (record: CicrsScoreRecord) => {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text(`${record.factorId} 循环`).fontSize(13).fontColor(this.ink);
              Text(`${record.quantity} × ${formatCicrsNumber(record.factorValue)} kgCO₂e 因子`).fontSize(10).fontColor(this.muted);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Text(`+${record.points} 分`).fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.accent);
          }.width('100%').padding(12).backgroundColor('#FFFFFF').borderRadius(10);
        }, (record: CicrsScoreRecord) => record.id);
        if (cicrsRepository.getScoreRecords().filter((record: CicrsScoreRecord) => record.ownerId === this.ownerId).length === 0) {
          Text('完成一次旧物流转后，积分与减碳明细会显示在这里。').fontSize(12).fontColor(this.muted).width('100%');
        }
        Text('本机演示账本，尚未连接云端，数值不可视为正式积分。').fontSize(11).fontColor(this.muted).width('100%').padding({ top: 8 });
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private mineView() {
    Scroll() {
      Column({ space: 14 }) {
        this.sectionHeader('M-05 我的', '校园循环伙伴', '个人数据与预约服务。');
        Row({ space: 12 }) {
          Text('林').fontSize(24).fontColor('#FFFFFF').fontWeight(FontWeight.Bold).width(54).height(54).textAlign(TextAlign.Center).backgroundColor(this.accent).borderRadius(27);
          Column({ space: 4 }) {
            Text(this.nickname).fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink);
            Text('本机体验身份 · 未绑定学号').fontSize(11).fontColor(this.muted);
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          Button('个人资料').fontSize(11).backgroundColor('#E7F0EC').fontColor(this.accent).onClick(() => this.openPage('profile'));
        }.width('100%').padding(15).backgroundColor('#FFFFFF').borderRadius(12);
        Row({ space: 8 }) {
          Column({ space: 3 }) { Text(`${this.myItems().length}`).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.ink); Text('我的发布').fontSize(11).fontColor(this.muted); }.layoutWeight(1).onClick(() => this.openPage('my-items'));
          Column({ space: 3 }) { Text(`${this.activeAppointments().length}`).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.ink); Text('进行中预约').fontSize(11).fontColor(this.muted); }.layoutWeight(1).onClick(() => this.openPage('appointments'));
          Column({ space: 3 }) { Text(`${this.account.points}`).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.ink); Text('碳积分').fontSize(11).fontColor(this.muted); }.layoutWeight(1).onClick(() => this.tab = 3);
        }.width('100%').padding(14).backgroundColor('#E7F0EC').borderRadius(12);
        this.menuButton('我的发布', '查看物品状态、流转轨迹或撤回待处理发布', 'my-items');
        this.menuButton('我的预约', '投递与领取预约、核销码及取消状态', 'appointments');
        this.menuButton('消息与动态', '本机状态变化与操作记录', 'messages');
        this.menuButton('校园排行榜', '查看碳积分与减排贡献排名', 'ranking');
        this.menuButton('AI 自然语言查询', '体验个人数据的本地查询入口', 'ai-query');
        this.menuButton('帮助与规则', '了解旧物流转、减碳与积分规则', 'help');
        Button('退出本机体验').width('100%').backgroundColor('#FFFFFF').fontColor('#A04D39').onClick(() => { this.enteredDemo = false; this.page = ''; this.tab = 0; });
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private loginView() {
    Column({ space: 14 }) {
      Blank();
      Text('CICRS · 青碳汇').fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.accent).letterSpacing(1);
      Text('让校园旧物再走一程').fontSize(29).fontWeight(FontWeight.Bold).fontColor(this.ink);
      Text('学生端 · 发布闲置、发现共享物品、查看碳账户').fontSize(13).fontColor(this.muted);
      Text('当前未连接 CICRS 云端，请以本机体验身份进入：').fontSize(11).fontColor('#A04D39').width('100%').padding({ top: 14 });
      TextInput({ text: this.nickname, placeholder: '体验昵称' }).onChange((value: string) => this.nickname = value);
      Button('进入本机学生体验').width('100%').height(46).onClick(() => this.enterDemo());
      Text('此入口不执行真实身份认证；学号/手机号绑定、账号数据同步与正式积分需接云端后验收。').fontSize(10).fontColor(this.muted).width('100%');
      Blank();
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start).padding({ left: 24, right: 24 }).backgroundColor(this.pageColor);
  }

  @Builder
  private menuButton(title: string, detail: string, pageName: string) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.ink);
        Text(detail).fontSize(10).fontColor(this.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Text('›').fontSize(22).fontColor(this.muted);
    }
    .width('100%')
    .padding(13)
    .backgroundColor('#FFFFFF')
    .borderRadius(10)
    .onClick(() => this.openPage(pageName));
  }

  @Builder
  private myItemsView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('我的发布', '查看状态、核验结果和完整流转轨迹');
        ForEach(this.myItems(), (item: CicrsItem) => {
          this.itemCard(item, 'mine');
        }, (item: CicrsItem) => `mine-${item.id}`);
        if (this.myItems().length === 0) Text('还没有发布记录。').fontSize(13).fontColor(this.muted).width('100%').padding(18);
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private appointmentsView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('我的预约', '进行中的投递码与领取码');
        ForEach(this.activeAppointments(), (item: CicrsItem) => {
          this.itemCard(item, 'appointment');
        }, (item: CicrsItem) => `appointment-${item.id}`);
        if (this.activeAppointments().length === 0) Text('当前没有进行中的预约。').fontSize(13).fontColor(this.muted).width('100%').padding(18);
        Text('预约过期后，系统会释放时段或库存，并回退物品状态。').fontSize(11).fontColor(this.muted).width('100%');
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private messagesView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('消息与动态', '本机演示活动流，不代表真实推送通知');
        ForEach(this.myItems(), (item: CicrsItem) => {
          Column({ space: 6 }) {
            Row() {
              Text(item.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.ink);
              Blank();
              this.labelPill(statusInfo(item.status).label, statusInfo(item.status).color);
            }.width('100%');
            Text(item.statusEvents.length > 0 ? item.statusEvents[item.statusEvents.length - 1].note : '暂无流转记录').fontSize(12).fontColor(this.muted).width('100%');
            Text(item.updatedAt).fontSize(10).fontColor(this.muted).width('100%');
          }.width('100%').padding(13).backgroundColor('#FFFFFF').borderRadius(10);
        }, (item: CicrsItem) => `message-${item.id}`);
        if (this.myItems().length === 0) Text('目前没有动态消息。').fontSize(13).fontColor(this.muted).width('100%').padding(18);
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private profileView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('个人资料', '当前为本机体验账号');
        Text('昵称').fontSize(12).fontColor(this.muted).width('100%');
        TextInput({ text: this.nickname, placeholder: '填写昵称' }).onChange((value: string) => this.nickname = value);
        Text('学号与手机号').fontSize(12).fontColor(this.muted).width('100%');
        Text('未绑定。真实实名认证需要连接 CICRS 身份服务。').fontSize(13).fontColor(this.muted).width('100%').padding(12).backgroundColor('#FFFFFF').borderRadius(10);
        Text('退出登录 / 多设备账号同步需待云端身份接入后开放。').fontSize(11).fontColor(this.muted).width('100%');
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private rankingView() {
    Scroll() {
      Column({ space: 14 }) {
        this.subHeader('校园排行榜', '碳积分与减排贡献榜');
        Column({ space: 8 }) {
          Text('排行榜需要全校云端数据。').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.ink);
          Text('当前没有连接 CICRS 云端，因此不展示虚构名次。接入云端后将支持积分榜、减碳榜与个人百分位。').fontSize(12).fontColor(this.muted);
        }.alignItems(HorizontalAlign.Start).width('100%').padding(18).backgroundColor('#FFFFFF').borderRadius(12);
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private aiQueryView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('自然语言查询', '本地演示查询 · 云端 AI 未接入');
        TextInput({ text: this.questionText, placeholder: '例如：我有多少积分？我发布了几件物品？' }).onChange((value: string) => this.questionText = value);
        Button('查询本机数据').width('100%').onClick(() => this.runLocalQuery());
        if (this.answerText.length > 0) Text(this.answerText).fontSize(13).fontColor(this.ink).width('100%').padding(14).backgroundColor('#FFFFFF').borderRadius(10);
        Text('本地只回答个人积分和发布数量，不会假装连接 AI 或统计全校事实。').fontSize(11).fontColor(this.muted).width('100%');
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private helpView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('帮助与规则', '旧物循环流程说明');
        this.helpRow('01 发布', '填写品类、成色、数量并上传 1–6 张实物照片，提交后等待核验。');
        this.helpRow('02 预约投递', '审核通过后选择驿站与半小时预约时段，出示 8 位核销码或二维码。');
        this.helpRow('03 驿站复核', '回收员现场称重、复核成色后上架或登记报废。');
        this.helpRow('04 预约领取', '在共享货架预约物品，到站出示领取码完成核销。');
        this.helpRow('05 积分规则', '只在完成流转或报废时按留存因子、复核重量/数量、成色和方式一次性计算。');
        Text('所有本机数据和积分仅供演示。因子当前由本地配置文件载入，生产数值与有效版本应由服务端管理。').fontSize(11).fontColor(this.muted).width('100%');
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private helpRow(title: string, content: string) {
    Column({ space: 5 }) {
      Text(title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
      Text(content).fontSize(12).fontColor(this.muted).width('100%');
    }.alignItems(HorizontalAlign.Start).width('100%').padding(13).backgroundColor('#FFFFFF').borderRadius(10);
  }

  @Builder
  private bookingView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader(this.bookingType === 'delivery' ? '预约投递' : '预约领取', '选择驿站与 30 分钟时段');
        ForEach(this.items.filter((item: CicrsItem) => item.id === this.selectedItemId), (item: CicrsItem) => {
          Column({ space: 5 }) {
            Text(item.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.ink);
            Text(`${item.category} · ${statusInfo(item.status).label}`).fontSize(12).fontColor(this.muted);
          }.alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor('#FFFFFF').borderRadius(10);
        }, (item: CicrsItem) => `booking-${item.id}`);
        Text('选择驿站').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
        ForEach(CICRS_STATIONS, (station: CicrsStation) => {
          Column({ space: 4 }) {
            Row() {
              Text(station.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.ink);
              Blank();
              if (this.selectedStationId === station.id) Text('已选择').fontSize(11).fontColor(this.accent);
            }.width('100%');
            Text(station.address).fontSize(11).fontColor(this.muted).width('100%');
            Text(station.openHours).fontSize(10).fontColor(this.muted).width('100%');
          }.alignItems(HorizontalAlign.Start).width('100%').padding(12).backgroundColor(this.selectedStationId === station.id ? '#E7F0EC' : '#FFFFFF').borderRadius(10).onClick(() => this.selectedStationId = station.id);
        }, (station: CicrsStation) => station.id);
        Text('可选时段').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
        ForEach(this.bookingSlots, (slot: string) => {
          Button(this.slotLabel(slot)).width('100%').backgroundColor(this.selectedSlotStart === slot ? this.accent : '#FFFFFF').fontColor(this.selectedSlotStart === slot ? '#FFFFFF' : this.ink).onClick(() => this.selectedSlotStart = slot);
        }, (slot: string) => slot);
        Button('确认预约并生成核销码').width('100%').height(46).onClick(() => this.confirmBooking());
        Text('本机模式时段容量按本设备数据校验；并发容量必须由服务端最终约束。').fontSize(10).fontColor(this.muted).width('100%');
      }.padding({ left: 20, right: 20, bottom: 24 });
    }.layoutWeight(1);
  }

  @Builder
  private appointmentDetailView() {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('预约详情', '到站后向回收员出示核销码或二维码');
        ForEach(this.items.filter((item: CicrsItem) => item.id === this.selectedItemId), (item: CicrsItem) => {
          Column({ space: 10 }) {
            Text(item.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
            if (item.appointment !== null) {
              Text(item.appointment.type === 'delivery' ? '预约投递' : '预约领取').fontSize(12).fontColor(this.muted).width('100%');
              QRCode(item.appointment.code).width(180).height(180);
              Text(item.appointment.code).fontSize(25).fontWeight(FontWeight.Bold).fontColor(this.accent).letterSpacing(3);
              Text(item.appointment.stationName).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.ink).width('100%');
              Text(item.appointment.slot).fontSize(13).fontColor(this.muted).width('100%');
              Text(`有效至 ${item.appointment.expiresAt}`).fontSize(10).fontColor(this.muted).width('100%');
              if (item.appointment.state === 'active') Button('取消预约').width('100%').backgroundColor('#F4E9E5').fontColor('#A04D39').onClick(() => this.cancelItem(item));
            }
          }.alignItems(HorizontalAlign.Center).width('100%').padding(18).backgroundColor('#FFFFFF').borderRadius(14);
        }, (item: CicrsItem) => `appointment-detail-${item.id}`);
      }.padding({ left: 20, right: 20, bottom: 20 });
    }.layoutWeight(1);
  }

  @Builder
  private itemDetail(item: CicrsItem) {
    Scroll() {
      Column({ space: 12 }) {
        this.subHeader('物品详情', '查看图片、成色、驿站与状态轨迹');
        if (item.imageUris.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(item.imageUris, (uri: string) => Image(uri).width(150).height(150).objectFit(ImageFit.Cover).borderRadius(10), (uri: string) => uri);
            }
          }.height(160).scrollable(ScrollDirection.Horizontal);
        }
        Column({ space: 6 }) {
          Text(item.title).fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
          Text(`${item.category} · ${statusInfo(item.status).label}`).fontSize(12).fontColor(this.muted).width('100%');
          Text(`成色 ${item.conditionLevel} 档 · ${transferMethodLabel(item.transferMethod)}`).fontSize(12).fontColor(this.muted).width('100%');
          Text(`数量 ${item.quantity} ${item.factorUnit === 'kg' ? '份' : '件'} · ${item.estimatedWeightKg > 0 ? `估计 ${item.estimatedWeightKg} kg` : '待称重'}`).fontSize(12).fontColor(this.muted).width('100%');
          Text(item.description.length > 0 ? item.description : '暂无补充说明').fontSize(13).fontColor(this.ink).width('100%').padding({ top: 6 });
          if (item.verificationRemark.length > 0) Text(`核验意见：${item.verificationRemark}`).fontSize(12).fontColor(this.muted).width('100%');
          if (item.appointment !== null) Text(`驿站：${item.appointment.stationName}`).fontSize(12).fontColor(this.muted).width('100%');
        }.alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor('#FFFFFF').borderRadius(12);
        Text('流转轨迹').fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%');
        ForEach(item.statusEvents.slice().reverse(), (event: CicrsStatusEvent) => {
          Row({ space: 8 }) {
            Text('●').fontSize(12).fontColor(statusInfo(event.status).color);
            Column({ space: 4 }) {
              Text(statusInfo(event.status).label).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.ink);
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
      if (!this.enteredDemo) {
        this.loginView();
      } else {
        if (this.page.length === 0) {
          if (this.tab === 0) this.homeView();
          if (this.tab === 1) this.discoverView();
          if (this.tab === 2) this.publishView();
          if (this.tab === 3) this.carbonView();
          if (this.tab === 4) this.mineView();
          Row() {
            this.navItem('首页', 0);
            this.navItem('找旧物', 1);
            this.navItem('发布', 2);
            this.navItem('碳账户', 3);
            this.navItem('我的', 4);
          }.height(54).width('100%').backgroundColor('#FFFFFF').border({ width: { top: 1 }, color: this.line });
        } else {
          if (this.page === 'my-items') this.myItemsView();
          if (this.page === 'appointments') this.appointmentsView();
          if (this.page === 'messages') this.messagesView();
          if (this.page === 'profile') this.profileView();
          if (this.page === 'ranking') this.rankingView();
          if (this.page === 'ai-query') this.aiQueryView();
          if (this.page === 'help') this.helpView();
          if (this.page === 'booking') this.bookingView();
          if (this.page === 'appointment-detail') this.appointmentDetailView();
          if (this.page === 'detail' && this.selectedItem() === null) {
            Text('未找到物品，请返回列表刷新。').fontSize(13).fontColor(this.muted).width('100%').padding(20);
          }
          if (this.page === 'detail' && this.selectedItem() !== null) {
            ForEach(this.items.filter((item: CicrsItem) => item.id === this.selectedItemId), (item: CicrsItem) => this.itemDetail(item), (item: CicrsItem) => `detail-${item.id}`);
          }
        }
      }
      if (this.notice.length > 0) {
        Text(this.notice).fontSize(12).fontColor('#FFFFFF').backgroundColor(this.ink).borderRadius(8).padding(12).margin({ left: 18, right: 18, bottom: 7 }).width('calc(100% - 36vp)');
      }
    }
    .backgroundColor(this.pageColor)
    .width('100%')
    .height('100%');
  }

  @Builder
  private navItem(label: string, index: number) {
    Text(label)
      .fontSize(11)
      .fontColor(this.tab === index ? this.accent : this.muted)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .onClick(() => this.tab = index);
  }
}
