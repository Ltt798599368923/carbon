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
- 旧物卡片支持 Preferences 本地持久化，断网创建/流转会进入待同步队列，联网后自动补偿到后端
- 已适配本机 HarmonyOS 6.0.1（API 21）构建配置

## 打开工程

DevEco Studio / Hvigor 会拒绝包含中文目录名的工程路径。当前 Windows 工作区请使用：

```text
D:\yingyongjishu\carbon\openharmony\CarbonLoop
```

如果复制到其他纯英文目录，也需要同步确认 `ApiClient.ets` 中的后端地址。

## 使用方式

1. 使用 DevEco Studio 打开 `D:\CarbonLoop\openharmony\CarbonLoop`。
2. 等待项目同步完成。
3. 点击 Build → Build Hap(s) 进行构建。
4. 根据本机设备情况选择模拟器或真机运行。
5. 如果 DevEco Studio 提示 Windows Defender 排除目录失败，可以先忽略，该提示不等同于代码构建失败。

## 命令行构建（Windows）

```powershell
cd D:\yingyongjishu\carbon\openharmony\CarbonLoop
$env:DEVECO_SDK_HOME='D:\daimaruanjian\Huawei\DevEco Studio\sdk'
& 'D:\daimaruanjian\Huawei\DevEco Studio\tools\node\node.exe' `
  'D:\daimaruanjian\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js' `
  --mode module -p product=default assembleHap --analyze=normal --parallel --incremental --no-daemon
```

输出文件：

`entry\build\default\outputs\default\entry-default-unsigned.hap`

## 已验证

在本机 DevEco Studio 工具链下，使用已安装的 HarmonyOS 6.0.1（API 21）配置进行 `assembleHap` 构建成功。当前仅有未配置签名的警告；连接设备运行前，再在 DevEco Studio 中配置调试签名即可。

## 下一步

- 在目标模拟器或真机安装 HAP，完成离线创建旧物、恢复联网和待同步队列的端到端验收。
- 增加手机与平板之间的分布式数据同步演示。
- 将 `data/emission-factors.json` 的来源说明补齐，并让 ArkTS、Web 原型和后端共用同一份正式规则。
- 配置调试签名并完成真机安装验证。

> 当前版本已包含 CarbonLoop REST 后端、访客身份、本地缓存、普通记录离线同步和旧物创建/流转待同步队列；仍不包含真实账号体系、CICRS 生产级订单协作和最终核证碳排放因子。`CarbonModel.ets` 中的部分因子仍是产品验证用演示值，提交前要替换为有来源、版本和适用边界的正式数据。
