# Carbon

碳足迹·全民绿色生活碳积分与减排指南项目。

当前产品方向：**CarbonLoop / 碳行校园**，面向高校学生的低碳生活闭环助手。

## 当前状态

- `prototype/`：无需构建工具的 Web 交互原型，用于快速确认产品流程。
- `data/`：演示用碳排放因子数据，正式提交前必须补齐来源、版本和适用范围。
- `tests/`：Node.js 内置测试，校验演示因子和主流程计算结果。
- `openharmony/CarbonLoop/`：OpenHarmony / ArkTS MVP 工程骨架，已实现首页、行为记录、可解释碳计算和最近记录。

## 目录约定

- 核心代码、配置与测试文件全部放在本目录。
- 比赛通知、方案文档、演示材料等非核心资料放在上级目录，与 `carbon` 并列。

## 快速运行 Web 原型

```powershell
cd D:\应用技术大赛\carbon\prototype
python -m http.server 4173
```

然后访问 `http://127.0.0.1:4173`。

## 运行测试

```powershell
cd D:\应用技术大赛\carbon
node --test tests\emission-factors.test.js
```

## OpenHarmony 验证

请使用 DevEco Studio 打开 `openharmony/CarbonLoop`。如果本机 SDK 版本与模板不同，优先根据 `openharmony/CarbonLoop/README.md` 调整构建配置，再运行模拟器或真机验证。
