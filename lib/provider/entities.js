const runKey = (sessionId) => `${sessionId}:run`;
const resultKey = (sessionId) => `${sessionId}:result`;
const askKey = (sessionId) => `${sessionId}:ask`;
function approvalInteraction(row, timeoutMs) {
  const approval = row.approval;
  if (approval === void 0) return void 0;
  return {
    id: `approval:${approval.id}`,
    timeoutMs,
    questions: [
      {
        id: approval.id,
        header: "\u5DE5\u5177\u8BB8\u53EF",
        question: `\u5141\u8BB8\u8FD0\u884C ${approval.toolName}\uFF1F`,
        ...approval.reason === void 0 ? {} : { detail: approval.reason },
        options: [{ label: "\u5141\u8BB8" }, { label: "\u62D2\u7EDD" }]
      }
    ]
  };
}
function askInteraction(row, timeoutMs) {
  const ask = row.ask;
  if (ask === void 0) return void 0;
  return {
    id: `ask:${ask.id}`,
    timeoutMs,
    questions: ask.questions.map((question) => ({
      id: question.id,
      question: question.question,
      ...question.header === void 0 ? {} : { header: question.header },
      ...question.detail === void 0 ? {} : { detail: question.detail },
      options: question.options ?? [],
      ...question.multiSelect === void 0 ? {} : { multiSelect: question.multiSelect }
    }))
  };
}
function decision(row, timeoutMs) {
  return approvalInteraction(row, timeoutMs) ?? askInteraction(row, timeoutMs);
}
function isDeciding(row) {
  return row.approval !== void 0 || row.ask !== void 0;
}
function entitiesForRow(row, context, timeoutMs) {
  const title = row.title;
  const deciding = decision(row, timeoutMs);
  if (deciding !== void 0) {
    const waiting = context.queuedDecisions;
    return [
      {
        key: askKey(row.id),
        class: "awaiting",
        state: "pending",
        lifetime: "held",
        title,
        ...waiting === 0 ? {} : { body: `\u8FD8\u6709 ${String(waiting)} \u4E2A\u4F1A\u8BDD\u5728\u7B49\u5F85\u5904\u7406` },
        interaction: deciding
      }
    ];
  }
  const entities = [];
  if (row.busy) {
    entities.push({
      key: runKey(row.id),
      class: "activity",
      state: "running",
      lifetime: "held",
      title,
      actions: context.actions
    });
  }
  if (row.unread && row.lastTurn !== void 0) {
    entities.push({
      key: resultKey(row.id),
      class: "result",
      state: row.lastTurn.failed ? "failed" : "succeeded",
      lifetime: "held",
      title,
      unread: true,
      actions: context.actions
    });
  }
  return entities;
}
function entitiesFor(rows, context, timeoutMs) {
  const entities = [];
  for (const row of rows) entities.push(...entitiesForRow(row, context, timeoutMs));
  return entities.sort((left, right) => left.key < right.key ? -1 : 1);
}
function same(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}
function delta(previous, next) {
  const upsert = [];
  const wanted = /* @__PURE__ */ new Set();
  for (const entity of next) {
    wanted.add(entity.key);
    const before = previous.get(entity.key);
    if (before === void 0 || !same(before, entity)) upsert.push(entity);
  }
  const remove = [...previous.keys()].filter((key) => !wanted.has(key));
  return { upsert, remove };
}
function remember(previous, change) {
  for (const entity of change.upsert) previous.set(entity.key, entity);
  for (const key of change.remove) previous.delete(key);
}
function answersFrom(interaction, answers) {
  if (interaction.id.startsWith("approval:")) {
    const first = interaction.questions[0];
    const selected = first === void 0 ? [] : answers[first.id] ?? [];
    return { kind: "approval", outcome: selected.includes("\u5141\u8BB8") ? "allowed-once" : "rejected" };
  }
  return {
    kind: "ask",
    items: interaction.questions.map((question) => ({
      id: question.id,
      selected: answers[question.id] ?? []
    }))
  };
}
export {
  answersFrom,
  askKey,
  delta,
  entitiesFor,
  entitiesForRow,
  isDeciding,
  remember,
  resultKey,
  runKey
};

//# sourceMappingURL=entities.js.map
