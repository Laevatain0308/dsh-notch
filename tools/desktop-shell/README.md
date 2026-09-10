# Desktop renderer recovery

This optional thin-shell patch prevents an unexpected renderer exit from leaving
an existing DSH window permanently blank. It does **not** identify or fix the
underlying long-idle renderer termination.

The recovery controller listens to `render-process-gone`, including `clean-exit`.
While the app/window remains open it reloads the original WebContents, preserves
its navigation/auth context, requests a repaint after load, and records the result.
It never starts, stops or restarts a Host. Two automatic attempts are allowed per
minute; further exits and a 15-second load timeout go to a native error prompt.
App quit/window close cancels pending work. The shell integration adds window and
system idle metadata to bounded local diagnostic logs.

`child-log.mjs` fixes a separate shutdown race: each child stdout/stderr stream
pipes with `end: false` so EOF cannot close the shared desktop log before an exit
callback writes to it. Logging errors cannot raise an uncaught main-process error.

## Checks

```sh
node --test tools/desktop-shell/*.test.mjs tools/diagnostics/renderer-diagnostics.test.mjs
"$DSH_TEST_ELECTRON" tools/desktop-shell/recovery-probe.cjs --baseline
"$DSH_TEST_ELECTRON" tools/desktop-shell/recovery-probe.cjs
```

Use the target app's matching Electron executable. The baseline is expected to
fail: it has no recovery handler. The repaired native integration fixture uses a
temporary profile/static page, crashes only its own renderer, checks both visible
and hidden windows twice, verifies an actual painted frame against its healthy
baseline (including display color management), and verifies retry limiting.
It never reads DSH conversations or invokes models. This is an Electron lifecycle
test, not an alternative browser automation interface.

## Package and activate

`package-recovery.py <original-app.asar> <staging-directory>` produces a patched
ASAR, readable main module, and input/output hash manifest. It requires the known
thin-shell source shape with the earlier diagnostics hook and refuses an already
patched or unfamiliar archive. Every unrelated archive entry is preserved and
all output entry bytes are verified. To test packaged recovery, set
`DSH_RECOVERY_MODULE` to the staged ASAR's `src/renderer-recovery.mjs` before the
native probe. The script never installs or controls a process.

Keep a verified copy of the original ASAR. Installation is a separate, authorized,
atomic resource replacement after checking that the current archive still matches
the reviewed input. Shell-main changes require a controlled App reopen. The current
App owns its Host: do this only with the applicable task authorization and an idle
runtime, and prove that the old Host exited before launching the original App.
Once active, routine renderer recovery does not require another App/Host restart.
Verify diagnostic attachment plus the actual conversation/composer through the
normal app. A package checksum or a recovery log is not visual acceptance.

For rollback, restore the exact preserved original archive and perform the same
controlled App reopen. Never replace the user's checkout, history or Notch assets.
Do not commit local logs, screenshots, session data or installed-artifact backups.
