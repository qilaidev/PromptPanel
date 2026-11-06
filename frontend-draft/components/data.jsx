// Sample data — realistic but not branded

const PROJECTS = [
  { id: 'all', name: '全部', count: 11, system: true },
  { id: 'promptpanel', name: 'PromptPanel', count: 5, current: true },
  { id: 'fangzhou', name: '方舟业务', count: 2 },
  { id: 'common', name: '通用项目', count: 4, common: true },
];

// kind: reply(回复), prompt(Prompt), note(说明)
const ENTRIES = [
  {
    id: 'e1', title: 'Bug 修复回执', kind: 'reply', project: 'promptpanel',
    tags: ['回执', '工程'], pinned: true, uses: 12, lastUsed: '1小时前',
    content: '问题现象 根因 修复内容 验证结果 风险与回滚',
    shortcut: '1',
  },
  {
    id: 'e2', title: '代码审计结论', kind: 'chat', project: 'common',
    tags: ['审计', '工程'], pinned: true, uses: 18, lastUsed: '40分钟前',
    content: '请直接列出 P0–P2 级问题、根因、影响面和建议修法。',
    shortcut: '2',
  },
  {
    id: 'e3', title: '发布前检查清单', kind: 'note', project: 'promptpanel',
    tags: ['发布', '检查清单'], uses: 6, lastUsed: '3小时前',
    content: '1. 跑 swift build 和 swift test  2. 验证权限与自动粘贴链路  3. 检查数据目录和备份状态  4. 本地冷启动确认面板弹出  5. 核对快捷键组合',
    shortcut: '3',
  },
  {
    id: 'e4', title: '设计收口提示词', kind: 'prompt', project: 'promptpanel',
    tags: ['设计', 'AI'], uses: 4, lastUsed: '1天前',
    content: '请基于当前截图判断主链路是否足够紧凑,并给出最值得优先解决的 3 个点。',
    shortcut: '4',
  },
  {
    id: 'e5', title: '交付说明模板', kind: 'reply', project: 'promptpanel',
    tags: ['交付'], uses: 2, lastUsed: '2天前',
    content: '本次改动已完成实现、构建验证和窗口级验收,未触及数据结构兼容边界。',
    shortcut: '5',
  },
  {
    id: 'e6', title: '状态同步', kind: 'reply', project: 'common',
    tags: ['同步'], uses: 20, lastUsed: '5小时前',
    content: '已完成本地验证,下面是当前真实状态与剩余风险。',
    shortcut: '6',
  },
  {
    id: 'e7', title: '日报摘要', kind: 'note', project: 'common',
    tags: ['日报'], uses: 9, lastUsed: '3天前',
    content: '今天完成了主链路优化、异常链路收口和验证脚本补齐。',
    shortcut: '7',
  },
  {
    id: 'e8', title: 'PR Review 反馈', kind: 'chat', project: 'common',
    tags: ['审计', '协作'], uses: 14, lastUsed: '6小时前',
    content: '在 diff 上按文件粒度给出可操作反馈,优先级 high/mid/low。',
    shortcut: '8',
  },
  {
    id: 'e9', title: '周报结构', kind: 'note', project: 'common',
    tags: ['日报', '周报'], uses: 7, lastUsed: '昨天',
    content: '本周完成 · 本周未完成 · 下周计划 · 风险 · 需协同事项',
    shortcut: '9',
  },
  {
    id: 'e10', title: '需求澄清清单', kind: 'prompt', project: 'fangzhou',
    tags: ['需求', 'AI'], uses: 3, lastUsed: '4天前',
    content: '请按"目标用户 / 使用场景 / 成功指标 / 边界"四个维度反问,并标注信息缺失点。',
  },
  {
    id: 'e11', title: '埋点规范', kind: 'note', project: 'fangzhou',
    tags: ['埋点'], uses: 5, lastUsed: '1周前',
    content: '事件名 snake_case · 属性不超过 6 个 · 必填 user_id / session_id · 版本号随包。',
  },
];

// Kind metadata — neutral monochrome, differentiated only by glyph
const KIND_META = {
  reply:  { label: '回复',   icon: 'reply' },
  chat:   { label: '对话',   icon: 'chat' },
  note:   { label: '说明',   icon: 'doc' },
  prompt: { label: 'Prompt', icon: 'sparkles' },
};

Object.assign(window, { PROJECTS, ENTRIES, KIND_META });
