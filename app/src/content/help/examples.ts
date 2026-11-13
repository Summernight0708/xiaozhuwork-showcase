import { findHelpArticle } from "./articles";

export interface HelpExample {
  id: string;
  articleId: string;
  title: string;
  scenario: string;
  steps: readonly string[];
  warning: string;
}

export const HELP_EXAMPLES: readonly HelpExample[] = [
  {
    id: "dependencies",
    articleId: "dependencies",
    title: "上下游任务示例",
    scenario:
      "任务 A：整理资料 → 任务 B：制作 PPT。任务 B 的启动依赖资料整理完成。",
    steps: [
      "查看任务 B 的依赖列表。",
      "等待任务 A 满足约定的完成条件。",
      "解除阻塞后再确认参考版本。",
    ],
    warning: "解除阻塞不代表资料自动获得验收。",
  },
  {
    id: "submission",
    articleId: "submission",
    title: "一次成果提交示例",
    scenario: "成员完成演示文稿，需要同时提交说明文字和 PPTX 附件。",
    steps: [
      "确认任务所需文件类型。",
      "填写本轮成果说明并选择附件。",
      "预览无误后，在真实任务中由用户自行提交。",
    ],
    warning: "这是只读教学，不会替你上传或提交。",
  },
  {
    id: "review",
    articleId: "review",
    title: "验收与退回示例",
    scenario: "提交的附件缺少最后一页，审核人提出修改建议。",
    steps: [
      "由符合权限的审核人查看提交轮次。",
      "填写具体退回原因。",
      "负责人完善附件，再次发起提交。",
    ],
    warning: "独立验收规则可能禁止提交者审核自己的成果。",
  },
  {
    id: "file-rollback",
    articleId: "file-rollback",
    title: "版本回滚示例",
    scenario: "误上传了错误版本，需要恢复到先前确认过的文件版本。",
    steps: [
      "比较两个文件版本，确认回退目标。",
      "核对回滚影响的文件清单。",
      "在实际页面中由有权限的人完成二次确认。",
    ],
    warning: "回滚可能影响其他人的引用。此示例不执行实际操作。",
  },
  {
    id: "advanced-permissions",
    articleId: "advanced-permissions",
    title: "高级权限委派示例",
    scenario: "组长希望其他成员协助处理邀请或入组审核。",
    steps: [
      "先确认高级权限能力已发布并有效。",
      "组长选择规定的权限模板和目标成员。",
      "核对授权范围，成员仅行使被授予的操作。",
    ],
    warning: "阅读示例不会获得或授予任何权限。",
  },
  {
    id: "contribution",
    articleId: "contribution",
    title: "贡献统计示例",
    scenario: "两位成员完成不同难度的任务，贡献依据不只是文件数量。",
    steps: [
      "核对任务难度和正式完成状态。",
      "查看已验收任务是否计入报告。",
      "在报告阶段确认自己的贡献记录。",
    ],
    warning: "具体贡献分以当时项目统计规则为准。",
  },
  {
    id: "calendar",
    articleId: "calendar",
    title: "日历订阅示例",
    scenario: "把课程项目的重要截止日期同步到自己的日历客户端。",
    steps: [
      "在项目日历订阅页面查看是否有能力和权限。",
      "由有权用户生成订阅链接。",
      "粘贴到支持订阅的日历应用。",
    ],
    warning: "私密订阅链接不可公开分享。",
  },
];

export function findHelpExample(id: string): HelpExample | undefined {
  const example = HELP_EXAMPLES.find((item) => item.id === id);
  return example && findHelpArticle(example.articleId) ? example : undefined;
}
