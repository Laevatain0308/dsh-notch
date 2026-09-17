import { ADAPTER_CLASSES, NotchProviderClient, endpointPath } from "./client.js";
import {
  answersFrom,
  delta,
  entitiesFor,
  isDeciding,
  remember
} from "./entities.js";
const REVIEW_MS = 2e3;
class DshProvider {
  client;
  board;
  held = /* @__PURE__ */ new Map();
  log;
  decisionTimeoutMs;
  actions;
  unsubscribe = null;
  /** Whether the connection has been asked for, which is not the same as made. */
  connecting = false;
  /** Whether a change has ever been reported to this adapter by its host. */
  heardAChange = false;
  reviewTimer = null;
  /**
   * Decisions the user has not answered, by the interaction id Notch knows.
   *
   * The questions are kept, not looked up again when the answer arrives: by then
   * the session may have moved on, and the answer belongs to the question that
   * was asked rather than to whatever the session is doing now.
   */
  outstanding = /* @__PURE__ */ new Map();
  constructor(options) {
    this.board = options.board;
    this.log = options.log;
    this.decisionTimeoutMs = options.decisionTimeoutMs;
    this.actions = options.actions;
    this.client = new NotchProviderClient(
      {
        path: endpointPath(),
        log: options.log,
        handlers: {
          onGranted: (grant) => {
            this.onGranted(grant);
          },
          onRefused: (code, reason) => {
            this.log(`notch refused (${code}): ${reason}`);
          },
          onConsentGranted: () => {
            this.log("the user allowed this program");
          },
          onConsentDenied: () => {
            this.log("the user refused this program; it will not be shown");
          },
          onSettled: (settlement) => {
            this.onSettled(settlement);
          },
          onAction: (name, key) => {
            this.onAction(name, key);
          }
        }
      },
      {
        displayName: "DSH Desktop",
        requestedClasses: [...ADAPTER_CLASSES],
        actions: options.actions,
        timeoutMs: options.decisionTimeoutMs
      }
    );
  }
  /**
   * Begin following the board.
   *
   * Nothing is connected yet. A provider that has nothing to show has no business
   * asking the user for permission to show it, and an idle DSH has nothing: the
   * connection is opened by the first thing worth displaying.
   */
  start() {
    this.unsubscribe = this.board.onChange(() => {
      if (!this.heardAChange) {
        this.heardAChange = true;
        this.log("the host reports board changes directly");
      }
      this.publish();
    });
    this.reviewTimer = setInterval(() => {
      this.review();
    }, REVIEW_MS);
    this.reviewTimer.unref();
    this.publish();
  }
  /**
   * Look at the board, and say what changed.
   *
   * The same call the notification makes, so there is one path to being up to
   * date rather than two that can disagree — this only decides *when* it runs.
   */
  review() {
    this.publish();
  }
  stop() {
    this.unsubscribe?.();
    this.unsubscribe = null;
    if (this.reviewTimer !== null) clearInterval(this.reviewTimer);
    this.reviewTimer = null;
    this.client.stop();
  }
  /** Whether Notch has accepted this provider, which is worth logging once. */
  onGranted(grant) {
    this.log(`notch granted ${grant.grantedClasses.join(", ")}`);
    this.publish();
  }
  /**
   * Tell Notch what DSH is doing, as far as it has changed.
   *
   * A snapshot is sent by `onGranted` rather than here: until the grant arrives
   * there is nothing that may be sent, and the state at that moment is whatever
   * the board says then, not whatever it said when the connection opened.
   */
  publish() {
    const rows = this.rows();
    if (!this.client.isGranted) {
      if (this.connecting || rows.length === 0) return;
      this.connecting = true;
      this.log("dsh has something to show; connecting to notch");
      this.client.start();
      return;
    }
    const context = {
      // One decision may be outstanding at a time, so the rest are counted
      // rather than raised: the number is what tells the user that answering
      // this one uncovers another.
      queuedDecisions: Math.max(0, rows.filter(isDeciding).length - 1),
      actions: this.actions
    };
    const entities = entitiesFor(rows, context, this.decisionTimeoutMs);
    this.rememberDecisions(entities);
    if (this.held.size === 0 && this.client.held().length === 0) {
      this.client.snapshot(entities);
      for (const entity of entities) this.held.set(entity.key, entity);
      return;
    }
    const change = delta(this.held, entities);
    remember(this.held, change);
    this.client.apply(change.upsert, change.remove);
  }
  rows() {
    return this.board.snapshot("adapter").rows;
  }
  /** Keep the questions of every decision that is on screen, so an answer can be read. */
  rememberDecisions(entities) {
    const present = /* @__PURE__ */ new Set();
    for (const entity of entities) {
      const interaction = entity.interaction;
      if (interaction === void 0) continue;
      present.add(interaction.id);
      if (this.outstanding.has(interaction.id)) continue;
      this.outstanding.set(interaction.id, {
        sessionId: entity.key.replace(/:ask$/, ""),
        questions: interaction.questions
      });
    }
    for (const id of [...this.outstanding.keys()]) {
      if (!present.has(id)) this.outstanding.delete(id);
    }
  }
  /**
   * Do what the user asked for by activating something.
   *
   * The action is the provider's to interpret, and this one interprets `open` as
   * "bring that session forward" — which is the same thing the HTTP surface has
   * always done with `/focus`, so the two paths cannot drift into doing different
   * things with the same tap.
   */
  onAction(name, key) {
    if (name !== "open" || key === void 0) return;
    const sessionId = key.replace(/:(run|result|ask)$/, "");
    this.board.markSeen(sessionId);
    if (!this.board.requestFocus(sessionId)) this.log(`the session ${sessionId} is no longer there`);
  }
  /**
   * Deliver the user's answer to DSH.
   *
   * The answer is applied to the board, which is the same path the HTTP surface
   * uses, so a decision answered in Notch and a decision answered in DSH are the
   * same decision arriving the same way.
   */
  onSettled(settlement) {
    const outstanding = this.outstanding.get(settlement.interactionId);
    this.outstanding.delete(settlement.interactionId);
    if (settlement.outcome.status === "cancelled") {
      this.log(`a decision was ${settlement.outcome.reason}`);
      return;
    }
    const [kind, id] = settlement.interactionId.split(":", 2);
    if (id === void 0) return;
    const answers = settlement.outcome.answers;
    if (kind === "approval") {
      const outcome = answers[id]?.[0] === "\u5141\u8BB8" ? "allowed-once" : "rejected";
      if (!this.board.decideApproval(id, outcome)) {
        this.log(`the approval ${id} was no longer waiting`);
      }
      return;
    }
    const questions = outstanding?.questions ?? [];
    const translated = answersFrom({ id: settlement.interactionId, questions }, answers);
    const items = "items" in translated && translated.items !== void 0 ? translated.items : [];
    if (!this.board.answerAsk(id, items)) {
      this.log(`the question ${id} was no longer waiting`);
    }
  }
}
export {
  DshProvider
};

//# sourceMappingURL=adapter.js.map
