import { connect } from "node:net";
const ADAPTER_CLASSES = ["activity", "result", "awaiting"];
const RENEW_MS = 2e3;
class NotchProviderClient {
  socket = null;
  buffer = "";
  renewTimer = null;
  reconnectTimer = null;
  closed = false;
  granted = false;
  sent = /* @__PURE__ */ new Map();
  registration;
  path;
  handlers;
  log;
  constructor(options, registration) {
    this.path = options.path;
    this.handlers = options.handlers;
    this.registration = registration;
    this.log = options.log ?? (() => void 0);
  }
  /** Whether a grant is currently held, which is what makes deltas meaningful. */
  get isGranted() {
    return this.granted;
  }
  /**
   * Connect and register.
   *
   * Nothing is awaited that could fail the caller: a missing endpoint is the
   * ordinary case of Notch not running, and the provider simply tries again.
   */
  start() {
    this.closed = false;
    this.open();
  }
  /** Stop for good, giving up the lease and the connection. */
  stop() {
    this.closed = true;
    if (this.renewTimer !== null) clearInterval(this.renewTimer);
    if (this.reconnectTimer !== null) clearTimeout(this.reconnectTimer);
    this.renewTimer = null;
    this.reconnectTimer = null;
    if (this.socket !== null) {
      this.send({ type: "unregister" });
      this.socket.end();
      this.socket = null;
    }
  }
  /**
   * Send the snapshot that opens a subscription.
   *
   * Sent on every grant, including the one after a reconnect: Notch holds what a
   * provider last said only for as long as its lease, so a provider that comes
   * back states the whole of what it has rather than a delta from a state the
   * other side may no longer remember.
   */
  snapshot(entities) {
    if (!this.granted) return;
    this.sent.clear();
    for (const entity of entities) this.sent.set(entity.key, entity);
    this.send({ type: "snapshot", entities });
  }
  /**
   * Send only what changed since the last snapshot or delta.
   *
   * Nothing is written before a grant, and nothing is remembered either: the
   * grant is what makes state sendable, and a provider that recorded what it
   * could not say would believe Notch holds something it has never been told.
   */
  apply(upsert, remove) {
    if (!this.granted) return;
    for (const entity of upsert) {
      this.sent.set(entity.key, entity);
      this.send({ type: "upsert", entity });
    }
    for (const key of remove) {
      this.sent.delete(key);
      this.send({ type: "remove", key });
    }
  }
  /** Clear the unread flag on a result the user has seen in DSH. */
  acknowledge(key) {
    if (!this.granted) return;
    const entity = this.sent.get(key);
    if (entity === void 0 || entity.unread !== true) return;
    this.sent.set(key, { ...entity, unread: false });
    this.send({ type: "ack", key });
  }
  /** The entities this provider believes Notch is holding. */
  held() {
    return [...this.sent.values()];
  }
  // MARK: - The connection
  open() {
    const socket = connect(this.path);
    this.socket = socket;
    socket.setNoDelay(true);
    socket.unref();
    socket.on("connect", () => {
      this.log(`connected to ${this.path}`);
      this.send({ type: "register", registration: this.registration });
    });
    socket.on("data", (chunk) => {
      this.buffer += chunk.toString("utf8");
      let newline = this.buffer.indexOf("\n");
      while (newline !== -1) {
        const line = this.buffer.slice(0, newline);
        this.buffer = this.buffer.slice(newline + 1);
        if (line.trim() !== "") this.receive(line);
        newline = this.buffer.indexOf("\n");
      }
    });
    socket.on("error", (error) => {
      this.log(`notch is not reachable: ${error.message}`);
    });
    socket.on("close", () => {
      this.granted = false;
      if (this.renewTimer !== null) clearInterval(this.renewTimer);
      this.renewTimer = null;
      this.socket = null;
      this.handlers.onClosed?.("the connection to Notch ended");
      this.scheduleReconnect();
    });
  }
  /** Try again, at the lease's own interval, until stopped. */
  scheduleReconnect() {
    if (this.closed || this.reconnectTimer !== null) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (!this.closed) this.open();
    }, RENEW_MS);
    this.reconnectTimer.unref();
  }
  send(message) {
    if (this.socket === null || this.socket.destroyed) return;
    this.socket.write(`${JSON.stringify(message)}
`);
  }
  /** One message from Notch. */
  receive(line) {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      this.log("notch sent something that is not JSON");
      return;
    }
    switch (message.type) {
      case "granted": {
        this.granted = true;
        this.startRenewing();
        this.handlers.onGranted?.(message.grant);
        break;
      }
      case "refused":
        this.handlers.onRefused?.(String(message.code), String(message.reason));
        break;
      case "consent.granted":
        this.handlers.onConsentGranted?.();
        this.send({ type: "register", registration: this.registration });
        break;
      case "consent.denied":
        this.handlers.onConsentDenied?.();
        break;
      case "interaction.settled":
        this.handlers.onSettled?.(message);
        break;
      case "action.invoke":
        this.handlers.onAction?.(
          String(message.name),
          message.key === void 0 ? void 0 : String(message.key),
          message.args
        );
        break;
      case "snapshot.required":
        this.snapshot([...this.sent.values()]);
        break;
      default:
        this.log(`notch sent a message this version does not know: ${String(message.type)}`);
    }
  }
  startRenewing() {
    if (this.renewTimer !== null) clearInterval(this.renewTimer);
    this.renewTimer = setInterval(() => {
      this.send({ type: "renew" });
    }, RENEW_MS);
    this.renewTimer.unref();
  }
}
function endpointPath() {
  return process.env.DSH_NOTCH_SOCKET ?? "/tmp/notch/notch.sock";
}
export {
  ADAPTER_CLASSES,
  NotchProviderClient,
  endpointPath
};

//# sourceMappingURL=client.js.map
