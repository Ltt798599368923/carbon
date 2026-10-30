# CICRS 鸿蒙适配

鸿蒙端按 CICRS 原产品结构拆成两个独立应用，不在同一页面里切换学生/回收员身份：

- `CICRS-Student-Harmony/`：学生端，包名 `com.cicrs.greenhub.student`。
- `CICRS-Recycler-Harmony/`：回收员端，包名 `com.cicrs.greenhub.recycler`。
- CICRS Web 管理后台继续使用原仓库中的 `admin-web/`，此处没有将其伪装成鸿蒙原生应用。

两端目前是原生 ArkTS 本机演示适配层，各自保存本机演示数据。接 CICRS 云端后，必须由服务端统一处理鉴权、共享业务数据、预约容量、驿站隔离、状态事务和积分结算；客户端本地演示积分不是正式积分。

详细的原 PRD 功能差异、待补项目与验收边界见 [CICRS-FEATURE-PARITY.md](CICRS-FEATURE-PARITY.md)。两个 HAP 当前已在 HarmonyOS 6.0.1（API 21）通过 `assembleHap` 构建；当前机器未检测到 hdc 设备，尚未完成模拟器/真机运行验收。
