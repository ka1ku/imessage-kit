/**
 * Bridge to the private API helper (`private-api/IMKitHelper.m`).
 *
 * The helper runs inside Messages.app, which is sandboxed with outbound
 * network only, so the SDK listens on 127.0.0.1 and the helper dials in.
 * One helper connection at a time; a newer one replaces the older.
 * Requests are newline-delimited JSON with an `id`, answered in kind.
 *
 * Everything here is optional: with no helper connected, `connected` is
 * false and the sender keeps using AppleScript.
 */

import { createServer, type Server, type Socket } from 'node:net'

import { SendError } from '../../domain/errors'
import type { MessageMention } from '../../domain/message'

/** How long one helper request may take before it fails. */
const REQUEST_TIMEOUT_MS = 10_000

type Pending = {
    resolve: (value: Record<string, unknown>) => void
    reject: (error: Error) => void
    timer: NodeJS.Timeout
}

export class PrivateApiBridge {
    private readonly server: Server
    private socket: Socket | null = null
    private buffer = ''
    private nextId = 1
    private readonly pending = new Map<number, Pending>()

    constructor(
        readonly port: number,
        private readonly debug = false
    ) {
        this.server = createServer((socket) => this.attach(socket))
        this.server.on('error', (error) => console.error('[imessage-kit] private API bridge:', error.message))
        this.server.listen(port, '127.0.0.1')
    }

    /** A helper is loaded in Messages.app and connected. */
    get connected(): boolean {
        return this.socket != null
    }

    /** Sends `text` to a chat with `mentions` as real @mentions. Resolves with the new message's guid. */
    async send(chatGuid: string, text: string, mentions: readonly MessageMention[]): Promise<string | null> {
        const res = await this.request({ op: 'send', chat: chatGuid, text, mentions })
        return typeof res.guid === 'string' ? res.guid : null
    }

    /** The name a person shares with their iMessage profile, if they shared it with this account. */
    async nickname(handle: string): Promise<string | null> {
        const res = await this.request({ op: 'nickname', handle })
        return typeof res.name === 'string' ? res.name : null
    }

    close(): Promise<void> {
        this.detach(new Error('bridge closed'))
        return new Promise((resolve) => this.server.close(() => resolve()))
    }

    private request(body: Record<string, unknown>): Promise<Record<string, unknown>> {
        const socket = this.socket
        if (!socket) return Promise.reject(SendError('Private API helper is not connected'))
        const id = this.nextId++
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                this.pending.delete(id)
                reject(SendError(`Private API helper timed out on ${String(body.op)}`))
            }, REQUEST_TIMEOUT_MS)
            this.pending.set(id, { resolve, reject, timer })
            socket.write(`${JSON.stringify({ id, ...body })}\n`)
        })
    }

    private attach(socket: Socket): void {
        if (socket.remoteAddress !== '127.0.0.1' && socket.remoteAddress !== '::ffff:127.0.0.1') {
            socket.destroy()
            return
        }
        this.detach(new Error('helper reconnected'))
        this.socket = socket
        this.buffer = ''
        socket.setEncoding('utf8')
        socket.on('data', (chunk: string) => this.read(chunk))
        socket.on('close', () => {
            if (this.socket === socket) this.detach(new Error('helper disconnected'))
        })
        socket.on('error', () => {})
        if (this.debug) console.log(`[imessage-kit] private API helper connected on :${this.port}`)
    }

    private detach(reason: Error): void {
        this.socket?.destroy()
        this.socket = null
        for (const [id, p] of this.pending) {
            clearTimeout(p.timer)
            p.reject(SendError(`Private API helper: ${reason.message}`))
            this.pending.delete(id)
        }
    }

    private read(chunk: string): void {
        this.buffer += chunk
        for (let nl = this.buffer.indexOf('\n'); nl >= 0; nl = this.buffer.indexOf('\n')) {
            const line = this.buffer.slice(0, nl)
            this.buffer = this.buffer.slice(nl + 1)
            let res: Record<string, unknown>
            try {
                res = JSON.parse(line)
            } catch {
                continue
            }
            const p = this.pending.get(res.id as number)
            if (!p) continue
            this.pending.delete(res.id as number)
            clearTimeout(p.timer)
            if (res.ok === true) p.resolve(res)
            else p.reject(SendError(`Private API helper: ${String(res.error ?? 'failed')}`))
        }
    }
}
