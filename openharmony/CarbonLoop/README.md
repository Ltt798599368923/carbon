# CarbonLoop OpenHarmony / ArkTS MVP

这里是 CarbonLoop（碳行校园）的 OpenHarmony 第一版业务骨架，当前覆盖“碳账本 + 低碳行为记录 + 旧物第二人生”主流程。

## 当前已实现

- 手机 / 平板设备类型声明
- 首页数据概览：累计减排、碳积分、减排指南、校园挑战卡片
- 行为记录：选择行为、输入数量、实时计算减排量与积分
- 最近记录：新增记录即时展示
- 旧物第二人生：登记物品、选择首个去向、查看流转卡片并更新交换/捐赠/维修/回收状态
- 地图已从首版鸿蒙主导航和启动同步中移除；后端点位接口与历史记录字段保留兼容
- 计算逻辑独立于 UI，位于 `entry/src/main/ets/model/CarbonModel.ets`
- 已适配本机 HarmonyOS 6.0.1（API 21）构建配置

## 打开工程

DevEco Studio / Hvigor 会拒绝包含中文目录名的工程路径。请使用下面这个纯英文路径打开：

```text
D:\CarbonLoop\openharmony\CarbonLoop
```

`D:\应用技术大赛\carbon` 保留为项目资料入口和代码镜像；真正用于 DevEco Studio 编译的路径是上面的 `D:\CarbonLoop`。

## 使用方式

1. 使用 DevEco Studio 打开 `D:\CarbonLoop\openharmony\CarbonLoop`。
2. 等待项目同步完成。
3. 点击 Build → Build Hap(s) 进行构建。
4. 根据本机设备情况选择模拟器或真机运行。
5. 如果 DevEco Studio 提示 Windows Defender 排除目录失败，可以先忽略，该提示不等同于代码构建失败。

## 命令行构建

macOS 本机 DevEco SDK 位于 `/Applications/DevEco-Studio.app/Contents/sdk`。Hvigor 需要通过 `DEVECO_SDK_HOME` 获得该路径：

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p module=entry@default -p product=default --no-daemon
```

## 已验证

在本机 DevEco Studio 工具链下，使用已安装的 HarmonyOS 6.0.1（API 21）配置进行 `assembleHap` 构建成功。当前仅有未配置签名的警告；连接设备运行前，再在 DevEco Studio 中配置调试签名即可。

## 下一步

- 用 Preferences / RDB 持久化记录，替换当前内存状态。
- 增加挑战加入状态与个人中心。
- 增加手机与平板之间的分布式数据同步演示。
- 将 `data/emission-factors.json` 的来源说明补齐，并让 ArkTS 和 Web 原型共用同一份规则。

> 当前版本是可评审的业务骨架，不包含真实账号、云端同步和最终碳排放因子来源。`CarbonModel.ets` 中的因子仍是产品验证用演示值，后续要替换为有来源、版本和适用边界的正式数据。
