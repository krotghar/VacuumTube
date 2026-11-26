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
        // While the player page is on the screen the browsing page must stay silent: previews are stopped as they start
        // (Shorts are not previews and play on).
        let quiet = false
        const pauseIfQuiet = (e) => {
            if (quiet && ![...document.querySelectorAll('ytlr-shorts-page')].some(page => page.getBoundingClientRect().width > 0)) e.target.pause?.()
        }
        for (const type of ['play', 'playing']) document.addEventListener(type, pauseIfQuiet, true)
        window.__vtQuiet = (value) => {
            quiet = value
            if (quiet) for (const video of document.querySelectorAll('video')) pauseIfQuiet({ target: video })
        }
        // Safety net: if a video still opens here while the player is ready, say so (it plays here as before).
        window.addEventListener('hashchange', () => {
            if (window.__vtPlayerReady === true && isWatch()) post({ type: 'log', text: 'browser opened ' + location.hash })
        })
        return
    }

    // How long the page may take to reach the player before the shell gives up on it (a dialog or toast instead of a video).
    const WATCH_TIMEOUT_MS = 8000

    let opened = false
    let sawWatch = false
    let openedAt = 0
    const setOpened = (value) => {
        opened = value
        window.__vtOpened = value
    }
    window.__vtOpened = false
    window.__vtOpenGen = 0

    window.__vtOpen = (json) => {
        setOpened(true)
        sawWatch = false
        openedAt = Date.now()
        // A "leave" still running for the previous video must not press Escape in this one.
        window.__vtOpenGen++
        rcMod.resolveCommand(JSON.parse(json))
    }

    const leave = window.__vtLeavePlayer
    window.__vtLeavePlayer = async () => {
        setOpened(false)
        await leave?.()
    }

    rcMod.addInputModifier((command) => {
        if (!opened || !isWatch() || !hasEndpoint(command, ['browseEndpoint', 'searchEndpoint'])) return command
        const json = serialize(command)
        if (!json) return command
        post({ type: 'forward', command: json })
        return false
    })

    window.__vtPause = () => document.querySelector('.html5-video-player')?.pauseVideo?.()

    // The displayed picture inside the <video> element (it is letterboxed), for the native minimize animation.
    window.__vtVideoRect = () => {
        const video = document.querySelector('video')
        if (!video) return null
        const r = video.getBoundingClientRect()
        const aspect = video.videoWidth && video.videoHeight ? video.videoWidth / video.videoHeight : r.width / r.height
        let w = r.width
        let h = r.height
        if (w / h > aspect) w = h * aspect
        else h = w / aspect
        return [r.left + (r.width - w) / 2, r.top + (r.height - h) / 2, w, h]
    }

    // Back from the system PiP window: the native side brings the player to the screen.
    let wasPip = false
    document.addEventListener('webkitpresentationmodechanged', (e) => {
        const mode = e.target.webkitPresentationMode
        if (mode === 'inline' && wasPip) post({ type: 'pipInline' })
        wasPip = mode === 'picture-in-picture'
    }, true)

    let ready = false
    setInterval(() => {
        if (!ready && Object.values(window._yttv ?? {}).some(entry => typeof entry?.instance?.resolveCommand === 'function')) {
            ready = true
            post({ type: 'ready' })
        }
        // The page left the player by itself (not through our close): the native player UI must follow.
        if (!opened) return
        if (isWatch()) sawWatch = true
        else if (sawWatch || Date.now() - openedAt > WATCH_TIMEOUT_MS) {
            setOpened(false)
            post({ type: 'close' })
        }
    }, 250)
}
