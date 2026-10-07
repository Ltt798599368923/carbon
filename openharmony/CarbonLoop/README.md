# CarbonLoop OpenHarmony / ArkTS MVP

这里是 CarbonLoop（碳行校园）的 OpenHarmony 第一版业务骨架，当前先覆盖“碳账本 + 低碳行为记录”主流程。

## 当前已实现

- 手机 / 平板设备类型声明
- 首页数据概览：累计减排、碳积分、减排指南、校园挑战卡片
- 行为记录：选择行为、输入数量、实时计算减排量与积分
- 最近记录：新增记录即时展示
- 计算逻辑独立于 UI，位于 `entry/src/main/ets/model/CarbonModel.ets`

## 使用方式

1. 使用 DevEco Studio 创建一个同名的 Stage 模型 ArkTS 工程，或打开此目录尝试导入。
2. 将 `entry/src/main/ets` 与 `entry/src/main/resources` 保留为本项目版本。
3. 根据本机 SDK / DevEco Studio 版本调整 `build-profile.json5` 中的 `compatibleSdkVersion`。
4. 编译并在模拟器或真机上运行，验证首页、记录行为和返回首页流程。

> 当前版本是可评审的业务骨架，不包含真实账号、云端同步和最终碳排放因子来源。`CarbonModel.ets` 中的因子仍是产品验证用演示值，后续要替换为有来源、版本和适用边界的正式数据。

## 下一步

- 用 Preferences / RDB 持久化记录，替换当前内存状态。
- 增加挑战加入状态与个人中心。
- 增加手机与平板之间的分布式数据同步演示。
- 将 `data/emission-factors.json` 的来源说明补齐，并让 ArkTS 和 Web 原型共用同一份规则。
