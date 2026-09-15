const FAILED = /* @__PURE__ */ new Set(["error", "blocked", "max-tokens"]);
function foldSession(session) {
  let busy = false;
  let lastTurn;
  for (const event of session.snapshotEvents()) {
    if (event.type === "turn/start") {
      busy = true;
      lastTurn = void 0;
      continue;
    }
    if (event.type === "turn/end") {
      busy = false;
      const kind = event.data.reason.kind;
      lastTurn = { at: event.time, kind, failed: FAILED.has(kind) };
    }
  }
  return { busy, lastTurn };
}
function isChildSession(session) {
  return session.header.parentSession !== void 0 || session.header.origin === "subagent";
}
export {
  foldSession,
  isChildSession
};

//# sourceMappingURL=session-state.js.map
