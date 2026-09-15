import { spawn, spawnSync, type ChildProcess } from 'node:child_process'
import { existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { RUNTIME_PATH } from './store.ts'

/**
 * Tie the native Notch process to the lifetime of the Host plugin: launch it
 * when the plugin mounts, terminate it when the plugin disposes.
 *
 * DSH Desktop boots its Host without the live patch watcher, so a mounted
 * plugin is the only place that reliably sees both edges of a Host session.
 * The Notch is a separate AppKit program rather than a Host module, so nothing
 * else stops it when the Host goes away — without this, quitting DSH leaves an
 * orphaned overlay attached to a dead origin.
 *
 * Absence is not an error. A machine that never built the Swift program, or
 * that runs a managed Notch from an App shell, gets a no-op and a log line.
 */

/** Overrides binary discovery with an absolute path to a `dsh-notch` executable. */
const BINARY_ENV = 'DSH_NOTCH_BIN'
/** Set to a non-empty value to keep the Host from launching a Notch at all. */
const DISABLE_ENV = 'DSH_NOTCH_NO_AUTOSTART'
/** Grace between SIGTERM and SIGKILL; a Notch that ignores SIGTERM still dies. */
const KILL_GRACE_MS = 2_000
/** Absolute path, because a Desktop-launched Host inherits a minimal PATH. */
const PGREP = '/usr/bin/pgrep'

/** The subset of `ctx.logger` this module reports through. */
export interface LauncherLogger {
  info: (message: string) => void
  warn: (message: string) => void
}

/** Deployment-varying launch choices, all optional. */
export interface NotchLaunchConfig {
  /** `false` keeps the Host from launching a Notch. Defaults to enabled. */
  enabled?: boolean
  /** Absolute path to a `dsh-notch` executable; skips discovery when set. */
  binary?: string
}

/** Injectable process probe, so tests do not depend on a real Notch running. */
export interface NotchLaunchDeps {
  /** Running Notch pids; defaults to the real {@link runningNotchPids} probe. */
  runningPids?: () => number[]
}

/**
 * Candidate executables built from this plugin's own checkout, best first.
 * The plugin is installed as a link to its checkout, so the module URL still
 * points at a directory that holds `macos/.build`.
 * @returns absolute candidate paths, whether or not they exist.
 */
function candidateBinaries(): string[] {
  const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
  return [
    join(packageRoot, 'macos', '.build', 'release', 'dsh-notch'),
    join(packageRoot, 'macos', '.build', 'debug', 'dsh-notch'),
  ]
}

/**
 * Resolve the Notch executable to launch.
 * @param override - configured binary path, which wins over the environment.
 * @returns the path to launch, or `undefined` when this machine has none.
 */
export function resolveNotchBinary(override?: string): string | undefined {
  const configured = override ?? process.env[BINARY_ENV]
  if (configured !== undefined && configured !== '') {
    return existsSync(configured) ? configured : undefined
  }
  return candidateBinaries().find(candidate => existsSync(candidate))
}

/**
 * Whether a process id is currently in use.
 * @param pid - process id to probe.
 * @returns true when the process exists, including one owned by another user.
 */
export function isRunning(pid: number): boolean {
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    // EPERM means the process exists but belongs to someone else.
    return (error as NodeJS.ErrnoException).code === 'EPERM'
  }
}

/**
 * Process ids of every running Notch, found by exact executable name.
 *
 * A Host restart must not stack a second overlay on the first: the README
 * warns about exactly that, and a Notch left behind by a killed Host is still
 * alive and still reading the runtime file this Host is about to rewrite.
 * @returns running pids, empty when the probe is unavailable or matches none.
 */
export function runningNotchPids(): number[] {
  if (!existsSync(PGREP)) return []
  const probe = spawnSync(PGREP, ['-x', 'dsh-notch'], { encoding: 'utf8' })
  if (probe.error !== undefined || typeof probe.stdout !== 'string') return []
  return probe.stdout
    .split('\n')
    .map(line => Number.parseInt(line.trim(), 10))
    .filter(pid => Number.isInteger(pid) && pid > 0)
}

/**
 * Terminate one process, escalating if it ignores the polite signal.
 * @param pid - process id to terminate.
 */
function terminate(pid: number): void {
  try {
    process.kill(pid, 'SIGTERM')
  } catch { /* already gone */ return }
  const escalation = setTimeout(() => {
    if (isRunning(pid)) {
      try {
        process.kill(pid, 'SIGKILL')
      } catch { /* exited during the grace period */ }
    }
  }, KILL_GRACE_MS)
  // Never let the escalation itself hold the Host open.
  escalation.unref()
}

/**
 * Launch the local Notch and return the disposer that stops it.
 *
 * Only a Notch this call started is ever stopped: a process the Host did not
 * spawn belongs to whoever did, and killing it would break a managed install.
 * That is also why an already-running Notch makes this a no-op — including one
 * that outlived a killed Host, which reconnects on its own because the client
 * re-reads the runtime file that was just rewritten.
 * @param logger - Host logger for the launch decision.
 * @param config - optional launch overrides from the plugin's cordis config.
 * @param deps - injectable process probe; tests override it.
 * @returns a disposer that terminates the launched Notch, if any.
 */
export function startNotch(
  logger: LauncherLogger,
  config: NotchLaunchConfig = {},
  deps: NotchLaunchDeps = {},
): () => void {
  const probeRunning = deps.runningPids ?? runningNotchPids
  if (process.platform !== 'darwin') return () => {}
  if (config.enabled === false) {
    logger.info('dsh-notch: Notch auto-launch disabled by config')
    return () => {}
  }
  if (process.env[DISABLE_ENV] !== undefined && process.env[DISABLE_ENV] !== '') {
    logger.info(`dsh-notch: Notch auto-launch disabled by ${DISABLE_ENV}`)
    return () => {}
  }

  const binary = resolveNotchBinary(config.binary)
  if (binary === undefined) {
    logger.info(`dsh-notch: no local Notch build found (${candidateBinaries().join(', ')}); not launching`)
    return () => {}
  }

  const existing = probeRunning()
  if (existing.length > 0) {
    logger.info(`dsh-notch: Notch already running (pid ${existing.join(', ')}); not launching a second one`)
    return () => {}
  }

  let child: ChildProcess
  try {
    child = spawn(binary, [], {
      detached: true,
      stdio: 'ignore',
      // Pin the runtime file explicitly: the Notch otherwise looks under the
      // user's home, which is the same file only while DSH_HOME is the default.
      env: { ...process.env, DSH_NOTCH_RUNTIME_FILE: RUNTIME_PATH },
    })
  } catch (error) {
    logger.warn(`dsh-notch: failed to launch Notch: ${String(error)}`)
    return () => {}
  }

  const pid = child.pid
  if (pid === undefined) {
    logger.warn('dsh-notch: Notch launch produced no process id')
    return () => {}
  }
  // Let the Host exit without waiting for the overlay it started.
  child.unref()
  child.on('error', (error: Error) => {
    logger.warn(`dsh-notch: Notch process error: ${error.message}`)
  })
  child.on('exit', (code, signal) => {
    logger.info(`dsh-notch: Notch exited (code ${String(code)}, signal ${String(signal)})`)
  })

  logger.info(`dsh-notch: launched Notch (pid ${String(pid)}) from ${binary}`)
  return () => {
    terminate(pid)
    logger.info(`dsh-notch: stopped Notch (pid ${String(pid)})`)
  }
}
