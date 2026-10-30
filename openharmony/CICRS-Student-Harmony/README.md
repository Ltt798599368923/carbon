# CICRS 青碳汇 OpenHarmony 学生端

这是 CICRS（青碳汇）面向鸿蒙系统的学生端原生 ArkTS 应用。它与 `CICRS-Recycler-Harmony` 是两个独立应用包，Web 管理后台仍是原仓库 `admin-web`，不把三端混在同一个产品里。

## 当前已实现（对应 CICRS PRD）

- 学生端五个主区：`首页`、`找旧物`、`发布`、`碳账户`、`我的`。
- F-01：发布闲置、品类/成色/方式、数量与可选估重、1–6 张照片。
- F-02/F-03：按品类/关键词检索、查看详情、选择驿站与 30 分钟时段、预约投递/领取、二维码与 8 位核销码。
- F-04：碳积分、减排量、等效树木、循环明细入口。
- F-05/F-06：消息动态与个人资料入口；当前为本机状态活动流/体验昵称，不是订阅消息或真实实名认证。
- M-05：我的发布、我的预约、排行榜入口、AI 查询入口、帮助与规则。
- 物品详情：图片、成色、驿站、核验意见和完整状态轨迹；支持待核验/已通过/待投递撤回。
- 碳因子从 `resources/rawfile/cicrs-factors.json` 载入，没有散落在页面代码中。

## 打开工程

在 DevEco Studio 中直接打开：

```text
/Users/yinzhenyu1/Desktop/carbon/openharmony/CICRS-Student-Harmony
```

## 使用方式

1. 使用 DevEco Studio 打开 `/Users/yinzhenyu1/Desktop/carbon/openharmony/CICRS-Student-Harmony`。
2. 等待项目同步完成。
3. 点击 Build → Build Hap(s) 进行构建。
4. 根据本机设备情况选择模拟器或真机运行。
5. 如果 DevEco Studio 提示 Windows Defender 排除目录失败，可以先忽略，该提示不等同于代码构建失败。

## 已验证

在本机 DevEco Studio 工具链下，使用 HarmonyOS 6.0.1（API 21）执行 `assembleHap` 构建成功。当前仅有未配置签名警告；连接设备运行前，在 DevEco Studio 中配置调试签名即可。

命令行验证命令：

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p module=entry@default -p product=default --no-daemon
```

## 演示边界与下一步

- 当前是本机演示模式，启动页和碳账户均明确提示“未连接 CICRS 云端”；演示积分不能当作生产积分。
- 启动后先进入本机体验身份，不执行真实登录；生产环境需接入身份服务、学号/手机号绑定和账号同步。
- 生产环境需把状态流转、预约并发、积分结算迁移到服务端事务，并接入图片上传和驿站 RBAC。回收员端已接 ScanKit，但该能力依赖兼容的鸿蒙设备。
- F-05 目前是本机状态动态，不是真实订阅通知；F-06 目前只有体验昵称编辑，没有实名认证。
- 校园排行、AI 拍照识物/语音、后台管理 F-11 至 F-15 和云端联调尚未移植；当前自然语言查询只支持本机规则问答。
- 继续开发时优先接入 CICRS 云函数/API，再补发布编辑/草稿、图片上传、推送通知、完整筛选和报表。

> 当前版本是可评审、可构建的鸿蒙原生业务骨架，不包含真实账号、云端同步和生产级因子服务。因子目录保留来源字段和版本边界，接云端时应由服务端统一下发。
