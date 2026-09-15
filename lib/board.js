import { randomUUID } from "node:crypto";
import { foldSession, isChildSession } from "./session-state.js";
import { loadSeen, saveSeen } from "./store.js";
class Board {
  constructor(ctx) {
    this.ctx = ctx;
  }
  ctx;
  pending = /* @__PURE__ */ new Map();
  seen = loadSeen();
  running = /* @__PURE__ */ new Set();
  pendingUnread = /* @__PURE__ */ new Set();
  listeners = /* @__PURE__ */ new Set();
  focus = null;
  onChange(fn) {
    this.listeners.add(fn);
    return () => {
      this.listeners.delete(fn);
    };
  }
  notify() {
    this.bump();
  }
  bump() {
    for (const fn of this.listeners) {
      try {
        fn();
      } catch (error) {
        this.ctx.logger.warn("dsh-notch: subscriber failed: %s", String(error));
      }
    }
  }
  snapshot(origin) {
    const rows = [];
    for (const session of this.ctx.sessions.list()) {
      const row = this.rowFor(session);
      if (row) rows.push(row);
    }
    rows.sort((a, b) => Number(Boolean(b.approval || b.ask)) - Number(Boolean(a.approval || a.ask)) || Number(b.busy) - Number(a.busy) || Number(b.unread) - Number(a.unread) || (b.lastTurn?.at ?? 0) - (a.lastTurn?.at ?? 0));
    this.running = new Set(
      this.ctx.sessions.list().filter((session) => this.isBusy(session)).map((session) => session.id)
    );
    return { ok: true, generatedAt: Date.now(), origin, rows };
  }
  markSeen(sessionId) {
    this.pendingUnread.delete(sessionId);
    this.seen[sessionId] = Date.now();
    saveSeen(this.seen);
    this.bump();
  }
  markAllSeen() {
    this.pendingUnread.clear();
    const now = Date.now();
    for (const session of this.ctx.sessions.list()) {
      this.seen[session.id] = now;
    }
    saveSeen(this.seen);
    this.bump();
  }
  /**
   * Record a "show this session in a DSH UI" wish from the native helper.
   * Returns false for unknown sessions. The wish expires after 60s; every
   * open DSH page consumes it idempotently, so no per-client cursor is kept.
   */
  requestFocus(sessionId) {
    const known = this.ctx.sessions.list().some((session) => session.id === sessionId);
    if (!known) return false;
    this.focus = { sessionId, at: Date.now() };
    this.bump();
    return true;
  }
  peekFocus() {
    if (this.focus === null) return null;
    if (Date.now() - this.focus.at > 6e4) {
      this.focus = null;
      return null;
    }
    return this.focus;
  }
  decideApproval(id, outcome) {
    const held = this.pending.get(id);
    if (!held || held.kind !== "approval") return false;
    this.pending.delete(id);
    this.seen[held.sessionId] = Date.now();
    saveSeen(this.seen);
    held.resolve(outcome);
    this.bump();
    return true;
  }
  answerAsk(id, answers) {
    const held = this.pending.get(id);
    if (!held || held.kind !== "ask") return false;
    this.pending.delete(id);
    this.seen[held.sessionId] = Date.now();
    saveSeen(this.seen);
    held.resolve({ answers });
    this.bump();
    return true;
  }
  holdApproval(request, next) {
    const sessionId = String(request.agent.id);
    const id = randomUUID();
    const fromNotch = new Promise((resolve) => {
      const held = {
        kind: "approval",
        id,
        sessionId,
        toolName: request.toolName,
        resolve
      };
      if (request.reason) held.reason = request.reason;
      this.pending.set(id, held);
      this.bump();
      request.signal?.addEventListener("abort", () => {
        if (!this.pending.delete(id)) return;
        this.bump();
      }, { once: true });
    });
    return Promise.race([fromNotch, next()]).finally(() => {
      if (this.pending.delete(id)) this.bump();
    });
  }
  holdAsk(request, next) {
    const sessionId = request.agent ? String(request.agent.id) : "";
    if (!sessionId) return next();
    const originalSignal = request.signal;
    const downstream = new AbortController();
    request.signal = originalSignal ? AbortSignal.any([originalSignal, downstream.signal]) : downstream.signal;
    const id = randomUUID();
    const questions = request.questions.map((item) => ({
      id: item.id,
      question: item.question,
      ...item.detail === void 0 ? {} : { detail: item.detail },
      ...item.header === void 0 ? {} : { header: item.header },
      ...item.options === void 0 ? {} : { options: item.options },
      ...item.multiSelect === void 0 ? {} : { multiSelect: item.multiSelect },
      ...item.intent === void 0 ? {} : { intent: item.intent }
    }));
    const fromNotch = new Promise((resolve) => {
      this.pending.set(id, { kind: "ask", id, sessionId, questions, resolve });
      this.bump();
      request.signal?.addEventListener("abort", () => {
        if (!this.pending.delete(id)) return;
        this.bump();
      }, { once: true });
    });
    return Promise.race([fromNotch, Promise.resolve().then(next)]).finally(() => {
      downstream.abort(new Error("Question settled through another answerer"));
      if (originalSignal === void 0) delete request.signal;
      else request.signal = originalSignal;
      if (this.pending.delete(id)) this.bump();
    });
  }
  isBusy(session) {
    return this.ctx.agents.get(session.id)?.status === "running";
  }
  rowFor(session) {
    const folded = foldSession(session);
    const child = isChildSession(session);
    const lastSeen = this.seen[session.id];
    const busy = this.isBusy(session);
    if (busy) {
      this.pendingUnread.delete(session.id);
    } else if (this.running.has(session.id) && folded.lastTurn && !folded.lastTurn.failed) {
      this.pendingUnread.add(session.id);
    }
    const dismissed = lastSeen !== void 0 && (folded.lastTurn === void 0 || lastSeen >= folded.lastTurn.at);
    const unread = dismissed ? false : this.pendingUnread.has(session.id);
    const approval = this.heldApproval(session.id);
    const ask = this.heldAsk(session.id);
    if (!busy && !unread && !approval && !ask) return void 0;
    if (child && !approval && !ask && !busy) return void 0;
    const title = this.titleOf(session);
    const row = {
      id: session.id,
      title,
      child,
      busy,
      unread
    };
    if (folded.lastTurn && !busy) row.lastTurn = folded.lastTurn;
    if (approval) row.approval = approval;
    if (ask) row.ask = ask;
    return row;
  }
  heldApproval(sessionId) {
    for (const held of this.pending.values()) {
      if (held.kind === "approval" && held.sessionId === sessionId) {
        return {
          id: held.id,
          toolName: held.toolName,
          ...held.reason === void 0 ? {} : { reason: held.reason }
        };
      }
    }
    return void 0;
  }
  heldAsk(sessionId) {
    for (const held of this.pending.values()) {
      if (held.kind === "ask" && held.sessionId === sessionId) {
        return { id: held.id, questions: held.questions };
      }
    }
    return void 0;
  }
  titleOf(session) {
    const service = this.ctx.get("sessionTitle");
    const title = service?.get(session)?.title?.trim();
    if (title) return title;
    return session.id.slice(0, 8);
  }
}
export {
  Board
};

//# sourceMappingURL=board.js.map
