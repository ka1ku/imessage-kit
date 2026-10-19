/**
 * PrivateApiBridge — the SDK side of the Messages.app helper.
 *
 * A TCP client stands in for the helper: it dials the bridge, reads the
 * newline-delimited requests and answers them the way IMKitHelper.m does.
 */

import { afterEach, describe, expect, it } from 'bun:test'
import { connect, type Socket } from 'node:net'

import { IMessageError } from '../src/domain/errors'
import { PrivateApiBridge } from '../src/infra/outgoing/private-api'

let port = 46_000 + Math.floor(Math.random() * 1000)
let bridge: PrivateApiBridge | null = null
let helper: Socket | null = null

afterEach(async () => {
    helper?.destroy()
    helper = null
    await bridge?.close()
    bridge = null
    port++
})

/** Connects a fake helper that answers every request with `answer(request)`. */
async function fakeHelper(answer: (req: Record<string, unknown>) => Record<string, unknown> | null) {
    const seen: Record<string, unknown>[] = []
    helper = connect(port, '127.0.0.1')
    let buffer = ''
    helper.setEncoding('utf8')
    helper.on('data', (chunk: string) => {
        buffer += chunk
        for (let nl = buffer.indexOf('\n'); nl >= 0; nl = buffer.indexOf('\n')) {
            const req = JSON.parse(buffer.slice(0, nl))
            buffer = buffer.slice(nl + 1)
            seen.push(req)
            const res = answer(req)
            if (res) helper?.write(`${JSON.stringify({ id: req.id, ...res })}\n`)
        }
    })
    await new Promise((resolve) => helper?.once('connect', resolve))
    while (!bridge?.connected) await new Promise((resolve) => setTimeout(resolve, 5))
    return seen
}

describe('PrivateApiBridge', () => {
    it('is not connected until a helper dials in, and rejects requests until then', async () => {
        bridge = new PrivateApiBridge(port)
        expect(bridge.connected).toBe(false)
        await expect(bridge.send('any;+;chat1', 'hi', [])).rejects.toBeInstanceOf(IMessageError)
    })

    it('sends text with mentions and returns the guid', async () => {
        bridge = new PrivateApiBridge(port)
        const seen = await fakeHelper(() => ({ ok: true, guid: 'GUID-1' }))
        const mentions = [{ address: '+15551234567', start: 4, length: 3 }]
        expect(await bridge.send('any;+;chat1', 'hey Kai', mentions)).toBe('GUID-1')
        expect(seen[0]).toMatchObject({ op: 'send', chat: 'any;+;chat1', text: 'hey Kai', mentions })
    })

    it('surfaces helper errors as SendError', async () => {
        bridge = new PrivateApiBridge(port)
        await fakeHelper(() => ({ ok: false, error: 'no chat any;+;chat1' }))
        await expect(bridge.send('any;+;chat1', 'hi', [])).rejects.toThrow('no chat any;+;chat1')
    })

    it('looks up nicknames, null when none was shared', async () => {
        bridge = new PrivateApiBridge(port)
        await fakeHelper((req) => ({ ok: true, name: req.handle === '+1555' ? 'Kai' : null }))
        expect(await bridge.nickname('+1555')).toBe('Kai')
        expect(await bridge.nickname('+1666')).toBeNull()
    })

    it('fails pending requests when the helper disconnects', async () => {
        bridge = new PrivateApiBridge(port)
        await fakeHelper(() => null)
        const pending = bridge.send('any;+;chat1', 'hi', [])
        helper?.destroy()
        await expect(pending).rejects.toThrow('helper disconnected')
        expect(bridge.connected).toBe(false)
    })
})
