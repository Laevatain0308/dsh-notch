/**
 * The provider side of the Notch protocol.
 *
 * A provider connects, registers, sends the snapshot that opens its subscription,
 * then sends deltas and renews its lease. It never polls and it never starts
 * Notch: if the endpoint is not there, the provider waits and carries on with the
 * work it exists to do, because a surface that is not running is not a reason for
 * anything else to fail.
 *
 * Framing is newline-delimited JSON, which `JSON.stringify` never breaks — a
 * string in JSON cannot contain a raw newline — so a frame is a line and a line
 * is a frame.
 *
 * @module provider/client
 */

import { connect, type Socket } from 'node:net'
import type { ProviderEntity } from './entities.ts'

/** What Notch granted, as the provider is told it. */
export interface Grant {
  protocolVersion: number
  grantedClasses: string[]
  limits: Record<string, number>
}

/** A settlement of a decision this provider raised. */
export interface Settlement {
  key: string
  interactionId: string
  outcome: { status: 'answered'; answers: Record<string, string[]> } | { status: 'cancelled'; reason: string }
}

/** What a provider does about what Notch tells it. */
export interface ProviderHandlers {
  /** The registration was accepted; the provider may send its snapshot. */
  onGranted?: (grant: Grant) => void
  /** The registration or a message was refused, with a code and a reason. */
  onRefused?: (code: string, reason: string) => void
  /** The user allowed this program; it may register now. */
  onConsentGranted?: () => void
  /** The user refused it. Nothing this provider sends will change that. */
  onConsentDenied?: () => void
  /** A decision this provider raised has been settled. */
  onSettled?: (settlement: Settlement) => void
  /** The user activated one of the provider's own actions. */
  onAction?: (name: string, key: string | undefined, args: unknown) => void
  /** The connection ended, which is not an error worth failing anything over. */
  onClosed?: (reason: string) => void
}

/** What a provider tells Notch about itself. */
export interface Registration {
  displayName: string
  requestedClasses: string[]
  actions?: string[]
  /** How long this provider's decisions may wait, in milliseconds. */
  timeoutMs?: number
}

/** The classes the adapter asks for, in one place so the consent request is legible. */
export const ADAPTER_CLASSES = ['activity', 'result', 'awaiting'] as const

/**
 * The lease interval, from the protocol.
 *
 * A provider that stops renewing has its entities removed, which is how a Notch
 * left running survives a provider that crashed. Renewing twice as often as the
 * lease expires means one lost message is not a removal.
 */
const RENEW_MS = 2_000

export interface ClientOptions {
  /** The socket to connect to. */
  path: string
  handlers: ProviderHandlers
  /** Called for anything worth a line in the Host's log. */
  log?: (message: string) => void
}

/**
 * One provider's connection to Notch.
 *
 * Everything is best-effort by design: a provider whose surface is not running
 * keeps working, and a provider that reconnects sends its snapshot again rather
 * than assuming Notch remembers anything. Nothing here throws at its caller for
 * a socket that is not there.
 */
export class NotchProviderClient {
  private socket: Socket | null = null
  private buffer = ''
  private renewTimer: NodeJS.Timeout | null = null
  private reconnectTimer: NodeJS.Timeout | null = null
  private closed = false
  private granted = false
  private readonly sent = new Map<string, ProviderEntity>()
  private readonly registration: Registration
  private readonly path: string
  private readonly handlers: ProviderHandlers
  private readonly log: (message: string) => void

  constructor(options: ClientOptions, registration: Registration) {
    this.path = options.path
    this.handlers = options.handlers
    this.registration = registration
    this.log = options.log ?? (() => undefined)
  }

  /** Whether a grant is currently held, which is what makes deltas meaningful. */
  get isGranted(): boolean {
    return this.granted
  }

  /**
   * Connect and register.
   *
   * Nothing is awaited that could fail the caller: a missing endpoint is the
   * ordinary case of Notch not running, and the provider simply tries again.
   */
  start(): void {
    this.closed = false
    this.open()
  }

  /** Stop for good, giving up the lease and the connection. */
  stop(): void {
    this.closed = true
    if (this.renewTimer !== null) clearInterval(this.renewTimer)
    if (this.reconnectTimer !== null) clearTimeout(this.reconnectTimer)
    this.renewTimer = null
    this.reconnectTimer = null
    if (this.socket !== null) {
      this.send({ type: 'unregister' })
      this.socket.end()
      this.socket = null
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
  snapshot(entities: ProviderEntity[]): void {
    if (!this.granted) return
    this.sent.clear()
    for (const entity of entities) this.sent.set(entity.key, entity)
    this.send({ type: 'snapshot', entities })
  }

  /**
   * Send only what changed since the last snapshot or delta.
   *
   * Nothing is written before a grant, and nothing is remembered either: the
   * grant is what makes state sendable, and a provider that recorded what it
   * could not say would believe Notch holds something it has never been told.
   */
  apply(upsert: ProviderEntity[], remove: string[]): void {
    if (!this.granted) return
    for (const entity of upsert) {
      this.sent.set(entity.key, entity)
      this.send({ type: 'upsert', entity })
    }
    for (const key of remove) {
      this.sent.delete(key)
      this.send({ type: 'remove', key })
    }
  }

  /** Clear the unread flag on a result the user has seen in DSH. */
  acknowledge(key: string): void {
    if (!this.granted) return
    const entity = this.sent.get(key)
    if (entity === undefined || entity.unread !== true) return
    this.sent.set(key, { ...entity, unread: false })
    this.send({ type: 'ack', key })
  }

  /** The entities this provider believes Notch is holding. */
  held(): ProviderEntity[] {
    return [...this.sent.values()]
  }

  // MARK: - The connection

  private open(): void {
    const socket = connect(this.path)
    this.socket = socket
    socket.setNoDelay(true)
    // A connection to a surface is never a reason for a provider's process to
    // stay alive. The Host has its own work to do; this must not be what keeps it
    // running, and must not be what keeps a test's process from ending.
    socket.unref()

    socket.on('connect', () => {
      this.log(`connected to ${this.path}`)
      this.send({ type: 'register', registration: this.registration })
    })

    socket.on('data', (chunk: Buffer) => {
      this.buffer += chunk.toString('utf8')
      let newline = this.buffer.indexOf('\n')
      while (newline !== -1) {
        const line = this.buffer.slice(0, newline)
        this.buffer = this.buffer.slice(newline + 1)
        if (line.trim() !== '') this.receive(line)
        newline = this.buffer.indexOf('\n')
      }
    })

    // An error here is the ordinary case of Notch not running, so it is worth a
    // log line rather than an exception: the provider has work to do either way.
    socket.on('error', (error: Error) => {
      this.log(`notch is not reachable: ${error.message}`)
    })

    socket.on('close', () => {
      this.granted = false
      if (this.renewTimer !== null) clearInterval(this.renewTimer)
      this.renewTimer = null
      this.socket = null
      this.handlers.onClosed?.('the connection to Notch ended')
      this.scheduleReconnect()
    })
  }

  /** Try again, at the lease's own interval, until stopped. */
  private scheduleReconnect(): void {
    if (this.closed || this.reconnectTimer !== null) return
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null
      if (!this.closed) this.open()
    }, RENEW_MS)
    this.reconnectTimer.unref()
  }

  private send(message: unknown): void {
    if (this.socket === null || this.socket.destroyed) return
    this.socket.write(`${JSON.stringify(message)}\n`)
  }

  /** One message from Notch. */
  private receive(line: string): void {
    let message: Record<string, unknown>
    try {
      message = JSON.parse(line) as Record<string, unknown>
    } catch {
      this.log('notch sent something that is not JSON')
      return
    }

    switch (message.type) {
      case 'granted': {
        this.granted = true
        this.startRenewing()
        this.handlers.onGranted?.(message.grant as Grant)
        break
      }
      case 'refused':
        this.handlers.onRefused?.(String(message.code), String(message.reason))
        break
      case 'consent.granted':
        this.handlers.onConsentGranted?.()
        break
      case 'consent.denied':
        this.handlers.onConsentDenied?.()
        break
      case 'interaction.settled':
        this.handlers.onSettled?.(message as unknown as Settlement)
        break
      case 'action.invoke':
        this.handlers.onAction?.(
          String(message.name),
          message.key === undefined ? undefined : String(message.key),
          message.args
        )
        break
      case 'snapshot.required':
        // Notch does not remember what this provider holds, so it says so rather
        // than guessing. A provider's answer is the same as after a reconnect.
        this.snapshot([...this.sent.values()])
        break
      default:
        this.log(`notch sent a message this version does not know: ${String(message.type)}`)
    }
  }

  private startRenewing(): void {
    if (this.renewTimer !== null) clearInterval(this.renewTimer)
    this.renewTimer = setInterval(() => { this.send({ type: 'renew' }) }, RENEW_MS)
    this.renewTimer.unref()
  }
}

/** Where providers connect, unless the environment says otherwise. */
export function endpointPath(): string {
  return process.env.DSH_NOTCH_SOCKET ?? '/tmp/notch/notch.sock'
}
