# CarbonLoop Backend

这是 CarbonLoop 的真实 REST 后端，不是 UI 假数据层。它负责用户身份、碳因子、低碳记录、服务端积分计算、挑战进度和排行榜。

## 启动

```powershell
cd D:\yingyongjishu\carbon\backend
npm start
```

默认监听 `0.0.0.0:8787`。

生产环境至少要配置随机的 Token 密钥；Web 客户端跨域地址可按部署域名限制：

```bash
CARBON_TOKEN_SECRET='replace-with-a-long-random-secret' \
CARBON_ALLOWED_ORIGIN='https://your-campus.example' \
npm start
```

本地开发不设置时会使用开发默认值，禁止把该默认值用于公网部署。

```text
GET  http://127.0.0.1:8787/health
POST http://127.0.0.1:8787/api/v1/auth/guest
GET  http://127.0.0.1:8787/api/v1/factors
GET  http://127.0.0.1:8787/api/v1/campus/overview
GET  http://127.0.0.1:8787/api/v1/locations
GET  http://127.0.0.1:8787/api/v1/teams
POST http://127.0.0.1:8787/api/v1/actions
GET  http://127.0.0.1:8787/api/v1/items
GET  http://127.0.0.1:8787/api/v1/rewards
POST http://127.0.0.1:8787/api/v1/rewards/:id/redeem
POST http://127.0.0.1:8787/api/v1/items
POST http://127.0.0.1:8787/api/v1/items/:id/cycle-events
```

数据持久化在 `backend/data/store.json`，写入采用临时文件替换。这个实现用于比赛开发和现场演示，后续部署到服务器时可以把存储层替换为 PostgreSQL，不需要改变 API 合同。

## 闭环原则

1. 客户端可以离线预览，但服务端重新计算减排量和积分。
2. `clientRecordId` 保证重复同步不会重复加分。
3. 每次积分都有 `pointsLedger` 流水。
4. 挑战进度从已保存记录实时汇总，不依赖前端传入的进度。
5. 因子带有版本号，后续可以接入来源和后台审核。
6. `GET /api/v1/tasks` 和 `GET /api/v1/points-ledger` 提供任务进度与积分流水；记录支持 `PATCH/DELETE /api/v1/records/:id`，撤销会回算任务奖励。
7. `GET /api/v1/rewards` 和 `POST /api/v1/rewards/:id/redeem` 使用服务端积分余额完成虚拟徽章、植树证书兑换，并保存兑换流水。

## 校园碳循环

本地演示数据包含郑州西亚斯学院示范校园、5 个低碳点位和体验宿舍 302。`POST /api/v1/actions` 支持 `locationId` 和 `clientActionId`；关联开放点位的行动标记为 `location_verified`，不关联点位的自报行为标记为 `self_reported`。

`POST /api/v1/items` 创建物品第二人生卡片。首次登记按回收因子生成一次行动和积分；`POST /api/v1/items/:id/cycle-events` 只追加交换、捐赠、维修或回收事件，不重复增加积分。当前物品重量和减排量用于 MVP 演示，正式活动启用前必须核实因子来源和回收口径。

Web 客户端会把网络失败的行动保存在当前浏览器的本地待同步队列，恢复联网后用稳定的 `clientActionId` 自动重试。清理浏览器站点数据会删除尚未同步的本地队列。

## 鸿蒙真机连接

客户端当前配置为 `http://192.168.100.102:8787`。如果电脑局域网 IPv4 发生变化，请同步修改：

```text
openharmony/CarbonLoop/entry/src/main/ets/network/ApiClient.ets
```

真机和电脑需要连接同一个局域网，并在 Windows 防火墙中允许 Node.js 或 TCP 8787 入站连接。启动后可先在电脑浏览器打开 `http://127.0.0.1:8787/health` 验证服务，再从 App 录入一条行为；服务端会重新计算减排量和积分并写入 `data/store.json`。
