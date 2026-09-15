import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { RUNTIME_PATH } from "./store.js";
const BINARY_ENV = "DSH_NOTCH_BIN";
const DISABLE_ENV = "DSH_NOTCH_NO_AUTOSTART";
const KILL_GRACE_MS = 2e3;
const PGREP = "/usr/bin/pgrep";
function candidateBinaries() {
  const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  return [
    join(packageRoot, "macos", ".build", "release", "dsh-notch"),
    join(packageRoot, "macos", ".build", "debug", "dsh-notch")
  ];
}
function resolveNotchBinary(override) {
  const configured = override ?? process.env[BINARY_ENV];
  if (configured !== void 0 && configured !== "") {
    return existsSync(configured) ? configured : void 0;
  }
  return candidateBinaries().find((candidate) => existsSync(candidate));
}
function isRunning(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}
function runningNotchPids() {
  if (!existsSync(PGREP)) return [];
  const probe = spawnSync(PGREP, ["-x", "dsh-notch"], { encoding: "utf8" });
  if (probe.error !== void 0 || typeof probe.stdout !== "string") return [];
  return probe.stdout.split("\n").map((line) => Number.parseInt(line.trim(), 10)).filter((pid) => Number.isInteger(pid) && pid > 0);
}
function terminate(pid) {
  try {
    process.kill(pid, "SIGTERM");
  } catch {
    return;
  }
  const escalation = setTimeout(() => {
    if (isRunning(pid)) {
      try {
        process.kill(pid, "SIGKILL");
      } catch {
      }
    }
  }, KILL_GRACE_MS);
  escalation.unref();
}
function startNotch(logger, config = {}, deps = {}) {
  const probeRunning = deps.runningPids ?? runningNotchPids;
  if (process.platform !== "darwin") return () => {
  };
  if (config.enabled === false) {
    logger.info("dsh-notch: Notch auto-launch disabled by config");
    return () => {
    };
  }
  if (process.env[DISABLE_ENV] !== void 0 && process.env[DISABLE_ENV] !== "") {
    logger.info(`dsh-notch: Notch auto-launch disabled by ${DISABLE_ENV}`);
    return () => {
    };
  }
  const binary = resolveNotchBinary(config.binary);
  if (binary === void 0) {
    logger.info(`dsh-notch: no local Notch build found (${candidateBinaries().join(", ")}); not launching`);
    return () => {
    };
  }
  const existing = probeRunning();
  if (existing.length > 0) {
    logger.info(`dsh-notch: Notch already running (pid ${existing.join(", ")}); not launching a second one`);
    return () => {
    };
  }
  let child;
  try {
    child = spawn(binary, [], {
      detached: true,
      stdio: "ignore",
      // Pin the runtime file explicitly: the Notch otherwise looks under the
      // user's home, which is the same file only while DSH_HOME is the default.
      env: { ...process.env, DSH_NOTCH_RUNTIME_FILE: RUNTIME_PATH }
    });
  } catch (error) {
    logger.warn(`dsh-notch: failed to launch Notch: ${String(error)}`);
    return () => {
    };
  }
  const pid = child.pid;
  if (pid === void 0) {
    logger.warn("dsh-notch: Notch launch produced no process id");
    return () => {
    };
  }
  child.unref();
  child.on("error", (error) => {
    logger.warn(`dsh-notch: Notch process error: ${error.message}`);
  });
  child.on("exit", (code, signal) => {
    logger.info(`dsh-notch: Notch exited (code ${String(code)}, signal ${String(signal)})`);
  });
  logger.info(`dsh-notch: launched Notch (pid ${String(pid)}) from ${binary}`);
  return () => {
    terminate(pid);
    logger.info(`dsh-notch: stopped Notch (pid ${String(pid)})`);
  };
}
export {
  isRunning,
  resolveNotchBinary,
  runningNotchPids,
  startNotch
};

//# sourceMappingURL=notch-process.js.map
