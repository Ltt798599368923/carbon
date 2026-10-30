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
  createdAt: string;
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
  events: ApiItemEvent[];
  updatedAt: string;
  createdAt: string;
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
  type?: string;
  note?: string;
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
  item?: ApiItem;
  items?: ApiItem[];
}

// 模拟器使用 10.0.2.2；真机请改成运行 backend 的电脑局域网 IPv4 地址。
const SERVER_URL: string = 'http://192.168.100.102:8787';

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

  public async addItemCycleEvent(itemId: string, type: string): Promise<ApiItem> {
    const response: ApiEnvelope = await this.request(`/api/v1/items/${encodeURIComponent(itemId)}/cycle-events`, http.RequestMethod.POST, { type });
    if (response.item === undefined) {
      throw new Error('后端没有返回更新后的旧物卡片');
    }
    return response.item;
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
