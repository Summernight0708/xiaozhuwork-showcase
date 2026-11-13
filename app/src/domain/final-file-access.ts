export function isFinalDesignationEligibleFile(
  purpose: "deliverable" | "reference" | null | undefined,
) {
  return purpose !== "reference";
}

export function canChangeFinalFileDesignation(options: {
  canMarkFinalFiles: boolean;
  projectLifecycle: string | null | undefined;
  taskStatus: string | null | undefined;
  contributionReportState: "draft" | "formal" | null | undefined;
}) {
  return (
    options.canMarkFinalFiles &&
    options.projectLifecycle === "active" &&
    options.taskStatus === "completed" &&
    options.contributionReportState !== "formal"
  );
}
