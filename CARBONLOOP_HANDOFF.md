# CarbonLoop 项目交接文档

**交接日期**：2026-10-30
**项目目录**：`/Users/yinzhenyu1/Desktop/carbon`
**产品定位**：面向高校学生的低碳生活账本，首版创新点为“旧物第二人生”。

## 1. 当前完成范围

### 后端

- 低碳行为记录：创建、查询、修改、删除。
- 因子目录、减排估算、积分流水。
- 每日任务、挑战加入和进度统计。
- 积分奖励目录、一次性兑换、虚拟徽章/植树证书兑换记录。
- 访客登录和本地后端同步。
- 旧物第二人生接口：
  - `GET /api/v1/items`
  - `POST /api/v1/items`
  - `POST /api/v1/items/:id/cycle-events`
- 旧物首次登记会生成一次回收行动和积分；后续流转事件不会重复发放首次积分。

### Web 原型

- 目录：`prototype/`
- 已拆分 API、本地存储、因子目录和离线队列模块。
- 已加入毛玻璃视觉、移动端适配、加载/空状态/失败提示。
- 保留原有首页、记录、趋势、挑战、我的、科普和旧物功能。
- Web 原型仍保留校园地图；它与鸿蒙 CarbonLoop 是两套独立前端，不会自动同步 UI。

### 鸿蒙 CarbonLoop

- 工程：`openharmony/CarbonLoop/`
- 已保留碳账本、趋势、行为记录、挑战、个人中心、科普和数据导出。
- 新增独立“旧物”底部工作区：
  - 登记物品名称、类型和重量。
  - 选择交换、捐赠、维修或回收。
  - 查看第二人生卡片、状态、流转次数、估算减排和首次积分。
  - 追加后续流转状态。
- 旧物首次登记成功后，会立即写入本地碳账本，首页总减排、积分和记录列表同步更新。
- 地图已从鸿蒙端主导航、页面、启动初始化请求和客户端地图类型/方法中移除。
- 历史记录的 `locationId` 字段仍保留，避免破坏已有数据和后端兼容性。

### 开源项目集成边界（必须明确）

当前**没有把 CICRS 开源项目的代码完整接入 CarbonLoop**。本轮完成的是 CarbonLoop 自己的一套旧物第二人生 MVP：鸿蒙页面、CarbonLoop REST API 和本地碳账本之间已经真实连通，不是只有一个展示窗口。

已实现的 CarbonLoop 原生能力：

- 个人登记旧物并生成卡片。
- 选择交换、捐赠、维修或回收。
- 追加流转事件并更新状态和次数。
- 首次登记生成一次碳账本行动和积分，后续事件不重复计奖。
- 后端持久化、查询和重复登记保护。

尚未完成的“完整开源项目接入”能力：

- CICRS 学生端和回收员端的完整角色协作。
- 物品发布、预约、交接确认、核销和二维码流程。
- 回收员/管理端、运营后台、审核和状态审计。
- 图片凭证、消息通知、交易或真实回收订单流程。
- CICRS 完整订单链路和跨角色离线队列（CarbonLoop 原生旧物 MVP 已支持本地持久化与创建/流转待同步队列）。

因此接手时应将旧物模块标记为：**CarbonLoop 原生 MVP 已完成，CICRS 开源项目完整集成未完成**。`openharmony/CICRS-Student-Harmony/` 和 `openharmony/CICRS-Recycler-Harmony/` 仍是独立工程，不是 CarbonLoop 的运行依赖。

### 可直接复用的重构基线

这两个 CICRS 工程不是待重新搭建的空项目，而是已经完成鸿蒙原生重构、可以打开和构建的演示基线：

- `CICRS-Student-Harmony`：学生端发布闲置、搜索、物品详情、预约投递/领取、二维码/核销码、碳账户和状态轨迹。
- `CICRS-Recycler-Harmony`：回收员端驿站工作台、扫码收货、扫码领取、待处置、上架和报废。
- 两个工程当前使用本机演示仓储，尚未接入真实 CICRS 云端鉴权、API、图片上传和生产事务。

下一位开发者不需要重新寻找或重新搭建旧物业务，应以这两个重构工程作为交互和状态机参考，按下面顺序接入 CarbonLoop：

1. 先保留 CarbonLoop 的个人碳账本和 `itemCycles` 接口，避免破坏已有积分和减排口径。
2. 将学生端的发布、详情、预约和状态轨迹映射到 CarbonLoop 的第二人生卡片。
3. 再根据实际需求接入回收员端的收货、交接、核销和处置流程。
4. 最后把本机演示仓储替换为统一后端 API，并补齐角色鉴权、幂等、并发预约和审计。

本次 GitHub 交付应包含这两个重构工程，但它们仍作为独立鸿蒙应用目录保留；“包含源码”不等于“已经完成 CarbonLoop 运行时集成”。

## 2. 重要文件

| 文件 | 用途 |
|---|---|
| `backend/src/server.mjs` | REST API、旧物流转和积分奖励兑换逻辑 |
| `backend/src/store.mjs` | 后端本地数据结构和持久化 |
| `backend/tests/api.test.mjs` | 后端 API 测试 |
| `tests/emission-factors.test.js` | 因子和计算测试 |
| `prototype/app.js` | Web 原型状态和事件编排 |
| `prototype/modules/` | Web API、本地存储、因子和离线队列 |
| `openharmony/CarbonLoop/entry/src/main/ets/pages/Index.ets` | 鸿蒙主页面和旧物工作区 |
| `openharmony/CarbonLoop/entry/src/main/ets/network/ApiClient.ets` | 鸿蒙 API 客户端和旧物接口 |
| `openharmony/CarbonLoop/entry/src/main/ets/model/CarbonModel.ets` | 鸿蒙因子、记录和趋势计算 |
| `openharmony/CarbonLoop/entry/src/main/ets/storage/CarbonStorage.ets` | 鸿蒙本地记录、令牌和同步状态存储 |
| `DESIGN_IMPLEMENTATION_PLAN.md` | 设计和实施基线 |
| `FRONTEND_IMPLEMENTATION_PLAN.md` | Web 前端实施计划 |

不要在 CarbonLoop 主工程中直接混入以下独立工程；接入工作应通过明确的适配层和 API 设计完成：

- `openharmony/CICRS-Student-Harmony/`
- `openharmony/CICRS-Recycler-Harmony/`

## 3. 启动方式

### 启动后端

```bash
cd /Users/yinzhenyu1/Desktop/carbon/backend
npm run dev
```

默认地址：`http://127.0.0.1:8787`
健康检查：`http://127.0.0.1:8787/health`

### 启动 Web 原型

```bash
cd /Users/yinzhenyu1/Desktop/carbon/prototype
python3 -m http.server 4175
```

访问：`http://127.0.0.1:4175`

### 构建鸿蒙 HAP

```bash
cd /Users/yinzhenyu1/Desktop/carbon/openharmony/CarbonLoop
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
assembleHap --mode module -p module=entry@default -p product=default --no-daemon
```

输出文件：

`openharmony/CarbonLoop/entry/build/default/outputs/default/entry-default-unsigned.hap`

当前 HAP 未配置签名，真机安装前需要在 DevEco Studio 配置调试签名。

## 4. 已完成验证

- 后端 API 测试：7/7 通过。
- 因子测试：4/4 通过。
- 鸿蒙 `assembleHap`：构建成功。
- `git diff --check`：通过。
- 已覆盖后端旧物重复登记和后续流转不重复计奖。

根目录没有 `package.json`，不要执行根目录 `npm test`；使用下面两个实际测试命令：

```bash
npm --prefix backend test
node --test tests/emission-factors.test.js
```

## 5. 接手后的第一优先级

### P0：回归测试

1. 无网络启动，完成一条普通低碳记录。
2. 修改、删除记录，检查本地数据和积分回算。
3. 测试日、周、月、年趋势和分类筛选。
4. 测试挑战加入、每日任务、积分和徽章状态。
5. 测试 JSON 备份、恢复和 CSV 导出。
6. 测试科普页面、空状态、失败提示和重试。

### P1：旧物第二人生验收

1. 分别登记交换、捐赠、维修、回收四种物品。
2. 检查登记后首页减排、积分和记录列表是否同步更新。
3. 重新启动或重新登录，确认旧物卡片和状态仍存在。
4. 连续点击同一流转状态，确认不会重复增加事件或积分。
5. 测试空名称、空类型、负重量、零重量、超大重量和网络失败。
6. 检查四种状态按钮在小屏设备上没有文字溢出。

### P2：优化项

- 将旧物待同步队列与统一后台任务/应用生命周期进一步整合。
- 补充旧物 loading、空状态、错误和重试状态。
- 使用统一因子版本，减少 Web、鸿蒙和后端因子口径漂移。
- 在目标模拟器或真机安装 HAP，完成端到端验收。
- 检查 320px 宽度下底部 7 个导航项的可读性。

## 6. 交接约束

- 不要把校园地图重新加入鸿蒙首版主流程。
- 不要把 Web 和鸿蒙强行合并成一个工程。
- 不要修改 CICRS 两个鸿蒙工程。
- 不要把估算减排量描述为核证碳资产。
- 旧物首次登记只允许计一次首次积分，后续流转默认只更新生命周期。
- 保持现有 CarbonLoop UI 的颜色、页头、白色信息块和圆角体系，优化应以局部改进为主。
- 修改前先确认工作区已有未提交变更，不要覆盖其他人的工作。

## 7. 当前已知限制

- 尚未完成真机/模拟器安装和完整 UI 验收。
- 鸿蒙旧物登记和流转更新已支持本地持久化与待同步队列；完整 CICRS 角色协作和生产级订单离线事务仍未接入。
- 因子中的部分减排数值仍属于演示口径，正式提交前需补齐来源、基准和适用范围。
- HAP 当前为 unsigned 包。
