// Recovery belongs to the desktop window, never to the Host or a plugin session.
// A zero exit code is still unexpected while the user's window remains open.
export function installRendererRecovery({
  app, window, write = () => {}, onUnavailable = () => {},
  repaint = () => window.webContents.invalidate(),
  now = Date.now, scheduler = {setTimeout, clearTimeout},
  retryDelayMs = 250, loadTimeoutMs = 15000, maxAttempts = 2, retryWindowMs = 60000,
}) {
  const contents = window.webContents;
  const listeners = [];
  let disposed = false, quitting = false, closing = false;
  let pending = false, reloadTimer = null, deadlineTimer = null, attempts = [];
  const on = (emitter, event, fn) => {
    emitter.on(event, fn);
    listeners.push(() => emitter.removeListener(event, fn));
  };
  const live = () => !disposed && !quitting && !closing && !window.isDestroyed() && !contents.isDestroyed();
  const record = (event, data = {}) => {
    try { write(event, {contentsId: contents.id, ...data}); } catch {}
  };
  const clearTimers = () => {
    if (reloadTimer !== null) scheduler.clearTimeout(reloadTimer);
    if (deadlineTimer !== null) scheduler.clearTimeout(deadlineTimer);
    reloadTimer = deadlineTimer = null;
  };
  const unavailable = reason => {
    record('renderer-recovery-unavailable', {reason});
    try { Promise.resolve(onUnavailable(reason)).catch(() => {}); } catch {}
  };
  const watchLoad = () => {
    if (deadlineTimer !== null) scheduler.clearTimeout(deadlineTimer);
    deadlineTimer = scheduler.setTimeout(() => {
      deadlineTimer = null;
      if (live() && pending) unavailable('load-timeout');
    }, loadTimeoutMs);
  };
  on(contents, 'render-process-gone', (_event, details) => {
    if (!live()) return;
    if (reloadTimer !== null) return;
    clearTimers();
    pending = false;
    const time = now();
    attempts = attempts.filter(at => time - at < retryWindowMs);
    if (attempts.length >= maxAttempts) { unavailable('repeated-exit'); return; }
    attempts.push(time);
    pending = true;
    record('renderer-recovery-scheduled', {reason: details.reason, exitCode: details.exitCode, attempt: attempts.length});
    reloadTimer = scheduler.setTimeout(() => {
      reloadTimer = null;
      if (!live() || !pending) return;
      watchLoad();
      try {
        // Preserve the existing navigation controller, auth session and conversation.
        if (!contents.isLoading()) contents.reload();
      } catch {
        clearTimers();
        pending = false;
        unavailable('reload-failed');
      }
    }, retryDelayMs);
  });
  on(contents, 'did-start-loading', () => {
    if (!live() || !pending) return;
    // A user's manual Reload can win the race with our queued recovery.
    if (reloadTimer !== null) scheduler.clearTimeout(reloadTimer);
    reloadTimer = null;
    watchLoad();
  });
  on(contents, 'did-finish-load', () => {
    if (!live() || !pending || contents.getOSProcessId() <= 0) return;
    clearTimers();
    pending = false;
    try { repaint(); } catch { record('renderer-repaint-failed'); }
    record('renderer-recovery-complete', {rendererPid: contents.getOSProcessId()});
  });
  on(app, 'before-quit', () => { quitting = true; pending = false; clearTimers(); });
  on(window, 'close', () => {
    closing = true;
    pending = false;
    clearTimers();
    // A cancelled close must not disable recovery for the remaining window.
    queueMicrotask(() => { if (!disposed && !quitting && !window.isDestroyed()) closing = false; });
  });
  on(contents, 'will-prevent-unload', () => { quitting = false; closing = false; });
  function dispose() {
    if (disposed) return;
    disposed = true;
    clearTimers();
    for (const remove of listeners) remove();
  }
  on(window, 'closed', dispose);
  on(contents, 'destroyed', dispose);
  record('renderer-recovery-attached');
  return dispose;
}
