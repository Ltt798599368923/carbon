import {
  CARBON_FACTORS,
  CarbonFactor,
  CarbonRecord,
  calculatePoints,
  calculateReduction,
  findFactor,
  formatKg
} from '../model/CarbonModel';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State selectedFactorId: string = 'walk';
  @State amountText: string = '3';
  @State records: CarbonRecord[] = [
    { id: 'demo-1', factorId: 'walk', amount: 3, reductionKg: 0.6, points: 6, createdAt: '今天 08:40' },
    { id: 'demo-2', factorId: 'reusable', amount: 2, reductionKg: 0.12, points: 12, createdAt: '昨天 12:20' }
  ];
  @State notice: string = '';

  private get selectedFactor(): CarbonFactor {
    return findFactor(this.selectedFactorId);
  }

  private get totalReduction(): number {
    return this.records.reduce((total: number, item: CarbonRecord) => total + item.reductionKg, 0);
  }

  private get totalPoints(): number {
    return this.records.reduce((total: number, item: CarbonRecord) => total + item.points, 0);
  }

  private get previewAmount(): number {
    const value: number = Number(this.amountText);
    return Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  private get previewReduction(): number {
    return calculateReduction(this.selectedFactor, this.previewAmount);
  }

  private get previewPoints(): number {
    return calculatePoints(this.selectedFactor, this.previewAmount);
  }

  @Builder
  private metric(label: string, value: string, unit: string, caption: string) {
    Column({ space: 4 }) {
      Text(label).fontSize(13).fontColor('#52706A');
      Row({ space: 4 }) {
        Text(value).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#123B35');
        Text(unit).fontSize(13).fontColor('#52706A').margin({ top: 7 });
      }
      Text(caption).fontSize(11).fontColor('#7A958E');
    }
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
    .layoutWeight(1);
  }

  @Builder
  private homeView() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 8 }) {
          Text('CarbonLoop').fontSize(14).fontColor('#D9F99D').fontWeight(FontWeight.Bold);
          Text('让每一次绿色选择都被看见').fontSize(26).fontWeight(FontWeight.Bold).fontColor('#FFFFFF');
          Text('记录行为 · 看见变化 · 一起完成低碳挑战').fontSize(13).fontColor('#D7EFDF');
        }
        .alignItems(HorizontalAlign.Start)
        .padding(20)
        .width('100%')
        .backgroundColor('#0F766E')
        .borderRadius(24);

        Row({ space: 10 }) {
          this.metric('累计减排', formatKg(this.totalReduction), 'kg', '可解释计算');
          this.metric('碳积分', `${this.totalPoints}`, '分', '持续积累中');
        }
        .width('100%');

        Column({ space: 10 }) {
          Row() {
            Text('今日减排指南').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
            Blank();
            Text('建议').fontSize(12).fontColor('#0F766E').backgroundColor('#E8F7E9').padding({ left: 8, right: 8, top: 4, bottom: 4 }).borderRadius(10);
          }
          Text('把一次性餐具换成自带餐具').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#23443E');
          Text('预计减少约 0.06 kg CO₂e，完成后可获得 6 个积分。').fontSize(13).fontColor('#6B817B');
          Button('去记录').onClick(() => {
            this.selectedFactorId = 'reusable';
            this.amountText = '1';
            this.currentTab = 1;
          }).backgroundColor('#D9F99D').fontColor('#123B35').borderRadius(14).width('100%');
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(20)
        .width('100%');

        Column({ space: 10 }) {
          Text('正在进行 · 校园挑战').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Row({ space: 12 }) {
            Text('🚲').fontSize(28);
            Column({ space: 4 }) {
              Text('骑行与步行周').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#23443E');
              Text('已完成 9.6 / 15 km').fontSize(13).fontColor('#6B817B');
            }.alignItems(HorizontalAlign.Start);
          }
          Progress({ value: 64, total: 100 }).color('#0F766E').backgroundColor('#DDEBE3');
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(20)
        .width('100%');
      }
      .padding({ left: 16, right: 16, top: 16, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private recordView() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 6 }) {
          Text('记录低碳行为').fontSize(26).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Text('每一笔记录都会进入你的碳账本。').fontSize(13).fontColor('#6B817B');
        }.alignItems(HorizontalAlign.Start).width('100%');

        Column({ space: 12 }) {
          Text('选择行为').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Flex({ wrap: FlexWrap.Wrap, space: { main: 8, cross: 8 } }) {
            ForEach(CARBON_FACTORS, (factor: CarbonFactor) => {
              Button(`${factor.icon} ${factor.label}`)
                .fontSize(12)
                .fontColor(factor.id === this.selectedFactorId ? '#FFFFFF' : '#315B53')
                .backgroundColor(factor.id === this.selectedFactorId ? '#0F766E' : '#EDF5EF')
                .borderRadius(14)
                .onClick(() => this.selectedFactorId = factor.id);
            }, (factor: CarbonFactor) => factor.id);
          }
          Text(`数量（${this.selectedFactor.unit}）`).fontSize(14).fontColor('#52706A');
          TextInput({ text: this.amountText, placeholder: '请输入数量' })
            .type(InputType.Number)
            .onChange((value: string) => this.amountText = value)
            .backgroundColor('#F4F8F4')
            .borderRadius(12);
          Row() {
            Column({ space: 4 }) {
              Text('预计减排').fontSize(12).fontColor('#52706A');
              Text(`${formatKg(this.previewReduction)} kg CO₂e`).fontSize(21).fontWeight(FontWeight.Bold).fontColor('#0F766E');
            }.alignItems(HorizontalAlign.Start);
            Blank();
            Text(`+${this.previewPoints} 积分`).fontSize(14).fontColor('#A35A17');
          }
          .padding(14)
          .backgroundColor('#F1F8E7')
          .borderRadius(14);
          Button('保存到我的碳账本')
            .width('100%')
            .backgroundColor('#0F766E')
            .fontColor('#FFFFFF')
            .borderRadius(14)
            .onClick(() => this.saveRecord());
          if (this.notice.length > 0) {
            Text(this.notice).fontSize(12).fontColor('#0F766E');
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(20)
        .width('100%');

        Column({ space: 10 }) {
          Text('最近记录').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
          ForEach(this.records, (record: CarbonRecord) => {
            this.recordRow(record);
          }, (record: CarbonRecord) => record.id);
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(20)
        .width('100%');
      }
      .padding({ left: 16, right: 16, top: 18, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private recordRow(record: CarbonRecord) {
    const factor: CarbonFactor = findFactor(record.factorId);
    Row({ space: 10 }) {
      Text(factor.icon).fontSize(22);
      Column({ space: 3 }) {
        Text(factor.label).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#23443E');
        Text(`${record.amount} ${factor.unit} · ${record.createdAt}`).fontSize(11).fontColor('#7A958E');
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Column({ space: 3 }) {
        Text(`-${formatKg(record.reductionKg)} kg`).fontSize(14).fontColor('#0F766E');
        Text(`+${record.points} 积分`).fontSize(11).fontColor('#A35A17');
      }.alignItems(HorizontalAlign.End);
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 });
  }

  private saveRecord(): void {
    if (this.previewAmount <= 0) {
      this.notice = '请输入大于 0 的数量';
      return;
    }
    const factor: CarbonFactor = this.selectedFactor;
    const record: CarbonRecord = {
      id: `${Date.now()}`,
      factorId: factor.id,
      amount: this.previewAmount,
      reductionKg: this.previewReduction,
      points: this.previewPoints,
      createdAt: '刚刚'
    };
    this.records = [record, ...this.records];
    this.notice = `已记录 ${factor.label}，获得 ${record.points} 个积分`;
  }

  build() {
    Column() {
      if (this.currentTab === 0) {
        this.homeView();
      } else {
        this.recordView();
      }
      Row() {
        Button('首页').layoutWeight(1).backgroundColor(this.currentTab === 0 ? '#E3F2E5' : '#FFFFFF').fontColor('#0F766E').onClick(() => this.currentTab = 0);
        Button('记录').layoutWeight(1).backgroundColor(this.currentTab === 1 ? '#E3F2E5' : '#FFFFFF').fontColor('#0F766E').onClick(() => this.currentTab = 1);
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 12 })
      .backgroundColor('#FFFFFF');
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F8F6');
  }
}

