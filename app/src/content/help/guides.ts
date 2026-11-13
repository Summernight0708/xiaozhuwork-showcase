import { HELP_ARTICLES, type HelpArticle } from "./articles";

export interface HelpGuide {
  id: string;
  title: string;
  summary: string;
  articleIds: readonly string[];
  articles: readonly HelpArticle[];
  questions: readonly string[];
  keywords: readonly string[];
}

// Eight end-to-end guides replace the 27 independent cards. Old article IDs stay valid.
const definitions: readonly Omit<HelpGuide, "articles">[] = [
  {
    id: "guide-projects",
    title: "项目创建与成员协作",
    summary: "从建项目、邀请成员到角色管理和项目归档。",
    articleIds: [
      "start-project",
      "join-project",
      "invite-members",
      "roles",
      "project-settings",
    ],
    questions: [
      "邀请链接过期怎么办？需要组长重新生成有效链接。",
      "项目归档后还能编辑吗？归档项目只读，恢复受权限与项目额度限制。",
    ],
    keywords: ["创建", "邀请", "项目", "入组", "归档"],
  },
  {
    id: "guide-task-team",
    title: "任务分工与协作",
    summary: "创建与认领任务，理解主负责人、协作者与协作请求。",
    articleIds: ["task-create", "task-claim", "task-help"],
    questions: [
      "主负责人承担交付责任，协作者须本人接受邀请后参与。",
      "任务责任可以移交，但需要接收人确认，历史记录不会被抹去。",
    ],
    keywords: ["主负责人", "协作者", "认领", "移交", "求助"],
  },
  {
    id: "guide-dependencies",
    title: "任务依赖与成果流转",
    summary: "建立无环依赖，查看上游证据和返工流程。",
    articleIds: ["dependencies", "artifact-binding"],
    questions: [
      "上游未完成时，下游仍可以提交和验收通过；等待上游只是首次提交前的进度提示。",
      "绑定成果版本后应检查引用版本，不要把重新上传等同于自动更新依赖。",
    ],
    keywords: ["上游", "下游", "依赖", "绑定", "返工"],
  },
  {
    id: "guide-submission",
    title: "成果提交与验收",
    summary: "提交文字与附件，了解独立验收、打回和二次提交。",
    articleIds: ["submission", "review", "review-authority"],
    questions: [
      "创建任务时可以关闭人工验收：有效提交即完成，提交事实仍会被记录。",
      "负责人不能自行验收自己的成果，审核人依权限和避嫌规则确定。",
    ],
    keywords: ["成果", "提交", "审核", "待验收", "无需验收"],
  },
  {
    id: "guide-files",
    title: "文件管理与存储",
    summary: "上传、预览、版本比较、恢复点与 Free/Pro 配额。",
    articleIds: [
      "files",
      "file-history",
      "file-compare",
      "file-rollback",
      "storage-quota",
    ],
    questions: [
      "文件须关联任务，上传完成仍要通过服务端权限与类型校验。",
      "文件恢复点恢复文件指针，不会回滚整个项目或验收状态。",
    ],
    keywords: ["文件", "上传", "历史", "回滚", "配额"],
  },
  {
    id: "guide-contribution",
    title: "贡献、统计与报告",
    summary: "理解贡献依据、申诉和项目报告导出。",
    articleIds: ["contribution", "enhanced-report", "project-analytics"],
    questions: [
      "任务难度和实际交付会影响贡献依据，贡献不等于教师评分。",
      "基础报告无需 Pro；增强报表和统计需同时满足权益及业务权限。",
    ],
    keywords: ["贡献", "报告", "统计", "申诉"],
  },
  {
    id: "guide-personal",
    title: "通知与个人使用",
    summary: "管理通知、个人资料、外观与 Android 客户端。",
    articleIds: ["notifications", "account-and-android"],
    questions: [
      "删除通知仅从个人收件箱隐藏，不会删除任务事实与审计记录。",
      "看到安装风险提示时，仅允许本次可信安装源，勿关闭系统整体防护。",
    ],
    keywords: ["通知", "删除通知", "外观", "Android", "账号"],
  },
  {
    id: "guide-pro",
    title: "Pro 与高级功能",
    summary: "理解 Free/Pro、权限委派、跨项目与日历订阅。",
    articleIds: [
      "advanced-permissions",
      "cross-project",
      "calendar",
      "upgrade-pro",
    ],
    questions: [
      "所有用户都可查看 Pro 教程，但阅读不会增加账号权益。",
      "高级功能仍由服务端检查项目成员角色、有效权益与发布开关。",
    ],
    keywords: ["Free", "Pro", "高级权限", "跨项目", "日历"],
  },
];

export const HELP_GUIDES: readonly HelpGuide[] = definitions.map((item) => ({
  ...item,
  articles: item.articleIds.map((id) => {
    const article = HELP_ARTICLES.find((entry) => entry.id === id);
    if (!article) throw new Error("缺少帮助章节：" + id);
    return article;
  }),
}));

export function findHelpGuide(id: string): HelpGuide | undefined {
  return HELP_GUIDES.find(
    (guide) => guide.id === id || guide.articleIds.includes(id),
  );
}

export function searchHelpGuides(query: string): HelpGuide[] {
  const term = query.trim().toLocaleLowerCase();
  if (!term) return [...HELP_GUIDES];
  return HELP_GUIDES.filter((guide) =>
    [
      guide.title,
      guide.summary,
      ...guide.keywords,
      ...guide.questions,
      ...guide.articles.flatMap((article) => [
        article.title,
        article.goal,
        article.note,
        ...article.steps,
        ...article.keywords,
      ]),
    ].some((word) => word.toLocaleLowerCase().includes(term)),
  );
}
