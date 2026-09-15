import { randomUUID } from "node:crypto";
const PREFIX = "/dsh-notch";
function isLoopback(req) {
  const ip = req.socket.remoteAddress ?? "";
  return ip === "127.0.0.1" || ip === "::1" || ip === ":ffff:127.0.0.1" || ip === "::ffff:127.0.0.1";
}
function authorized(req, token) {
  const header = req.headers.authorization;
  if (header === `Bearer ${token}`) return true;
  try {
    const url = new URL(req.url ?? "/", "http://127.0.0.1");
    return url.searchParams.get("token") === token;
  } catch {
    return false;
  }
}
function browserTrusted(req) {
  if (!isLoopback(req)) return false;
  if (req.headers["sec-fetch-site"] === "cross-site") return false;
  const host = req.headers.host;
  if (host === void 0) return false;
  const origin = req.headers.origin;
  if (origin === void 0) return true;
  try {
    return new URL(origin).host === new URL(`http://${host}`).host;
  } catch {
    return false;
  }
}
function send(res, status, body) {
  const json = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store"
  });
  res.end(json);
}
function readBody(req, limit = 64 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(new Error("body too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}
function attachHttp(ctx, board, token, origin) {
  const streams = /* @__PURE__ */ new Map();
  const push = () => {
    const payload = `data: ${JSON.stringify(board.snapshot(origin))}

`;
    for (const [id, res] of streams) {
      try {
        res.write(payload);
      } catch {
        streams.delete(id);
      }
    }
  };
  const stopListen = board.onChange(push);
  const handler = async (req, res) => {
    const url = new URL(req.url ?? "/", "http://127.0.0.1");
    const path = url.pathname;
    const method = req.method ?? "GET";
    if (method === "GET" && path === `${PREFIX}/pending-focus`) {
      if (!browserTrusted(req)) {
        send(res, 403, { ok: false, error: "forbidden" });
        return;
      }
      send(res, 200, { ok: true, focus: board.peekFocus() });
      return;
    }
    if (!isLoopback(req) || !authorized(req, token)) {
      send(res, 403, { ok: false, error: "forbidden" });
      return;
    }
    if (method === "GET" && path === `${PREFIX}/status`) {
      send(res, 200, board.snapshot(origin));
      return;
    }
    if (method === "GET" && path === `${PREFIX}/events`) {
      const id = randomUUID();
      res.writeHead(200, {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        connection: "keep-alive"
      });
      streams.set(id, res);
      res.write(`data: ${JSON.stringify(board.snapshot(origin))}

`);
      req.on("close", () => {
        streams.delete(id);
      });
      return;
    }
    if (method === "POST" && path === `${PREFIX}/seen`) {
      const body = JSON.parse(await readBody(req));
      if (body.all) {
        board.markAllSeen();
        send(res, 200, { ok: true });
        return;
      }
      if (!body.sessionId) {
        send(res, 400, { ok: false, error: "sessionId required" });
        return;
      }
      board.markSeen(body.sessionId);
      send(res, 200, { ok: true });
      return;
    }
    if (method === "POST" && path === `${PREFIX}/approve`) {
      const body = JSON.parse(await readBody(req));
      if (!body.id || body.outcome !== "allowed-once" && body.outcome !== "rejected") {
        send(res, 400, { ok: false, error: "id and outcome required" });
        return;
      }
      if (!board.decideApproval(body.id, body.outcome)) {
        send(res, 404, { ok: false, error: "not pending" });
        return;
      }
      send(res, 200, { ok: true });
      return;
    }
    if (method === "POST" && path === `${PREFIX}/answer`) {
      const body = JSON.parse(await readBody(req));
      if (!body.id || !Array.isArray(body.answers)) {
        send(res, 400, { ok: false, error: "id and answers required" });
        return;
      }
      if (!board.answerAsk(body.id, body.answers)) {
        send(res, 404, { ok: false, error: "not pending" });
        return;
      }
      send(res, 200, { ok: true });
      return;
    }
    if (method === "POST" && path === `${PREFIX}/focus`) {
      const body = JSON.parse(await readBody(req));
      if (!body.sessionId) {
        send(res, 400, { ok: false, error: "sessionId required" });
        return;
      }
      if (!board.requestFocus(body.sessionId)) {
        send(res, 404, { ok: false, error: "unknown session" });
        return;
      }
      send(res, 200, { ok: true });
      return;
    }
    send(res, 404, { ok: false, error: "not found" });
  };
  const disposeRoute = ctx.webServer.register({
    kind: "prefix",
    path: PREFIX,
    handler: (req, res) => {
      void handler(req, res).catch((error) => {
        if (!res.headersSent) send(res, 400, { ok: false, error: String(error) });
      });
    }
  });
  return () => {
    stopListen();
    for (const res of streams.values()) {
      try {
        res.end();
      } catch {
      }
    }
    streams.clear();
    disposeRoute();
  };
}
export {
  attachHttp,
  authorized,
  browserTrusted,
  isLoopback
};

//# sourceMappingURL=http.js.map
