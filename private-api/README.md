# Private API helper (optional)

AppleScript can only send plain text. Real @mentions need IMCore, Apple's
private framework, called from inside Messages.app. `IMKitHelper.m` is a small
dylib that loads into Messages, dials the SDK on `127.0.0.1:45677` and sends
text with `__kIMMentionConfirmedMention` ranges. It also looks up the names
people share with their iMessage profile.

## One-time Mac setup (Apple Silicon)

1. Recovery → `csrutil disable`.
2. `sudo nvram boot-args="-arm64e_preview_abi"` (lets a non-Apple arm64e dylib load into an Apple process).
3. `sudo defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation -bool true`
4. Reboot.

## Use

```sh
private-api/build.sh    # build/IMKitHelper.dylib
private-api/launch.sh   # restarts Messages.app with it loaded
```

```ts
const sdk = new IMessageSDK({ privateApi: {} })   // or { port }
await sdk.send({ to: chatId, text: 'hey Kai', mentions: [{ address: '+15551234567', start: 4, length: 3 }] })
sdk.privateApiConnected                           // true once the helper dialed in
await sdk.nickname('+15551234567')                // 'Kai' if they shared their name, else null
```

Without the helper (or in a DM, where iMessage has no mentions), the same
`send` goes out by AppleScript as plain text. The helper relaunches with
Messages only through `launch.sh`; a plain relaunch of Messages drops it.
IMCore is private, so a macOS update can break it: check
`log show --last 5m --predicate 'eventMessage CONTAINS "imessage-kit helper"'`.
