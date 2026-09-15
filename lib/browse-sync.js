const KEY = /* @__PURE__ */ Symbol.for("dsh-notch.browse-sync.v1");
function sessionId(request) {
  const value = request?.address?.sessionId ?? request?.address?.childSessionId;
  return typeof value === "string" ? value : void 0;
}
function installBrowseSync(controller, observe) {
  let state = controller[KEY];
  if (!state) {
    for (const name of ["page", "follow"]) {
      const own = Object.getOwnPropertyDescriptor(controller, name);
      const text = typeof own?.value === "function" ? own.value.toString().replace(/\s/g, "") : "";
      const legacy = name === "follow" ? "function*(req,signal){constsid=getTargetSessionId(req.address);if(sid)board.markSeen(sid);returnyield*origFollow(req,signal)}" : "(req,signal)=>{constsid=getTargetSessionId(req.address);if(sid)board.markSeen(sid);returnorigPage(req,signal)}";
      if (text === legacy) {
        const base = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(controller), name)?.value;
        if (typeof base !== "function" || !base.toString().replace(/\s/g, "").includes(`returnthis.history.${name}(request,signal)`)) {
          throw new Error(`Cannot restore known legacy Notch ${name}: official prototype changed`);
        }
        delete controller[name];
      }
    }
    state = { observers: /* @__PURE__ */ new Set(), methods: [] };
    for (const name of ["page", "follow"]) {
      const descriptor = Object.getOwnPropertyDescriptor(controller, name);
      const original = controller[name];
      const wrapped = function(...args) {
        const result = Reflect.apply(original, this, args);
        const id = sessionId(args[0]);
        if (id) for (const callback of [...state.observers]) {
          try {
            callback(id);
          } catch {
          }
        }
        return result;
      };
      controller[name] = wrapped;
      state.methods.push({ name, descriptor, wrapped });
    }
    controller[KEY] = state;
  }
  state.observers.add(observe);
  let disposed = false;
  return () => {
    if (disposed) return;
    disposed = true;
    state.observers.delete(observe);
    if (state.observers.size) return;
    for (const { name, descriptor, wrapped } of state.methods) {
      if (controller[name] !== wrapped) continue;
      if (descriptor) Object.defineProperty(controller, name, descriptor);
      else delete controller[name];
    }
    if (controller[KEY] === state) delete controller[KEY];
  };
}
export {
  installBrowseSync
};

//# sourceMappingURL=browse-sync.js.map
