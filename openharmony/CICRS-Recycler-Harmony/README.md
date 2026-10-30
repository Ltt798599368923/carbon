# CICRS 青碳汇 OpenHarmony 回收员端

这是独立于学生端的回收员鸿蒙应用，包名为 `com.cicrs.greenhub.recycler`。学生端、回收员端和 Web 管理后台分别运行，生产环境通过同一 CICRS 云端 API 共享业务数据。

## 已覆盖的回收员模块

- 独立演示登录入口：选择体验驿站；真实账号密码与驿站绑定仍需接原 CICRS 鉴权。
- 工作台：本驿站待处理数量、扫码收货、扫码领取、待处置入口。
- 扫码收货：鸿蒙 ScanKit 扫描预约码，校验有效期、核销幂等与驿站归属，录入实际重量和复核成色。
- 待处置：已收货物品上架（货位占用校验）或报废（原因必填并按回收处置因子结算）。
- 领取核销：预约领取码完成 `RESERVED → COMPLETED`，一次性结算学生碳积分。
- 台账、库存、物品详情和回收员资料入口；待处置支持编辑货位号和必填报废原因。

## 打开与构建

在 DevEco Studio 中打开：

```text
/Users/yinzhenyu1/Desktop/carbon/openharmony/CICRS-Recycler-Harmony
```

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p module=entry@default -p product=default --no-daemon
```

当前工程是本机演示适配层，尚未接入原项目的真实云端登录/API；不要把本机账本当成生产数据。学生端的本机演示仓储也不会自动同步到此应用。Web 管理后台仍直接使用原 CICRS 仓库的 `admin-web`，鸿蒙端不替代它。当前本机没有连接 hdc 设备，HAP 仅完成编译，尚未实机运行验收。
