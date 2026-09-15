import { test } from 'node:test'
import assert from 'node:assert/strict'
import { chmodSync, existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  isRunning,
  resolveNotchBinary,
  runningNotchPids,
  startNotch,
} from '../src/notch-process.ts'

/** Collects the launcher's log lines so tests can assert on the decision. */
function recordingLogger() {
  const lines = []
  return {
    lines,
    info: message => lines.push(`info: ${message}`),
    warn: message => lines.push(`warn: ${message}`),
    text: () => lines.join('\n'),
  }
}

/**
 * A stand-in for the Notch executable that stays alive until it is killed.
 * Spawning the real overlay in a test would put a window on screen.
 */
function fakeNotch(dir) {
  const path = join(dir, 'fake-notch')
  writeFileSync(path, '#!/bin/sh\nexec sleep 300\n')
  chmodSync(path, 0o755)
  return path
}

/** Wait until `predicate` holds, so assertions do not race the signal. */
async function eventually(predicate, timeoutMs = 4000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (predicate()) return true
    await new Promise(resolve => setTimeout(resolve, 25))
  }
  return predicate()
}

test('resolves the built Notch from this checkout', () => {
  const resolved = resolveNotchBinary()
  const expected = join(process.cwd(), 'macos', '.build', 'release', 'dsh-notch')
  if (existsSync(expected)) {
    assert.equal(resolved, expected)
  } else {
    // A checkout that never built the Swift program must resolve to nothing
    // rather than to a path that does not exist.
    assert.equal(resolved, undefined)
  }
})

test('a configured binary wins, and a missing one resolves to nothing', () => {
  const dir = mkdtempSync(join(tmpdir(), 'notch-bin-'))
  try {
    const binary = fakeNotch(dir)
    assert.equal(resolveNotchBinary(binary), binary)
    assert.equal(resolveNotchBinary(join(dir, 'absent')), undefined)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('a live pid is running and a reaped pid is not', async () => {
  assert.equal(isRunning(process.pid), true)
  const dir = mkdtempSync(join(tmpdir(), 'notch-dead-'))
  try {
    // Spawn something short-lived, wait for it to be reaped, then probe it.
    const { spawn } = await import('node:child_process')
    const child = spawn(fakeNotch(dir), [], { stdio: 'ignore' })
    const pid = child.pid
    assert.equal(isRunning(pid), true)
    const exited = new Promise(resolve => child.on('exit', resolve))
    child.kill('SIGKILL')
    await exited
    assert.equal(await eventually(() => !isRunning(pid)), true)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('the process probe never throws and reports only real pids', () => {
  const pids = runningNotchPids()
  assert.ok(Array.isArray(pids))
  for (const pid of pids) assert.equal(isRunning(pid), true)
})

test('launches the Notch and stops exactly the process it started', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'notch-launch-'))
  try {
    const binary = fakeNotch(dir)
    const logger = recordingLogger()
    const stop = startNotch(logger, { binary }, { runningPids: () => [] })

    const pid = Number(/pid (\d+)/.exec(logger.text())?.[1])
    assert.ok(Number.isInteger(pid) && pid > 0, `no pid in: ${logger.text()}`)
    assert.equal(await eventually(() => isRunning(pid)), true)
    assert.match(logger.text(), /launched Notch/)

    stop()
    assert.equal(await eventually(() => !isRunning(pid)), true)
    assert.match(logger.text(), /stopped Notch/)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('an already-running Notch is left alone', () => {
  const dir = mkdtempSync(join(tmpdir(), 'notch-dup-'))
  try {
    const logger = recordingLogger()
    let probes = 0
    const stop = startNotch(logger, { binary: fakeNotch(dir) }, {
      runningPids: () => {
        probes += 1
        return [4242]
      },
    })
    assert.equal(probes, 1)
    assert.match(logger.text(), /already running \(pid 4242\)/)
    assert.doesNotMatch(logger.text(), /launched Notch/)
    // Nothing was spawned, so the disposer must not kill an unrelated process.
    stop()
    assert.doesNotMatch(logger.text(), /stopped Notch/)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('absence and explicit refusal are both quiet no-ops', () => {
  const dir = mkdtempSync(join(tmpdir(), 'notch-skip-'))
  try {
    const absent = recordingLogger()
    const stopAbsent = startNotch(absent, { binary: join(dir, 'absent') }, { runningPids: () => [] })
    assert.match(absent.text(), /no local Notch build found/)
    assert.doesNotMatch(absent.text(), /launched Notch/)
    assert.equal(typeof stopAbsent, 'function')
    stopAbsent()

    const disabled = recordingLogger()
    startNotch(disabled, { enabled: false }, { runningPids: () => [] })
    assert.match(disabled.text(), /disabled by config/)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})
