export interface KnowledgeArticle {
  id: string;
  category: string;
  title: string;
  summary: string;
  body: string;
  source: string;
  updatedAt: string;
}

export const KNOWLEDGE_ARTICLES: KnowledgeArticle[] = [
  {
    id: 'carbon-basics',
    category: '双碳科普',
    title: '碳达峰与碳中和，和日常生活有什么关系？',
    summary: '先理解“排放”和“减排”的关系，再看懂自己的低碳记录。',
    body: '碳达峰指碳排放量达到峰值后进入下降阶段，碳中和指通过减排、替代和必要的抵消，让排放与吸收相平衡。个人应用中的减排量是基于行为和因子得出的估算，不等于经过核证的碳信用。记录的价值在于帮助我们看见习惯变化，并持续做出更绿色的选择。',
    source: '内容说明：依据公开“双碳”基础概念整理，提交前需结合正式政策来源复核。',
    updatedAt: '2026-10-29'
  },
  {
    id: 'green-mobility',
    category: '绿色出行',
    title: '短距离出行，为什么可以优先考虑步行和骑行？',
    summary: '把可替代的小汽车短途出行换成主动出行，是容易坚持的低碳行动。',
    body: '步行和骑行通常不需要直接燃烧化石燃料，短距离出行时还可以减少拥堵和停车带来的额外消耗。记录时应填写真实或合理估计的距离，并查看应用采用的比较基准与因子版本。没有可靠距离时，不要为了积分随意填大数。',
    source: '内容说明：绿色出行建议；排放因子仍需按比赛要求补充正式来源。',
    updatedAt: '2026-10-29'
  },
  {
    id: 'save-energy-water',
    category: '节能节水',
    title: '节约用电用水，从一个可观察的动作开始',
    summary: '关灯、关闭待机设备、缩短用水时间，都比口号更容易形成习惯。',
    body: '节能节水的记录应该尽量对应可观察的数量或任务，例如电表变化、活动规定的节能动作或明确的节水时长。应用展示的减排结果必须说明估算口径；如果无法可靠量化，可以先记录行为和任务完成状态，不强行显示精确的减排数字。',
    source: '内容说明：生活节能建议；具体因子和计量方法需结合本地口径复核。',
    updatedAt: '2026-10-29'
  },
  {
    id: 'food-waste',
    category: '光盘行动',
    title: '光盘行动不只是“吃完”，更是减少食物浪费',
    summary: '按需取餐、合理点餐、打包剩余食物，都是减少浪费的行动。',
    body: '食物从种植、加工、运输到烹饪都消耗资源，没被吃掉的部分还会产生额外处理负担。记录光盘行动时，可以记录一次明确完成的行动或活动任务，不把吃得过量当成低碳。减排结果应建立在明确的食物类型和基准研究上。',
    source: '内容说明：反食品浪费生活建议；光盘行动因子暂待正式来源确认。',
    updatedAt: '2026-10-29'
  },
  {
    id: 'second-life',
    category: '旧物循环',
    title: '让旧物拥有“第二人生”',
    summary: '转赠、交换、维修和再利用，通常比直接丢弃更能延长物品寿命。',
    body: '旧物循环的重点不是“回收得越重越好”，而是减少不必要的新购买和废弃。可以为旧书、衣物和生活用品建立一张循环卡片，记录它从登记、转赠、维修到再次使用的过程。没有可靠的品类和去向因子时，应用只展示循环事实和自报状态，不虚构减排量。',
    source: '内容说明：旧物循环设计说明；品类因子需在正式核算前逐项复核。',
    updatedAt: '2026-10-29'
  }
];

export function findArticle(id: string): KnowledgeArticle {
  for (const article of KNOWLEDGE_ARTICLES) {
    if (article.id === id) {
      return article;
    }
  }
  return KNOWLEDGE_ARTICLES[0];
}
