import { LengthMetrics } from '@kit.ArkUI';
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
  @State challengeJoined: boolean = false;
  @State challengeNotice: string = '';

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

  private joinChallenge(): void {
    this.challengeJoined = true;
    this.challengeNotice = '已加入挑战，完成低碳行为后进度会自动更新';
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
          this.metric('累计减排', formatKg(this.calculateTotalReduction()), 'kg', '可解释计算');
          this.metric('碳积分', `${this.calculateTotalPoints()}`, '分', '持续积累中');
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
          Row() {
            Text('正在进行 · 校园挑战').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
            Blank();
            Text(this.challengeJoined ? '已加入' : '推荐').fontSize(12).fontColor('#0F766E').backgroundColor('#E8F7E9').padding({ left: 8, right: 8, top: 4, bottom: 4 }).borderRadius(10);
          }
          Row({ space: 12 }) {
            Text('🚲').fontSize(28);
            Column({ space: 4 }) {
              Text('骑行与步行周').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#23443E');
              Text(`${this.getChallengeProgress()} / 15 km`).fontSize(13).fontColor('#6B817B');
            }.alignItems(HorizontalAlign.Start);
          }
          Progress({ value: this.getChallengeProgress(), total: 15 }).color('#0F766E').backgroundColor('#DDEBE3');
          Button('查看挑战').onClick(() => this.currentTab = 2)
            .backgroundColor('#EDF5EF').fontColor('#0F766E').borderRadius(12).width('100%');
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
  private challengeView() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 8 }) {
          Text('校园挑战').fontSize(14).fontColor('#D9F99D').fontWeight(FontWeight.Bold);
          Text('和同学一起，把低碳变成习惯').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF');
          Text('完成行为记录，自动累计挑战进度').fontSize(13).fontColor('#D7EFDF');
        }
        .alignItems(HorizontalAlign.Start)
        .padding(20)
        .width('100%')
        .backgroundColor('#0F766E')
        .borderRadius(24);

        Column({ space: 12 }) {
          Row() {
            Text('🚲').fontSize(30);
            Blank();
            Text(this.challengeJoined ? '进行中' : '可加入').fontSize(12).fontColor('#0F766E').backgroundColor('#E8F7E9').padding({ left: 8, right: 8, top: 4, bottom: 4 }).borderRadius(10);
          }
          Text('骑行与步行周').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Text('本周累计步行或骑行 15 公里，完成后获得校园低碳徽章。').fontSize(13).fontColor('#6B817B');
          Row() {
            Text(`${this.getChallengeProgress()} km`).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#0F766E');
            Blank();
            Text('目标 15 km').fontSize(13).fontColor('#52706A');
          }
          Progress({ value: this.getChallengeProgress(), total: 15 }).color('#0F766E').backgroundColor('#DDEBE3');
          if (!this.challengeJoined) {
            Button('加入挑战').width('100%').backgroundColor('#D9F99D').fontColor('#123B35').borderRadius(14).onClick(() => this.joinChallenge());
          } else {
            Text('你已加入挑战，去记录一次步行或骑行吧。').fontSize(13).fontColor('#0F766E');
          }
          if (this.challengeNotice.length > 0) {
            Text(this.challengeNotice).fontSize(12).fontColor('#0F766E');
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(20)
        .width('100%');

        Column({ space: 10 }) {
          Text('完成挑战的小建议').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Text('每天记录一次校园内的步行或骑行，进度会自动累计。').fontSize(13).fontColor('#6B817B');
          Button('记录一次步行 / 骑行').width('100%').backgroundColor('#EDF5EF').fontColor('#0F766E').borderRadius(14).onClick(() => {
            this.selectedFactorId = 'walk';
            this.amountText = '1';
            this.currentTab = 1;
          });
          Button('记录公交 / 地铁').width('100%').backgroundColor('#EDF5EF').fontColor('#0F766E').borderRadius(14).onClick(() => {
            this.selectedFactorId = 'transit';
            this.amountText = '1';
            this.currentTab = 1;
          });
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(20)
        .width('100%');

        Column({ space: 8 }) {
          Text('挑战规则').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Text('• 仅“步行 / 骑行出行”会计入本次挑战进度。').fontSize(13).fontColor('#6B817B');
          Text('• 每次记录都会同时获得碳积分和减排量。').fontSize(13).fontColor('#6B817B');
          Text('• 当前版本为本地演示数据，后续可接入校园排行榜。').fontSize(13).fontColor('#6B817B');
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#F1F8E7')
        .borderRadius(20)
        .width('100%');
      }
      .padding({ left: 16, right: 16, top: 18, bottom: 24 });
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
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
            ForEach(CARBON_FACTORS, (factor: CarbonFactor) => {
              Button(`${factor.icon} ${factor.label}`)
                .fontSize(12)
                .fontColor(factor.id === this.selectedFactorId ? '#FFFFFF' : '#315B53')
                .backgroundColor(factor.id === this.selectedFactorId ? '#0F766E' : '#EDF5EF')
                .borderRadius(14)
                .onClick(() => this.selectedFactorId = factor.id);
            }, (factor: CarbonFactor) => factor.id);
          }
          Text(`数量（${this.getSelectedFactor().unit}）`).fontSize(14).fontColor('#52706A');
          TextInput({ text: this.amountText, placeholder: '请输入数量' })
            .type(InputType.Number)
            .onChange((value: string) => this.amountText = value)
            .backgroundColor('#F4F8F4')
            .borderRadius(12);
          Row() {
            Column({ space: 4 }) {
              Text('预计减排').fontSize(12).fontColor('#52706A');
              Text(`${formatKg(this.getPreviewReduction())} kg CO₂e`).fontSize(21).fontWeight(FontWeight.Bold).fontColor('#0F766E');
            }.alignItems(HorizontalAlign.Start);
            Blank();
            Text(`+${this.getPreviewPoints()} 积分`).fontSize(14).fontColor('#A35A17');
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
    Row({ space: 10 }) {
      Text(findFactor(record.factorId).icon).fontSize(22);
      Column({ space: 3 }) {
        Text(findFactor(record.factorId).label).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#23443E');
        Text(`${record.amount} ${findFactor(record.factorId).unit} · ${record.createdAt}`).fontSize(11).fontColor('#7A958E');
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
    this.notice = `已记录 ${factor.label}，获得 ${record.points} 个积分`;
  }

  build() {
    Column() {
      if (this.currentTab === 0) {
        this.homeView();
      } else if (this.currentTab === 1) {
        this.recordView();
      } else {
        this.challengeView();
      }
      Row() {
        Button('首页').layoutWeight(1).backgroundColor(this.currentTab === 0 ? '#E3F2E5' : '#FFFFFF').fontColor('#0F766E').onClick(() => this.currentTab = 0);
        Button('记录').layoutWeight(1).backgroundColor(this.currentTab === 1 ? '#E3F2E5' : '#FFFFFF').fontColor('#0F766E').onClick(() => this.currentTab = 1);
        Button('挑战').layoutWeight(1).backgroundColor(this.currentTab === 2 ? '#E3F2E5' : '#FFFFFF').fontColor('#0F766E').onClick(() => this.currentTab = 2);
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




