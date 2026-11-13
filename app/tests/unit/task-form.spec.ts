import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import TaskForm from "@/components/task/TaskForm.vue";
import TaskResponsibilityFields from "@/components/task/TaskResponsibilityFields.vue";
import {
  emptyTaskForm,
  taskChangeFacts,
  validateTaskForm,
  type TaskFormCapabilities,
  type TaskFormModel,
} from "@/domain/task-form";
import type { MembershipRow, TaskRow } from "@/types/ui";

const fullCapabilities: TaskFormCapabilities = {
  startAt: true,
  collaborators: true,
  requiredFileType: true,
};

const members = [
  {
    id: "m-primary",
    user_id: "primary-1",
    display_name_snapshot: "张三",
    role: "member",
    is_observer: false,
  },
  {
    id: "m-collab",
    user_id: "collab-1",
    display_name_snapshot: "李四",
    role: "member",
    is_observer: false,
  },
  {
    id: "m-observer",
    user_id: "observer-1",
    display_name_snapshot: "观察者",
    role: "observer",
    is_observer: true,
  },
] as MembershipRow[];

const upstream = [
  {
    id: "task-a",
    project_id: "project-1",
    title: "数据清洗",
    deadline_at: "2026-10-08T00:00:00Z",
    weight: 2,
    assignment_state: "assigned",
    status: "in_progress",
  },
] as TaskRow[];

describe("TaskForm", () => {
  it("defaults to manual review and can turn it off without extra screens", async () => {
    const model = { ...emptyTaskForm(), deadlineAt: "2026-10-12T12:00" };
    expect(model.requiresReview).toBe(true);
    const wrapper = mount(TaskForm, {
      props: {
        modelValue: model,
        members,
        tasks: upstream,
        capabilities: fullCapabilities,
      },
    });
    const toggle = wrapper.get('[data-testid="requires-review-toggle"]');
    expect(toggle.attributes("type")).toBe("checkbox");
    expect((toggle.element as HTMLInputElement).checked).toBe(true);
    await toggle.setValue(false);
    const changes = wrapper.emitted("update:modelValue") ?? [];
    expect(changes[changes.length - 1]?.[0]).toMatchObject({
      requiresReview: false,
    });
  });

  it("omits star inputs in facts-only mode without removing responsibility fields", () => {
    const wrapper = mount(TaskForm, {
      props: {
        modelValue: emptyTaskForm(),
        members,
        tasks: upstream,
        capabilities: fullCapabilities,
        contributionMode: "facts_only",
      },
    });
    expect(wrapper.find('[name="task-difficulty"]').exists()).toBe(false);
    expect(wrapper.findComponent(TaskResponsibilityFields).exists()).toBe(true);
  });

  it("uses the approved three-section layout and never exposes runtime Help/Rework/Binding controls", () => {
    const model = {
      ...emptyTaskForm(),
      deadlineAt: "2026-10-10T12:00",
    };
    const wrapper = mount(TaskForm, {
      props: {
        modelValue: model,
        members,
        tasks: upstream,
        capabilities: fullCapabilities,
      },
    });

    expect(wrapper.text()).toContain("基本信息");
    expect(wrapper.text()).toContain("责任与时间");
    expect(wrapper.text()).toContain("工作流与提交");
    expect(wrapper.text()).not.toContain("启用 Help");
    expect(wrapper.text()).not.toContain("Rework");
    expect(wrapper.text()).not.toContain("Binding 类型");
  });

  it("explains open claim instead of leaving an unexplained empty assignee", () => {
    const wrapper = mount(TaskForm, {
      props: {
        modelValue: {
          ...emptyTaskForm(),
          deadlineAt: "2026-10-10T12:00",
          assignmentMode: "claimable",
        },
        members,
        tasks: upstream,
        capabilities: fullCapabilities,
      },
    });

    expect(wrapper.text()).toContain("暂不指定，开放认领");
    expect(wrapper.text()).toContain("该任务将进入「待认领任务」区域");
    expect(wrapper.text()).not.toContain("协作者");
  });

  it("shows collaborator invitation semantics only when a Primary is assigned and excludes observers", () => {
    const wrapper = mount(TaskForm, {
      props: {
        modelValue: {
          ...emptyTaskForm(),
          deadlineAt: "2026-10-10T12:00",
          assignmentMode: "direct",
          assigneeId: "primary-1",
        },
        members,
        tasks: upstream,
        capabilities: fullCapabilities,
      },
    });

    expect(wrapper.text()).toContain("协作者");
    expect(wrapper.text()).toContain("接受后才成为协作者");
    expect(wrapper.text()).toContain("李四");
    expect(wrapper.text()).not.toContain("观察者");
  });

  it("preserves the selected Primary when responsibility fields emit sequential updates", async () => {
    const wrapper = mount(TaskForm, {
      props: {
        modelValue: {
          ...emptyTaskForm(),
          title: "任务",
          deadlineAt: "2026-10-10T12:00",
        },
        members,
        tasks: upstream,
        capabilities: fullCapabilities,
      },
    });

    const responsibility = wrapper.getComponent(TaskResponsibilityFields);
    responsibility.vm.$emit("updateAssignmentMode", "direct");
    responsibility.vm.$emit("updateAssigneeId", "primary-1");
    responsibility.vm.$emit("updateCollaboratorIds", []);

    const updates = wrapper.emitted("update:modelValue") ?? [];
    expect(updates[updates.length - 1]?.[0]).toMatchObject({
      assignmentMode: "direct",
      assigneeId: "primary-1",
      collaboratorIds: [],
    });
  });

  it("renders friendly required-file labels and explains that text plus other files remain allowed", () => {
    const wrapper = mount(TaskForm, {
      props: {
        modelValue: {
          ...emptyTaskForm(),
          deadlineAt: "2026-10-10T12:00",
          requiredFileTypes: ["xlsx"],
        },
        members,
        tasks: upstream,
        capabilities: fullCapabilities,
      },
    });

    expect(wrapper.text()).toContain("XLSX");
    expect(wrapper.text()).toContain("也可以同时提交其他附件和文字说明");
    expect(wrapper.text()).not.toContain("application/");
  });

  it("supports unrestricted, single and multiple required file types", async () => {
    const wrapper = mount(TaskForm, {
      props: {
        modelValue: {
          ...emptyTaskForm(),
          deadlineAt: "2026-10-10T12:00",
        },
        members,
        tasks: upstream,
        capabilities: fullCapabilities,
      },
    });

    expect(wrapper.text()).toContain("不限制文件类型");
    const pdf = wrapper.get('input[data-testid="required-file-type-pdf"]');
    const docx = wrapper.get('input[data-testid="required-file-type-docx"]');
    expect((pdf.element as HTMLInputElement).checked).toBe(false);
    expect((docx.element as HTMLInputElement).checked).toBe(false);

    const lastUpdate = () => {
      const updates = wrapper.emitted("update:modelValue") ?? [];
      return updates[updates.length - 1]?.[0];
    };
    const syncModel = async () => {
      const latest = lastUpdate() as TaskFormModel | undefined;
      if (latest) await wrapper.setProps({ modelValue: latest });
    };

    await pdf.setValue(true);
    expect(lastUpdate()).toMatchObject({ requiredFileTypes: ["pdf"] });
    await syncModel();
    expect(wrapper.text()).toContain("至少包含其中一种即可");

    await docx.setValue(true);
    expect(lastUpdate()).toMatchObject({
      requiredFileTypes: ["pdf", "docx"],
    });
    await syncModel();

    await pdf.setValue(false);
    expect(lastUpdate()).toMatchObject({ requiredFileTypes: ["docx"] });
    await syncModel();
    await docx.setValue(false);
    expect(lastUpdate()).toMatchObject({ requiredFileTypes: [] });
    await syncModel();
    expect(wrapper.text()).toContain("不限制文件类型");
  });

  it("hydrates multiple file-type selections and exposes each checkbox label", () => {
    const wrapper = mount(TaskForm, {
      props: {
        modelValue: {
          ...emptyTaskForm(),
          deadlineAt: "2026-10-10T12:00",
          requiredFileTypes: ["docx", "pdf"],
        },
        members,
        tasks: upstream,
        capabilities: fullCapabilities,
      },
    });

    for (const type of ["pdf", "docx"]) {
      const input = wrapper.get(
        `input[data-testid="required-file-type-${type}"]`,
      );
      expect((input.element as HTMLInputElement).checked).toBe(true);
      expect(input.element.closest("label")?.textContent).toContain(
        type.toUpperCase(),
      );
    }
    expect(wrapper.text()).toContain("至少包含其中一种即可");
  });
});

describe("task form validation and change facts", () => {
  it("requires start < deadline and prevents Primary/collaborator duplication", () => {
    const model = {
      ...emptyTaskForm(),
      title: "任务",
      assignmentMode: "direct" as const,
      assigneeId: "primary-1",
      collaboratorIds: ["primary-1"],
      startAt: "2026-10-11T12:00",
      deadlineAt: "2026-10-10T12:00",
    };
    expect(validateTaskForm(model, fullCapabilities)).toBe(
      "开始时间必须早于截止时间",
    );

    model.startAt = "2026-10-09T12:00";
    expect(validateTaskForm(model, fullCapabilities)).toBe(
      "主负责人不能同时作为协作者",
    );
  });

  it("caps the task deadline at the project DDL and explains the boundary", () => {
    const model = {
      ...emptyTaskForm(),
      title: "任务",
      deadlineAt: "2026-10-11T12:00",
    };
    const projectDeadlineAt = "2026-10-10T12:00";

    expect(
      validateTaskForm(model, fullCapabilities, { projectDeadlineAt }),
    ).toBe("任务截止时间不能晚于项目 DDL");

    const wrapper = mount(TaskForm, {
      props: {
        modelValue: model,
        members,
        tasks: upstream,
        capabilities: fullCapabilities,
        projectDeadlineAt,
      },
    });
    const deadline = wrapper.get('input[type="datetime-local"][required]');
    expect(deadline.attributes("max")).toBe(projectDeadlineAt);
    expect(wrapper.text()).toContain("项目 DDL");
  });

  it("builds an edit confirmation summary for important task facts", () => {
    const before = {
      ...emptyTaskForm(),
      title: "任务",
      deadlineAt: "2026-10-10T12:00",
      assigneeId: "primary-1",
      assignmentMode: "direct" as const,
      difficulty: 3,
    };
    const after = {
      ...before,
      deadlineAt: "2026-10-12T12:00",
      assigneeId: "primary-2",
      difficulty: 4,
      requiredFileTypes: ["pdf" as const],
    };

    expect(taskChangeFacts(before, after).map((fact) => fact.label)).toEqual([
      "DDL",
      "主负责人",
      "任务难度",
      "提交要求",
    ]);
  });
});
