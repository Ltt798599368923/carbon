import { http } from '@kit.NetworkKit';

export interface ApiFactor {
  id: string;
  label: string;
  unit: string;
  icon?: string;
  reductionKgPerUnit: number;
  pointsPerUnit: number;
  version: string;
  source?: string;
  baseline?: string;
  calculationStatus?: 'estimated_demo' | 'behavior_only';
}

export interface ApiRecord {
  id: string;
  userId?: string;
  clientRecordId: string;
  factorId: string;
  factorVersion: string;
  amount: number;
  reductionKg: number;
  points: number;
  occurredAt: string;
  createdAt: string;
  verificationStatus?: 'self_reported' | 'location_verified';
  locationId?: string | null;
}

export interface ApiTask {
  id: string;
  name: string;
  description: string;
  factorIds: string[];
  target: number;
  unit: string;
  rewardPoints: number;
  period: string;
  day: string;
  progress: number;
  completed: boolean;
}

export interface ApiReward {
  id: string;
  name: string;
  description: string;
  cost: number;
  kind: string;
  code: string;
  limitPerUser: number;
  redeemed: boolean;
  canRedeem: boolean;
}

export interface ApiRedemption {
  id: string;
  rewardId: string;
  rewardName: string;
  cost: number;
  kind: string;
  code: string;
  createdAt: string;
}

export interface ApiPointsLedgerEntry {
  id: string;
  recordId?: string;
  taskId?: string;
  taskDate?: string;
  points: number;
  reason: string;
  createdAt: string;
}

export interface ApiUser {
  id: string;
  nickname: string;
  campus: string;
  createdAt: string;
}

export interface DashboardSummary {
  totalReductionKg: number;
  totalPoints: number;
  recordCount: number;
  participantCount?: number;
  actionCount?: number;
  activeLocationCount?: number;
}

export interface ApiChallenge {
  id: string;
  name: string;
  description: string;
  target: number;
  unit: string;
  reward: string;
  joined: boolean;
  progress: number;
  completed: boolean;
}

export interface ApiItemEvent {
  id: string;
  type: string;
  label: string;
  note: string;
  locationId?: string | null;
  actor?: string;
  createdAt: string;
}

export interface ApiItemAppointment {
  type: 'delivery' | 'pickup';
  code: string;
  stationId: string;
  stationName: string;
  slot: string;
  slotStartsAt: string;
  expiresAt: string;
  state: 'active' | 'used' | 'canceled' | 'expired';
  usedAt?: string | null;
}

export interface ApiStation {
  id: string;
  name: string;
  address: string;
  openHours: string;
  enabled: boolean;
}

export interface ApiItem {
  id: string;
  clientItemId: string;
  title: string;
  itemType: string;
  weightKg: number;
  flow: string;
  status: string;
  cycleCount: number;
  reductionKg: number;
  points: number;
  quantity?: number;
  conditionLevel?: number | null;
  verifiedConditionLevel?: number | null;
  description?: string;
  imageUris?: string[];
  transferMethod?: string;
  workflowStatus: string;
  workflowStatusLabel: string;
  appointment?: ApiItemAppointment | null;
  stationId?: string | null;
  shelfLocation?: string;
  verificationRemark?: string;
  events: ApiItemEvent[];
  updatedAt: string;
  createdAt: string;
  owner?: ApiUser;
  requestCount?: number;
  hasMyPendingRequest?: boolean;
}

export interface ApiItemSummary {
  id: string;
  title: string;
  itemType: string;
  flow: string;
  status: string;
}

export interface ApiServiceItemSummary {
  id: string;
  title: string;
  itemType: string;
  status: string;
}

export interface ApiItemRequest {
  id: string;
  itemId: string;
  ownerId: string;
  applicantId: string;
  type: string;
  message: string;
  offerTitle: string;
  status: string;
  createdAt: string;
  updatedAt: string;
  item?: ApiItemSummary;
  applicant?: ApiUser;
  owner?: ApiUser;
  isIncoming?: boolean;
}

export interface ApiServiceOrder {
  id: string;
  itemId: string;
  requesterId: string;
  providerId?: string | null;
  type: string;
  description: string;
  locationId?: string | null;
  scheduledAt?: string | null;
  status: string;
  createdAt: string;
  updatedAt: string;
  item?: ApiServiceItemSummary;
  requester?: ApiUser;
  provider?: ApiUser;
}

export interface RequestPayload {
  deviceId?: string;
  nickname?: string;
  campus?: string;
  clientRecordId?: string;
  factorId?: string;
  amount?: number;
  occurredAt?: string;
  locationId?: string;
  clientItemId?: string;
  title?: string;
  itemType?: string;
  weightKg?: number;
  flow?: string;
  conditionLevel?: number;
  quantity?: number;
  imageUris?: string[];
  transferMethod?: string;
  type?: string;
  stationId?: string;
  slot?: string;
  slotStartsAt?: string;
  code?: string;
  actualWeightKg?: number;
  verifiedConditionLevel?: number;
  shelfLocation?: string;
  reason?: string;
  note?: string;
  message?: string;
  offerTitle?: string;
  itemId?: string;
  description?: string;
  scheduledAt?: string;
  public?: boolean;
}

interface RequestHeaders {
  'Content-Type': string;
  'Accept': string;
  Authorization?: string;
}

interface ApiEnvelope {
  ok: boolean;
  token?: string;
  user?: ApiUser;
  factors?: ApiFactor[];
  record?: ApiRecord;
  records?: ApiRecord[];
  challenge?: ApiChallenge;
  summary?: DashboardSummary;
  challenges?: ApiChallenge[];
  recentRecords?: ApiRecord[];
  tasks?: ApiTask[];
  pointsLedger?: ApiPointsLedgerEntry[];
  rewards?: ApiReward[];
  redemptions?: ApiRedemption[];
  totalPoints?: number;
  reward?: ApiReward;
  redemption?: ApiRedemption;
  item?: ApiItem;
  items?: ApiItem[];
  stations?: ApiStation[];
  requests?: ApiItemRequest[];
  request?: ApiItemRequest;
  orders?: ApiServiceOrder[];
  order?: ApiServiceOrder;
}

// 模拟器使用 10.0.2.2；真机请改成运行 backend 的电脑局域网 IPv4 地址。
const SERVER_URL: string = 'http://10.0.2.2:8787';

export class CarbonApiClient {
  private token: string = '';

  public setToken(token: string): void {
    this.token = token;
  }

  public async guestLogin(deviceId: string): Promise<ApiEnvelope> {
    return this.request('/api/v1/auth/guest', http.RequestMethod.POST, { deviceId, nickname: '校园用户', campus: '我的校园' });
  }

  public async getFactors(): Promise<ApiFactor[]> {
    const response: ApiEnvelope = await this.request('/api/v1/factors', http.RequestMethod.GET);
    return response.factors ?? [];
  }

  public async createRecord(clientRecordId: string, factorId: string, amount: number, occurredAt: string, locationId?: string): Promise<ApiRecord> {
    const response: ApiEnvelope = await this.request('/api/v1/records', http.RequestMethod.POST, {
      clientRecordId,
      factorId,
      amount,
      occurredAt,
      locationId
    });
    if (response.record === undefined) {
      throw new Error('后端没有返回记录');
    }
    return response.record;
  }

  public async getDashboard(): Promise<ApiEnvelope> {
    return this.request('/api/v1/dashboard', http.RequestMethod.GET);
  }

  public async getRecords(): Promise<ApiRecord[]> {
    const response: ApiEnvelope = await this.request('/api/v1/records', http.RequestMethod.GET);
    return response.records ?? [];
  }

  public async deleteRecord(recordId: string): Promise<void> {
    await this.request(`/api/v1/records/${encodeURIComponent(recordId)}`, http.RequestMethod.DELETE);
  }

  public async updateRecord(recordId: string, factorId: string, amount: number, occurredAt: string): Promise<ApiRecord> {
    const response: ApiEnvelope = await this.request(`/api/v1/records/${encodeURIComponent(recordId)}`, http.RequestMethod.PUT, {
      factorId,
      amount,
      occurredAt
    });
    if (response.record === undefined) {
      throw new Error('后端没有返回更新后的记录');
    }
    return response.record;
  }

  public async getRewards(): Promise<ApiEnvelope> {
    return this.request('/api/v1/rewards', http.RequestMethod.GET);
  }

  public async redeemReward(rewardId: string): Promise<ApiEnvelope> {
    return this.request(`/api/v1/rewards/${encodeURIComponent(rewardId)}/redeem`, http.RequestMethod.POST);
  }

  public async getTasks(): Promise<ApiTask[]> {
    const response: ApiEnvelope = await this.request('/api/v1/tasks', http.RequestMethod.GET);
    return response.tasks ?? [];
  }

  public async joinChallenge(challengeId: string): Promise<ApiChallenge> {
    const response: ApiEnvelope = await this.request(`/api/v1/challenges/${challengeId}/join`, http.RequestMethod.POST);
    if (response.challenge === undefined) {
      throw new Error('后端没有返回挑战');
    }
    return response.challenge;
  }

  public async getItems(): Promise<ApiItem[]> {
    const response: ApiEnvelope = await this.request('/api/v1/items', http.RequestMethod.GET);
    return response.items ?? [];
  }

  public async getItemCatalog(): Promise<ApiItem[]> {
    const response: ApiEnvelope = await this.request('/api/v1/items/catalog', http.RequestMethod.GET);
    return response.items ?? [];
  }

  public async getStations(): Promise<ApiStation[]> {
    const response: ApiEnvelope = await this.request('/api/v1/items/stations', http.RequestMethod.GET);
    return response.stations ?? [];
  }

  public async createItem(clientItemId: string, title: string, itemType: string, weightKg: number, flow: string): Promise<ApiItem> {
    const response: ApiEnvelope = await this.request('/api/v1/items', http.RequestMethod.POST, {
      clientItemId,
      title,
      itemType,
      weightKg,
      flow
    });
    if (response.item === undefined) {
      throw new Error('后端没有返回旧物卡片');
    }
    return response.item;
  }

  public async approveItem(itemId: string): Promise<ApiItem> {
    return this.workflowAction(itemId, 'approve');
  }

  public async rejectItem(itemId: string, reason: string): Promise<ApiItem> {
    return this.workflowAction(itemId, 'reject', { reason });
  }

  public async bookItem(itemId: string, type: 'delivery' | 'pickup', stationId: string, slot: string, slotStartsAt: string): Promise<ApiItem> {
    return this.workflowAction(itemId, 'appointments', { type, stationId, slot, slotStartsAt });
  }

  public async verifyDelivery(itemId: string, code: string, stationId: string, actualWeightKg: number, verifiedConditionLevel: number): Promise<ApiItem> {
    return this.workflowAction(itemId, 'verify-delivery', { code, stationId, actualWeightKg, verifiedConditionLevel });
  }

  public async shelveItem(itemId: string, shelfLocation: string): Promise<ApiItem> {
    return this.workflowAction(itemId, 'shelve', { shelfLocation });
  }

  public async reserveItem(itemId: string, stationId: string, slot: string, slotStartsAt: string): Promise<ApiItem> {
    return this.workflowAction(itemId, 'reserve', { stationId, slot, slotStartsAt });
  }

  public async completeItem(itemId: string): Promise<ApiItem> {
    return this.workflowAction(itemId, 'complete');
  }

  public async scrapItem(itemId: string, reason: string): Promise<ApiItem> {
    return this.workflowAction(itemId, 'scrap', { reason });
  }

  public async addItemCycleEvent(itemId: string, type: string): Promise<ApiItem> {
    const response: ApiEnvelope = await this.request(`/api/v1/items/${encodeURIComponent(itemId)}/cycle-events`, http.RequestMethod.POST, { type });
    if (response.item === undefined) {
      throw new Error('后端没有返回更新后的旧物卡片');
    }
    return response.item;
  }

  private async workflowAction(itemId: string, action: string, payload?: RequestPayload): Promise<ApiItem> {
    const response: ApiEnvelope = await this.request(`/api/v1/items/${encodeURIComponent(itemId)}/${action}`, http.RequestMethod.POST, payload);
    if (response.item === undefined) {
      throw new Error('后端没有返回更新后的旧物卡片');
    }
    return response.item;
  }

  public async getMarketItems(flow?: string): Promise<ApiItem[]> {
    const suffix: string = flow === undefined ? '' : `?flow=${encodeURIComponent(flow)}`;
    const response: ApiEnvelope = await this.request(`/api/v1/items/market${suffix}`, http.RequestMethod.GET);
    return response.items ?? [];
  }

  public async createItemRequest(itemId: string, message: string, offerTitle?: string): Promise<ApiItemRequest> {
    const response: ApiEnvelope = await this.request(`/api/v1/items/${encodeURIComponent(itemId)}/requests`, http.RequestMethod.POST, { message, offerTitle });
    if (response.request === undefined) throw new Error('后端没有返回申请');
    return response.request;
  }

  public async getRequests(scope: string = 'all'): Promise<ApiItemRequest[]> {
    const response: ApiEnvelope = await this.request(`/api/v1/requests?scope=${encodeURIComponent(scope)}`, http.RequestMethod.GET);
    return response.requests ?? [];
  }

  public async decideRequest(requestId: string, action: 'accept' | 'reject' | 'cancel'): Promise<ApiItemRequest> {
    const response: ApiEnvelope = await this.request(`/api/v1/requests/${encodeURIComponent(requestId)}/${action}`, http.RequestMethod.POST);
    if (response.request === undefined) throw new Error('后端没有返回申请状态');
    return response.request;
  }

  public async completeRequest(requestId: string): Promise<ApiItemRequest> {
    const response: ApiEnvelope = await this.request(`/api/v1/requests/${encodeURIComponent(requestId)}/complete`, http.RequestMethod.POST);
    if (response.request === undefined) throw new Error('后端没有返回完成状态');
    return response.request;
  }

  public async getServiceOrders(scope: string = 'mine'): Promise<ApiServiceOrder[]> {
    const response: ApiEnvelope = await this.request(`/api/v1/service-orders?scope=${encodeURIComponent(scope)}`, http.RequestMethod.GET);
    return response.orders ?? [];
  }

  public async createServiceOrder(itemId: string, description: string, locationId?: string): Promise<ApiServiceOrder> {
    const response: ApiEnvelope = await this.request('/api/v1/service-orders', http.RequestMethod.POST, { itemId, description, locationId });
    if (response.order === undefined) throw new Error('后端没有返回服务订单');
    return response.order;
  }

  public async acceptServiceOrder(orderId: string): Promise<ApiServiceOrder> {
    const response: ApiEnvelope = await this.request(`/api/v1/service-orders/${encodeURIComponent(orderId)}/accept`, http.RequestMethod.POST);
    if (response.order === undefined) throw new Error('后端没有返回接单状态');
    return response.order;
  }

  public async completeServiceOrder(orderId: string): Promise<ApiServiceOrder> {
    const response: ApiEnvelope = await this.request(`/api/v1/service-orders/${encodeURIComponent(orderId)}/complete`, http.RequestMethod.POST);
    if (response.order === undefined) throw new Error('后端没有返回订单状态');
    return response.order;
  }

  private async request(path: string, method: http.RequestMethod, payload?: RequestPayload): Promise<ApiEnvelope> {
    const request = http.createHttp();
    try {
      let headers: RequestHeaders = {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      };
      if (this.token.length > 0) {
        headers = {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': `Bearer ${this.token}`
        };
      }
      const options: http.HttpRequestOptions = {
        method,
        header: headers,
        connectTimeout: 8000,
        readTimeout: 8000,
        expectDataType: http.HttpDataType.STRING
      };
      if (payload !== undefined) {
        options.extraData = JSON.stringify(payload);
      }
      const response: http.HttpResponse = await request.request(`${SERVER_URL}${path}`, options);
      if (Number(response.responseCode) < 200 || Number(response.responseCode) >= 300) {
        throw new Error(`后端返回 ${response.responseCode}`);
      }
      if (typeof response.result !== 'string') {
        throw new Error('后端响应格式错误');
      }
      return JSON.parse(response.result) as ApiEnvelope;
    } finally {
      request.destroy();
    }
  }
}
