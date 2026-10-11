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
import { carbonPreferences } from '../entryability/EntryAbility';
import { loadChallengeJoined, loadRecords, saveChallengeJoined, saveRecords } from '../storage/CarbonStorage';

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

  aboutToAppear(): void {
    const savedRecords: CarbonRecord[] | null = loadRecords(carbonPreferences);
    if (savedRecords === null) {
      saveRecords(carbonPreferences, this.records);
    } else {
      this.records = savedRecords;
    }
    this.challengeJoined = loadChallengeJoined(carbonPreferences);
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

  private joinChallenge(): void {
    this.challengeJoined = true;
    saveChallengeJoined(carbonPreferences, true);
    this.challengeNotice = '已加入挑战，完成低碳行为后进度会自动更新';
  }

  private calculateRecordCount(): number {
    return this.records.length;
  }

  private hasFirstRecordBadge(): boolean {
    return this.records.length >= 1;
  }

  private hasReductionBadge(): boolean {
    return this.calculateTotalReduction() >= 1;
  }

  private hasChallengeBadge(): boolean {
    return this.challengeJoined;
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
      Column({ space: 14 }) {
        Column({ space: 5 }) {
          Text('挑战').fontSize(13).fontColor('#0F766E').fontWeight(FontWeight.Bold);
          Text('骑行与步行周').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Text('用 15 公里的绿色出行，换一枚校园低碳徽章。').fontSize(13).fontColor('#6B817B');
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ top: 8, bottom: 4 });

        Column({ space: 12 }) {
          Row() {
            Row({ space: 8 }) {
              Text('🚲').fontSize(24);
              Text(this.challengeJoined ? '进行中' : '可加入').fontSize(12).fontColor('#0F766E').backgroundColor('#E7F4EC').padding({ left: 8, right: 8, top: 4, bottom: 4 }).borderRadius(8);
            }
            Blank();
            Text('本周挑战').fontSize(12).fontColor('#8A9B95');
          }
          Text('把通勤变成减排行动').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Text('记录步行或骑行里程，进度会自动累计。').fontSize(13).fontColor('#6B817B');
          Row() {
            Column({ space: 2 }) {
              Text(`${this.getChallengeProgress()} km`).fontSize(30).fontWeight(FontWeight.Bold).fontColor('#0F766E');
              Text('已完成').fontSize(11).fontColor('#7A958E');
            }.alignItems(HorizontalAlign.Start);
            Blank();
            Column({ space: 2 }) {
              Text('15 km').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#52706A');
              Text('目标里程').fontSize(11).fontColor('#7A958E');
            }.alignItems(HorizontalAlign.End);
          }
          Progress({ value: this.getChallengeProgress(), total: 15 }).color('#0F766E').backgroundColor('#E1ECE6');
          if (!this.challengeJoined) {
            Button('加入挑战').width('100%').backgroundColor('#C9F57D').fontColor('#123B35').borderRadius(12).onClick(() => this.joinChallenge());
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
        .borderRadius(16)
        .width('100%');

        Column({ space: 10 }) {
          Text('快速记录').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Text('今天就完成一笔低碳出行记录。').fontSize(13).fontColor('#6B817B');
          Row({ space: 8 }) {
            Button('步行 / 骑行')
              .layoutWeight(1)
              .fontSize(13)
              .backgroundColor('#EAF4EE')
              .fontColor('#0F766E')
              .borderRadius(11)
              .onClick(() => {
                this.selectedFactorId = 'walk';
                this.amountText = '1';
                this.currentTab = 1;
              });
            Button('公交 / 地铁')
              .layoutWeight(1)
              .fontSize(13)
              .backgroundColor('#EAF4EE')
              .fontColor('#0F766E')
              .borderRadius(11)
              .onClick(() => {
                this.selectedFactorId = 'transit';
                this.amountText = '1';
                this.currentTab = 1;
              });
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .width('100%');

        Column({ space: 8 }) {
          Text('挑战规则').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Text('01  仅步行 / 骑行出行会计入本次挑战进度。').fontSize(13).fontColor('#6B817B');
          Text('02  每次记录都会同时获得碳积分和减排量。').fontSize(13).fontColor('#6B817B');
          Text('03  当前为本地演示版本，排行榜暂不接入真实校园数据。').fontSize(13).fontColor('#6B817B');
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#EEF5F0')
        .borderRadius(16)
        .width('100%');
      }
      .padding({ left: 18, right: 18, top: 12, bottom: 24 });
    }
    .layoutWeight(1);
  }

  @Builder
  private badgeCard(icon: string, title: string, description: string, earned: boolean) {
    Column({ space: 6 }) {
      Text(icon).fontSize(28).opacity(earned ? 1 : 0.35);
      Text(title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(earned ? '#123B35' : '#78908A');
      Text(description).fontSize(11).fontColor(earned ? '#52706A' : '#9AAEA8').maxLines(2);
      Text(earned ? '已解锁' : '待解锁')
        .fontSize(11)
        .fontColor(earned ? '#0F766E' : '#8A9B95')
        .backgroundColor(earned ? '#E3F2E5' : '#F0F3F1')
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(8);
    }
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .layoutWeight(1)
    .backgroundColor(earned ? '#F1F8E7' : '#F7F9F8')
    .borderRadius(16);
  }

  @Builder
  private pointDetailRow(record: CarbonRecord) {
    Row({ space: 10 }) {
      Text(findFactor(record.factorId).icon).fontSize(20);
      Column({ space: 3 }) {
        Text(findFactor(record.factorId).label).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#23443E');
        Text(record.createdAt).fontSize(11).fontColor('#7A958E');
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Text(`+${record.points} 分`).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#A35A17');
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 });
  }

  @Builder
  private rankingRow(rank: string, name: string, points: string, isCurrentUser: boolean) {
    Row({ space: 10 }) {
      Text(rank).fontSize(16).fontWeight(FontWeight.Bold).fontColor(isCurrentUser ? '#0F766E' : '#7A958E').width(24);
      Text(name).fontSize(13).fontWeight(isCurrentUser ? FontWeight.Bold : FontWeight.Medium).fontColor('#23443E').layoutWeight(1);
      Text(`${points} 分`).fontSize(13).fontColor(isCurrentUser ? '#0F766E' : '#52706A');
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
    .backgroundColor(isCurrentUser ? '#F1F8E7' : '#FFFFFF')
    .borderRadius(10);
  }

  @Builder
  private factorInfoCard(factor: CarbonFactor) {
    Row({ space: 10 }) {
      Text(factor.icon).fontSize(22);
      Column({ space: 4 }) {
        Text(factor.label).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#23443E');
        Text(`每 1 ${factor.unit} 减少 ${formatKg(factor.reductionKgPerUnit)} kg CO₂e`).fontSize(11).fontColor('#6B817B');
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Text(`+${factor.pointsPerUnit} 分/${factor.unit}`).fontSize(11).fontColor('#A35A17');
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 });
  }

  @Builder
  private profileView() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 5 }) {
          Text('我的').fontSize(13).fontColor('#0F766E').fontWeight(FontWeight.Bold);
          Text('低碳行动者').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Text('把每一次选择，积累成看得见的改变。').fontSize(13).fontColor('#6B817B');
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ top: 8, bottom: 4 });

        Row({ space: 10 }) {
          this.metric('累计减排', formatKg(this.calculateTotalReduction()), 'kg', '绿色行动成果');
          this.metric('碳积分', `${this.calculateTotalPoints()}`, '分', '持续积累中');
        }
        .width('100%');

        Column({ space: 10 }) {
          Text('行动概览').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Row() {
            Column({ space: 4 }) {
              Text(`${this.calculateRecordCount()}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#0F766E');
              Text('已记录行为').fontSize(12).fontColor('#6B817B');
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Column({ space: 4 }) {
              Text(this.challengeJoined ? '进行中' : '未加入').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#0F766E');
              Text('校园挑战').fontSize(12).fontColor('#6B817B');
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          }
          Text('数据保存在本机，重新打开应用后仍会保留。').fontSize(12).fontColor('#7A958E');
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .width('100%');

        Column({ space: 10 }) {
          Row() {
            Text('低碳徽章').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
            Blank();
            Text('持续行动，解锁更多').fontSize(11).fontColor('#7A958E');
          }
          Row({ space: 8 }) {
            this.badgeCard('🌱', '绿色起点', '完成第一次低碳行为记录', this.hasFirstRecordBadge());
            this.badgeCard('🌍', '减排新星', '累计减排达到 1 kg CO₂e', this.hasReductionBadge());
          }
          Row({ space: 8 }) {
            this.badgeCard('🏆', '校园挑战者', '加入校园低碳挑战', this.hasChallengeBadge());
            this.badgeCard('✨', '持续行动', '累计完成 5 次低碳记录', this.records.length >= 5);
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .width('100%');

        Column({ space: 10 }) {
          Row() {
            Text('积分明细').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
            Blank();
            Text('每次记录都会获得积分').fontSize(11).fontColor('#7A958E');
          }
          ForEach(this.records, (record: CarbonRecord) => {
            this.pointDetailRow(record);
          }, (record: CarbonRecord) => `points-${record.id}`);
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .width('100%');

        Column({ space: 10 }) {
          Row() {
            Text('校园排行榜').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
            Blank();
            Text('本地演示').fontSize(11).fontColor('#7A958E');
          }
          this.rankingRow('1', '绿色先锋', '128', false);
          this.rankingRow('2', '校园减碳队', '96', false);
          this.rankingRow('3', '低碳行动者', `${this.calculateTotalPoints()}`, true);
          Text('排行榜为演示数据，后续可接入校园账号和云端数据。').fontSize(11).fontColor('#7A958E');
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .width('100%');

        Column({ space: 8 }) {
          Text('下一步建议').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
          Text(this.challengeJoined ? '继续完成步行或骑行记录，争取达成 15 公里挑战。' : '先加入校园挑战，再记录一次步行或骑行。').fontSize(13).fontColor('#6B817B');
          Button(this.challengeJoined ? '去记录低碳行为' : '去参加校园挑战')
            .width('100%')
            .backgroundColor('#C9F57D')
            .fontColor('#123B35')
            .borderRadius(12)
            .onClick(() => this.currentTab = this.challengeJoined ? 1 : 2);
        }
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#EEF5F0')
        .borderRadius(16)
        .width('100%');
      }
      .padding({ left: 18, right: 18, top: 12, bottom: 24 });
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


        Column({ space: 10 }) {
          Row() {
            Text('碳因子说明').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#123B35');
            Blank();
            Text('透明计算规则').fontSize(11).fontColor('#7A958E');
          }
          Text('以下数值用于校园演示，记录数量 × 对应碳因子 = 预计减排量。').fontSize(12).fontColor('#6B817B');
          ForEach(CARBON_FACTORS, (factor: CarbonFactor) => {
            this.factorInfoCard(factor);
          }, (factor: CarbonFactor) => `factor-${factor.id}`);
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
    saveRecords(carbonPreferences, this.records);
    this.notice = `已记录 ${factor.label}，获得 ${record.points} 个积分`;
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
        Button('首页').layoutWeight(1).backgroundColor(this.currentTab === 0 ? '#E3F2E5' : '#FFFFFF').fontColor('#0F766E').onClick(() => this.currentTab = 0);
        Button('记录').layoutWeight(1).backgroundColor(this.currentTab === 1 ? '#E3F2E5' : '#FFFFFF').fontColor('#0F766E').onClick(() => this.currentTab = 1);
        Button('挑战').layoutWeight(1).backgroundColor(this.currentTab === 2 ? '#E3F2E5' : '#FFFFFF').fontColor('#0F766E').onClick(() => this.currentTab = 2);
        Button('我的').layoutWeight(1).backgroundColor(this.currentTab === 3 ? '#E3F2E5' : '#FFFFFF').fontColor('#0F766E').onClick(() => this.currentTab = 3);
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




