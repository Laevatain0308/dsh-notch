import { Board } from "./board.js";
import { attachHttp } from "./http.js";
import { startNotch } from "./notch-process.js";
import { loadOrCreateToken, writeRuntime } from "./store.js";
const name = "dsh-notch";
const inject = ["sessions", "webServer", "approval", "userQuestions", "agents"];
function apply(ctx, config = {}) {
  console.log("[my-plugins/dsh-notch] loaded");
  const board = new Board(ctx);
  const token = loadOrCreateToken();
  const origin = `http://${ctx.webServer.host}:${String(ctx.webServer.port)}`;
  writeRuntime({
    origin,
    token,
    pid: process.pid,
    writtenAt: Date.now()
  });
  const logger = {
    info: (message) => {
      ctx.logger.info("%s", message);
    },
    warn: (message) => {
      ctx.logger.warn("%s", message);
    }
  };
  ctx.effect(() => startNotch(logger, config), "dsh-notch: notch process");
  ctx.effect(() => attachHttp(ctx, board, token, origin), "dsh-notch: http");
  const notify = debounce(() => board.notify(), 80);
  ctx.effect(() => notify.dispose, "dsh-notch: notification timer");
  ctx.effect(() => ctx.on("session/created", notify), "dsh-notch: created");
  ctx.effect(() => ctx.on("session/disposed", notify), "dsh-notch: disposed");
  ctx.effect(() => ctx.on("session/event", (session, event) => {
    const type = String(event.type);
    if (type === "turn/start" || type === "turn/end" || type === "session/title") {
      notify();
    }
    if (type === "turn/start" || type === "user/message" && event.data?.source === "user") {
      board.markSeen(session.id);
    }
  }), "dsh-notch: events");
  ctx.effect(() => ctx.on("agent/status", notify), "dsh-notch: agent-status");
  ctx.on("user-questions/request", (request, next) => board.holdAsk(request, next), { prepend: true });
}
function debounce(fn, ms) {
  let timer;
  const notify = () => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = void 0;
      fn();
    }, ms);
  };
  return Object.assign(notify, { dispose: () => {
    if (timer) clearTimeout(timer);
    timer = void 0;
  } });
}
export {
  apply,
  inject,
  name
};

//# sourceMappingURL=dsh-notch.js.map
