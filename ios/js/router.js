// Two Leanback pages share the app: "browser" shows the home screen and lists, "player" plays the videos opened from it.
// The browser hands every video command to the native shell instead of running it; the shell opens the player page
// and has it run the same command. The player forwards browse and search commands back to the browser.
const rcMod = require('../../src/preload/util/resolveCommandModifiers')

const isWatch = () => location.hash.startsWith('#/watch')

function post(message) {
    try {
        window.webkit?.messageHandlers?.vtRoute?.postMessage(message)
    } catch (e) {}
}

// The command itself, or one of the commands it executes; `reelWatchEndpoint` (Shorts) is a different key.
function hasEndpoint(command, keys, depth = 0) {
    if (!command || typeof command !== 'object' || depth > 4) return false
    if (keys.some(key => key in command)) return true
    const nested = command.commandExecutorCommand?.commands
    return Array.isArray(nested) && nested.some(item => hasEndpoint(item, keys, depth + 1))
}

function serialize(command) {
    try {
        return JSON.stringify(command)
    } catch (e) {
        return null
    }
}

module.exports = () => {
    if (window.top !== window) return
    const role = globalThis.__vtRole
    if (role !== 'browser' && role !== 'player') return

    window.__vtExecute = (json) => rcMod.resolveCommand(JSON.parse(json))

    if (role === 'browser') {
        rcMod.addInputModifier((command) => {
            if (window.__vtPlayerReady !== true || isWatch() || !hasEndpoint(command, ['watchEndpoint'])) return command
            const json = serialize(command)
            if (!json) return command
            post({ type: 'open', command: json })
            return false
        })
        // Safety net: if a video still opens here while the player is ready, say so (it plays here as before).
        window.addEventListener('hashchange', () => {
            if (window.__vtPlayerReady === true && isWatch()) post({ type: 'log', text: 'browser opened ' + location.hash })
        })
        return
    }

    let opened = false
    let sawWatch = false

    window.__vtOpen = (json) => {
        opened = true
        sawWatch = false
        rcMod.resolveCommand(JSON.parse(json))
    }

    const leave = window.__vtLeavePlayer
    window.__vtLeavePlayer = async () => {
        opened = false
        await leave?.()
    }

    rcMod.addInputModifier((command) => {
        if (!opened || !isWatch() || !hasEndpoint(command, ['browseEndpoint', 'searchEndpoint'])) return command
        const json = serialize(command)
        if (!json) return command
        post({ type: 'forward', command: json })
        return false
    })

    let ready = false
    setInterval(() => {
        if (!ready && Object.values(window._yttv ?? {}).some(entry => typeof entry?.instance?.resolveCommand === 'function')) {
            ready = true
            post({ type: 'ready' })
        }
        // The page left the player by itself (not through our close): the native player UI must follow.
        if (!opened) return
        if (isWatch()) sawWatch = true
        else if (sawWatch) {
            opened = false
            post({ type: 'close' })
        }
    }, 250)
}
