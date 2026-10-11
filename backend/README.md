# CarbonLoop Backend

这是 CarbonLoop 的真实 REST 后端，不是 UI 假数据层。它负责用户身份、碳因子、低碳记录、服务端积分计算、挑战进度和排行榜。

## 启动

```powershell
cd D:\yingyongjishu\carbon\backend
npm start
```

默认监听 `0.0.0.0:8787`。

```text
GET  http://127.0.0.1:8787/health
POST http://127.0.0.1:8787/api/v1/auth/guest
GET  http://127.0.0.1:8787/api/v1/factors
```

数据持久化在 `backend/data/store.json`。这个实现用于比赛开发和现场演示，后续部署到服务器时可以把存储层替换为 PostgreSQL，不需要改变 API 合同。

## 闭环原则

1. 客户端可以离线预览，但服务端重新计算减排量和积分。
2. `clientRecordId` 保证重复同步不会重复加分。
3. 每次积分都有 `pointsLedger` 流水。
4. 挑战进度从已保存记录实时汇总，不依赖前端传入的进度。
5. 因子带有版本号，后续可以接入来源和后台审核。

## 鸿蒙真机连接

客户端当前配置为 `http://192.168.100.102:8787`。如果电脑局域网 IPv4 发生变化，请同步修改：

```text
openharmony/CarbonLoop/entry/src/main/ets/network/ApiClient.ets
```

真机和电脑需要连接同一个局域网，并在 Windows 防火墙中允许 Node.js 或 TCP 8787 入站连接。启动后可先在电脑浏览器打开 `http://127.0.0.1:8787/health` 验证服务，再从 App 录入一条行为；服务端会重新计算减排量和积分并写入 `data/store.json`。
