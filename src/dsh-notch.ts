import type { Context } from '@deepseek-ai/cordis'
import type { ApprovalOutcome, ApprovalRequest } from '@deepseek-ai/dsh-user-approval'
import type { AskUserQuestionAnswer, AskUserQuestionRequest } from '@deepseek-ai/dsh-user-questions'
import type {} from '@deepseek-ai/dsh-host-webserver'
import type {} from '@deepseek-ai/dsh-session'
import { Board } from './board.ts'
import { DshProvider } from './provider/adapter.ts'
import { attachHttp } from './http.ts'
import { loadOrCreateToken, writeRuntime } from './store.ts'

export const name = 'dsh-notch'
export const inject = ['sessions', 'webServer', 'approval', 'userQuestions', 'agents']

export function apply(ctx: Context) {
  console.log('[my-plugins/dsh-notch] loaded')
  const board = new Board(ctx)
  const token = loadOrCreateToken()
  const origin = `http://${ctx.webServer.host}:${String(ctx.webServer.port)}`
  writeRuntime({
    origin,
    token,
    pid: process.pid,
    writtenAt: Date.now(),
  })

  // Nothing here starts Notch. A surface any program can ask to speak through
  // cannot also be a program's to launch: a persistent window that a local
  // process can make appear on demand is the intrusion the consent design exists
  // to prevent. The user runs it, or enables it at login, and a provider that
  // finds it absent waits.
  ctx.effect(() => attachHttp(ctx, board, token, origin), 'dsh-notch: http')

  // The same board, said again in the provider protocol. It runs beside the HTTP
  // path rather than instead of it: the overlay still reads that one, and a
  // rewrite that breaks the surface the user is looking at is not a rewrite
  // worth having. `DSH_NOTCH_PROVIDER=0` turns the new path off.
  if (process.env.DSH_NOTCH_PROVIDER !== '0') {
    const provider = new DshProvider({
      board,
      decisionTimeoutMs: 15 * 60_000,
      actions: ['open'],
      log: (message: string) => { ctx.logger.info('dsh-notch: %s', message) },
    })
    ctx.effect(() => {
      provider.start()
      return () => { provider.stop() }
    }, 'dsh-notch: provider')
  }

  const notify = debounce(() => board.notify(), 80)
  ctx.effect(() => notify.dispose, 'dsh-notch: notification timer')
  ctx.effect(() => ctx.on('session/created', notify), 'dsh-notch: created')
  ctx.effect(() => ctx.on('session/disposed', notify), 'dsh-notch: disposed')
  ctx.effect(() => ctx.on('session/event', (session, event) => {
    const type = String(event.type)
    if (type === 'turn/start' || type === 'turn/end' || type === 'session/title') {
      notify()
    }
    // When a turn starts or user sends a message in DSH, mark session as read
    if (type === 'turn/start' || (type === 'user/message' && (event.data as Record<string, unknown>)?.source === 'user')) {
      board.markSeen(session.id)
    }
  }), 'dsh-notch: events')
  ctx.effect(() => ctx.on('agent/status', notify), 'dsh-notch: agent-status')


  // Only intercept user-questions/request (AskUserQuestion).
  // Do NOT intercept internal tool approval/request which causes false alarms
  // when background agent tools run sandbox checks.
  ctx.on('user-questions/request', (
    request: AskUserQuestionRequest,
    next: () => Promise<AskUserQuestionAnswer>,
  ) => board.holdAsk(request, next), { prepend: true })
}

function debounce(fn: () => void, ms: number): (() => void) & { dispose: () => void } {
  let timer: ReturnType<typeof setTimeout> | undefined
  const notify = () => {
    if (timer) clearTimeout(timer)
    timer = setTimeout(() => { timer = undefined; fn() }, ms)
  }
  return Object.assign(notify, { dispose: () => { if (timer) clearTimeout(timer); timer = undefined } })
}
