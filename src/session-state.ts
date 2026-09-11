import type { Session } from '@deepseek-ai/dsh-session'
import type { NotchLastTurn } from './types.ts'

export interface FoldedSession {
  busy: boolean
  lastTurn?: NotchLastTurn
}

const FAILED = new Set(['error', 'blocked', 'max-tokens'])

export function foldSession(session: Session): FoldedSession {
  let busy = false
  let lastTurn: NotchLastTurn | undefined
  for (const event of session.snapshotEvents()) {
    if (event.type === 'turn/start') {
      busy = true
      lastTurn = undefined
      continue
    }
    if (event.type === 'turn/end') {
      busy = false
      const kind = event.data.reason.kind
      lastTurn = { at: event.time, kind, failed: FAILED.has(kind) }
    }
  }
  return { busy, lastTurn }
}

export function isChildSession(session: Session): boolean {
  return session.header.parentSession !== undefined || session.header.origin === 'subagent'
}
