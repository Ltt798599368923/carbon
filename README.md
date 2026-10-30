# Carbon

碳足迹·全民绿色生活碳积分与减排指南项目。

当前产品方向：**CarbonLoop / 碳行校园**，面向高校学生的低碳生活闭环助手。

## 当前状态

- `prototype/`：无需构建工具的 Web 客户端，已连接本地 CarbonLoop REST 后端，包含校园碳循环地图和旧物第二人生卡片。
- `data/`：演示用碳排放因子数据，正式提交前必须补齐来源、版本和适用范围。
- `tests/`：Node.js 内置测试，校验演示因子和主流程计算结果。
- `openharmony/CarbonLoop/`：原先的 CarbonLoop 独立客户端（保留，不与 CICRS 鸿蒙适配混用）。
- `openharmony/CICRS-Student-Harmony/`：CICRS 青碳汇鸿蒙学生端，独立应用包。
- `openharmony/CICRS-Recycler-Harmony/`：CICRS 青碳汇鸿蒙回收员端，独立应用包。
- `openharmony/CICRS-FEATURE-PARITY.md`：按原 CICRS PRD 对照的鸿蒙端完成度与缺口清单。
- `PRODUCT_DESIGN.md`：CarbonLoop “校园碳循环地图”产品设计和实施基线。

## 目录约定

- 核心代码、配置与测试文件全部放在本目录。
- 比赛通知、方案文档、演示材料等非核心资料放在上级目录，与 `carbon` 并列。

## 快速运行 Web 客户端

先启动后端：

```bash
cd backend
npm start
```

再启动静态 Web 客户端：

```bash
cd prototype
python3 -m http.server 4173
```

然后访问 `http://127.0.0.1:4173`。客户端默认请求 `http://127.0.0.1:8787`，也可以在页面加载前设置 `window.CARBON_API_URL` 指向其他后端地址。

## 运行测试

```powershell
cd D:\应用技术大赛\carbon
node --test tests\emission-factors.test.js
```

## OpenHarmony 验证

如果要运行原 CarbonLoop，请打开 `openharmony/CarbonLoop`；如果要运行 CICRS 鸿蒙适配，请分别打开 `openharmony/CICRS-Student-Harmony` 或 `openharmony/CICRS-Recycler-Harmony`。两个 CICRS 工程不是同一个应用，分别对应学生端和回收员端。
