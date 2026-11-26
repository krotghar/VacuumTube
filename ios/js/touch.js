// Touch gestures on top of Leanback's enable_touch_support (taps and list scrolling stay with Leanback).
const css = require('./shims/css')

const BACK = 27
const UP = 38
const DOWN = 40

const TAP_SLOP = 20
const SWIPE_MIN = 80
const DOUBLE_TAP_MS = 280
const SEEK_SECONDS = 10

const INTERACTIVE = 'yt-button-container, ytlr-button, ytlr-progress-bar, ytlr-tile-renderer, yt-lockup-view-model, button, ytlr-player-overlay-renderer, ytlr-endscreen-element-renderer'

const sleep = (ms) => new Promise(r => setTimeout(r, ms))

function pressKey(keyCode) {
    for (const type of ['keydown', 'keyup']) {
        const event = new Event(type)
        event.keyCode = keyCode
        document.dispatchEvent(event)
    }
}

const isWatch = () => location.hash.startsWith('#/watch')
// The player page has been asked to play a video (router.js): back is always possible then, even if the page is not at #/watch.
const playerOpened = () => globalThis.__vtRole === 'player' && window.__vtOpened === true
const player = () => document.querySelector('.html5-video-player')

// The end screens ("UP NEXT", "Next in N", the author's cards) live in the same overlay but are not the player panel.
const END_SCREEN = 'ytlr-player-overlay-renderer, ytlr-timely-action-renderer, ytlr-endscreen-renderer'

function overlayVisible() {
    const active = document.activeElement
    return !!active && active.tagName !== 'YT-FOCUS-CONTAINER' && !!active.closest('ytlr-squeezeback-player-overlay') && !active.closest(END_SCREEN)
}

function disableZoom() {
    const meta = document.createElement('meta')
    meta.name = 'viewport'
    meta.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no'
    document.head.appendChild(meta)
}

// Shorts have no route of their own: the hash stays as before and the page is told apart by its width (hidden pages keep 0).
const shortsPage = () => [...document.querySelectorAll('ytlr-shorts-page')].find(page => page.getBoundingClientRect().width > 0)
const isShorts = () => !!shortsPage()
const isRoot = () => (location.hash === '' || location.hash === '#/') && !isShorts()

const LEFT = 37
const ENTER = 13

// Back from Shorts is a single Escape: a third one in a row opens "Welcome back". A Short opened from a shelf or history returns
// to the previous screen; the Shorts tab opens the guide rail instead, so from there we go on to Home.
async function backFromShorts() {
    const railOpen = () => (document.querySelector('ytlr-guide-response')?.getBoundingClientRect().width ?? 0) > 200 // the collapsed rail is ~110 px wide and always there
    pressKey(BACK)
    for (let i = 0; i < 8 && isShorts() && !railOpen(); i++) await sleep(100)
    if (!railOpen()) return
    for (let i = 0; i < 8 && !document.activeElement?.closest('ytlr-guide-response'); i++) await sleep(100)
    pressKey(UP)
    await sleep(300)
    if (document.activeElement?.closest('ytlr-guide-entry-renderer')) pressKey(ENTER)
}

// A remote's Back sometimes only moves focus (e.g. to the search page's own back button); on touch it should leave the page.
async function back() {
    if (isShorts()) return backFromShorts()
    if (globalThis.__vtRole === 'player') return backFromPlayer()
    const from = location.hash
    for (let i = 0; i < 3 && location.hash === from && !isRoot(); i++) {
        pressKey(BACK)
        await sleep(300)
    }
}

// In the player page "back" hides the panels one by one, then asks the shell to close the player (Escape would leave to Leanback's home).
async function backFromPlayer() {
    // The page never reached the player (a dialog or toast instead of the video): there is nothing to hide, just close.
    if (!isWatch()) {
        window.webkit?.messageHandlers?.vtRoute?.postMessage({ type: 'close' })
        return
    }
    for (let i = 0; i < 4 && isWatch(); i++) {
        if (!overlayVisible() && !sidePanelOpen()) {
            window.webkit?.messageHandlers?.vtRoute?.postMessage({ type: 'close' })
            return
        }
        pressKey(BACK)
        await sleep(i === 0 && sidePanelOpen() ? 450 : 300)
    }
}

// `__vtOpenGen` changes when the shell opens another video: this leave is then over, its Escapes would hit the new one.
async function leavePlayer() {
    const gen = window.__vtOpenGen
    for (let i = 0; i < 3 && isWatch() && window.__vtOpenGen === gen; i++) {
        pressKey(BACK)
        await sleep(300)
    }
}

// The native drag (ShellView) awaits this: it resolves once the page has left the player, or after 1.5 s.
async function leavePlayerAndWait() {
    const gen = window.__vtOpenGen
    leavePlayer()
    for (let i = 0; i < 15 && isWatch() && window.__vtOpenGen === gen; i++) await sleep(100)
}

// Settings, its sub-menus, description and comments open in this stage and shrink the video to the left.
const sidePanelOpen = () => !!document.querySelector('yt-unified-overlay-stage ytlr-animated-overlay')

async function closeSidePanels() {
    // A panel takes ~370 ms to close and ignores Escape meanwhile.
    for (let i = 0; i < 3 && sidePanelOpen(); i++) {
        pressKey(BACK)
        await sleep(450)
    }
}

async function togglePause() {
    const p = player()
    if (!p) return
    if (sidePanelOpen()) {
        await closeSidePanels()
    } else if (overlayVisible()) {
        p.playVideo()
        pressKey(BACK)
    } else {
        p.pauseVideo()
        await sleep(100)
        if (!overlayVisible()) pressKey(UP)
    }
}

let hint = null
let hintTimer = null

function showSeekHint(seconds) {
    if (!hint) {
        hint = document.createElement('div')
        Object.assign(hint.style, {
            position: 'fixed', top: '50%', transform: 'translate(-50%, -50%)', zIndex: '9999',
            padding: '1.2rem 2rem', borderRadius: '3rem', background: 'rgba(0, 0, 0, 0.6)',
            color: 'white', font: '500 2rem Roboto, sans-serif', pointerEvents: 'none', transition: 'opacity 0.2s'
        })
    }
    hint.textContent = (seconds < 0 ? '−' : '+') + Math.abs(seconds) + ' с'
    hint.style.left = seconds < 0 ? '20%' : '80%'
    hint.style.opacity = '1'
    if (!hint.isConnected) document.body.appendChild(hint)
    clearTimeout(hintTimer)
    hintTimer = setTimeout(() => hint.style.opacity = '0', 600)
}

function seek(x) {
    const third = window.innerWidth / 3
    const seconds = x < third ? -SEEK_SECONDS : x > 2 * third ? SEEK_SECONDS : 0
    if (!seconds) return
    player()?.seekBy(seconds)
    showSeekHint(seconds)
}

function overlayButton(left, paths, onTap, visible) {
    const button = document.createElement('div')
    // innerHTML is blocked by the page's Trusted Types policy.
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    for (const [name, value] of Object.entries({ viewBox: '0 0 24 24', width: '24', height: '24', fill: 'none', stroke: 'white', 'stroke-width': '2.2', 'stroke-linecap': 'round', 'stroke-linejoin': 'round' })) {
        svg.setAttribute(name, value)
    }
    for (const attrs of paths) {
        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
        for (const [name, value] of Object.entries(attrs)) path.setAttribute(name, value)
        svg.appendChild(path)
    }
    button.appendChild(svg)
    Object.assign(button.style, {
        position: 'fixed', top: '10px', left, width: '44px', height: '44px', zIndex: '9999',
        display: 'none', alignItems: 'center', justifyContent: 'center',
        borderRadius: '50%', background: 'rgba(0, 0, 0, 0.5)'
    })

    for (const type of ['pointerdown', 'pointermove', 'pointerup', 'pointercancel', 'mousedown', 'mouseup', 'click']) {
        window.addEventListener(type, (e) => {
            if (e.target !== button && !button.contains(e.target)) return
            e.stopImmediatePropagation()
            // A default action would move focus to <body> and Leanback would lose its focused element.
            if ((type === 'pointerdown' || type === 'mousedown') && e.cancelable) e.preventDefault()
            if (type === 'pointerup') onTap()
        }, true)
    }
    window.addEventListener('touchstart', (e) => {
        if ((e.target === button || button.contains(e.target)) && e.cancelable) e.preventDefault()
    }, { capture: true, passive: false })

    // Leanback rebuilds <body> while booting, so re-attach whenever the button is gone.
    setInterval(() => {
        if (!button.isConnected && document.body) document.body.appendChild(button)
        button.style.display = visible() ? 'flex' : 'none'
    }, 250)
}

// WebKit pauses inline video when the app goes to the background; playback in PiP keeps going.
function togglePictureInPicture() {
    const video = document.querySelector('video')
    if (!video?.webkitSetPresentationMode) return
    video.webkitSetPresentationMode(video.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture')
}

// Vertical lists are virtual: Leanback renders a window of shelves around the focused one and fetches more only when focus
// reaches the last shelf. A finger scroll does not move focus, so at the bottom we walk focus down to the last rendered shelf.
function feedFollowsScroll() {
    const SELECTOR = 'ytlr-section-list-renderer > yt-virtual-list'
    let timer = null
    let busy = false

    async function follow(list) {
        const section = list.parentElement.__instance
        if (typeof section?.selectedIndex !== 'number') return
        if (list.scrollTop + list.clientHeight < list.scrollHeight - 200) return
        const rendered = [...list.querySelectorAll(':scope > div > div')]
            .map(item => +(/-item-(\d+)/.exec(item.firstElementChild?.className ?? '')?.[1] ?? -1))
        const last = Math.max(...rendered)
        busy = true
        for (let i = 0; i < 12 && section.selectedIndex < last; i++) {
            pressKey(DOWN)
            await sleep(80)
        }
        setTimeout(() => busy = false, 500)
    }

    document.addEventListener('scroll', (e) => {
        const list = e.target
        if (busy || !(list instanceof Element) || !list.matches(SELECTOR) || list.closest('ytlr-watch-default')) return
        clearTimeout(timer)
        timer = setTimeout(() => follow(list), 250)
    }, true)
}

const shortsVideo = () => shortsPage()?.querySelector('video') ?? document.querySelector('video')

function pauseIndicator() {
    const icon = document.createElement('div')
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    for (const [name, value] of Object.entries({ viewBox: '0 0 24 24', width: '48', height: '48', fill: 'white' })) svg.setAttribute(name, value)
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    path.setAttribute('d', 'M8 5v14l11-7z')
    svg.appendChild(path)
    icon.appendChild(svg)
    Object.assign(icon.style, {
        position: 'fixed', top: '50%', left: '50%', transform: 'translate(-50%, -50%)', width: '96px', height: '96px',
        borderRadius: '50%', background: 'rgba(0, 0, 0, 0.5)', display: 'none', alignItems: 'center', justifyContent: 'center',
        pointerEvents: 'none', zIndex: '9999'
    })

    let hiddenUntil = 0
    const update = () => {
        if (!icon.isConnected && document.body) document.body.appendChild(icon)
        const video = isShorts() ? shortsVideo() : null
        const rect = video?.getBoundingClientRect()
        const show = !!rect && rect.width > 0 && video.paused && !video.ended && Date.now() > hiddenUntil
        if (show) {
            icon.style.left = rect.left + rect.width / 2 + 'px'
            icon.style.top = rect.top + rect.height / 2 + 'px'
        }
        icon.style.display = show ? 'flex' : 'none'
    }
    for (const type of ['play', 'pause', 'playing', 'emptied']) document.addEventListener(type, update, true)
    setInterval(update, 250)
    return () => {
        hiddenUntil = Date.now() + 500
        icon.style.display = 'none'
    }
}

// Taking the touches ourselves keeps Shorts independent of Leanback's own touch handling; its handlers are muted so a swipe does not scroll twice.
function shortsGestures() {
    const hideIndicator = pauseIndicator()
    let start = null
    let swallow = false

    const owned = (e) => e.pointerType === 'touch' && isShorts() && !sidePanelOpen() &&
        !!shortsPage().contains(e.target) && !e.target.closest?.('yt-button-container, ytlr-button, button')

    const videoId = () => player()?.getVideoData?.().video_id

    // No rendered item sits above the current one while the first Short is showing.
    function isFirst() {
        const list = shortsPage().querySelector('yt-virtual-list')
        const items = [...shortsPage().querySelectorAll('yt-virtual-list > div > div')]
        if (!list || !items.length) return null
        const top = list.getBoundingClientRect().top
        return !items.some(item => top - item.getBoundingClientRect().top >= 10)
    }

    async function previous() {
        const first = isFirst()
        if (first) return back()
        const before = videoId()
        pressKey(UP)
        if (first === null) {
            await sleep(450)
            if (isShorts() && videoId() === before) back()
        }
    }

    function swipe(dy) {
        hideIndicator()
        if (document.activeElement?.closest('yt-button-container') && shortsPage().contains(document.activeElement)) pressKey(LEFT)
        if (dy < 0) pressKey(DOWN)
        else previous()
    }

    function tap() {
        const p = player()
        if (typeof p?.pauseVideo === 'function' && typeof p.playVideo === 'function') {
            const video = shortsVideo()
            if (video?.paused) p.playVideo()
            else p.pauseVideo()
            return
        }
        pressKey(LEFT)
        pressKey(ENTER)
    }

    window.addEventListener('pointerdown', (e) => {
        if (!owned(e)) {
            start = null
            swallow = false
            return
        }
        start = { x: e.clientX, y: e.clientY, id: e.pointerId }
        swallow = true
        e.stopPropagation()
    }, true)

    for (const type of ['pointermove', 'pointercancel', 'mousedown', 'mousemove', 'mouseup', 'click']) {
        window.addEventListener(type, (e) => {
            if (!swallow) return
            e.stopPropagation()
            if (type === 'pointercancel') start = null
        }, true)
    }

    window.addEventListener('pointerup', (e) => {
        if (!swallow) return
        e.stopPropagation()
        setTimeout(() => swallow = false, 400)
        if (!start || start.id !== e.pointerId) return

        const dx = e.clientX - start.x
        const dy = e.clientY - start.y
        start = null

        if (Math.abs(dy) > SWIPE_MIN && Math.abs(dy) > 2 * Math.abs(dx)) swipe(dy)
        else if (Math.abs(dx) <= TAP_SLOP && Math.abs(dy) <= TAP_SLOP) tap()
    }, true)

    window.addEventListener('touchend', (e) => {
        if (swallow && e.cancelable) e.preventDefault()
    }, { capture: true, passive: false })
}

// A tap on the next video's preview or title on "UP NEXT" only moves Leanback's focus to the block; the first Enter then
// goes to the play button and the second one opens the video, so the tap does both.
function endScreenTaps() {
    const AUTOPLAY = 'ytlr-player-overlay-autoplay-renderer'
    let busy = false

    async function playNext(block) {
        busy = true
        for (let i = 0; i < 3 && block.isConnected && isWatch(); i++) {
            const onButton = !!document.activeElement?.closest(`${AUTOPLAY} yt-button-container`)
            pressKey(ENTER)
            if (onButton) break
            await sleep(150)
        }
        busy = false
    }

    window.addEventListener('pointerup', (e) => {
        if (busy || e.pointerType !== 'touch' || !isWatch()) return
        const block = e.target.closest?.(AUTOPLAY)
        if (!block || e.target.closest('ytlr-button, yt-button-container, button')) return
        setTimeout(() => playNext(block), 100)
    }, true)
}

// The native side follows the finger on a swipe down; it needs to know the state of the page and whether the touch is ours.
let touchOwned = false
let postedState = ''

function postState() {
    const handler = window.webkit?.messageHandlers?.vtState
    if (!handler) return
    const state = { watch: isWatch(), shorts: isShorts(), sidePanel: sidePanelOpen(), canBack: playerOpened() || (globalThis.__vtRole !== 'player' && !isRoot()), touchOwned }
    const key = JSON.stringify(state)
    if (key === postedState) return
    postedState = key
    handler.postMessage(state)
}

function stateReporting() {
    window.addEventListener('hashchange', postState)
    document.addEventListener('focusin', postState, true)
    setInterval(postState, 250)
    postState()
}

function playerGestures() {
    let start = null
    let swallow = false
    let lastTap = null
    let seeking = 0
    let singleTimer = null

    const owned = (e) => e.pointerType === 'touch' && isWatch() &&
        !!e.target.closest?.('ytlr-watch-default') && !e.target.closest(INTERACTIVE)

    const setTouchOwned = (value) => {
        touchOwned = value
        postState()
    }

    window.addEventListener('pointerdown', (e) => {
        if (!owned(e)) {
            start = null
            swallow = false
            setTouchOwned(false)
            return
        }
        start = { x: e.clientX, y: e.clientY, id: e.pointerId }
        swallow = true
        setTouchOwned(true)
        e.stopPropagation()
    }, true)

    for (const type of ['pointermove', 'pointercancel', 'mousedown', 'mousemove', 'mouseup', 'click']) {
        window.addEventListener(type, (e) => {
            if (type === 'pointercancel') setTouchOwned(false)
            if (!swallow) return
            e.stopPropagation()
            if (type === 'pointercancel') start = null
        }, true)
    }

    window.addEventListener('pointerup', (e) => {
        setTouchOwned(false)
        if (!swallow) return
        e.stopPropagation()
        setTimeout(() => swallow = false, 400)
        if (!start || start.id !== e.pointerId) return

        const dx = e.clientX - start.x
        const dy = e.clientY - start.y
        start = null

        if (Math.abs(dy) > SWIPE_MIN && Math.abs(dy) > 2 * Math.abs(dx)) {
            clearTimeout(singleTimer)
            lastTap = null
            // With the native drag the shell follows the finger and asks for the exit itself.
            if (dy > 0 && window.__vtNativeDrag !== true) leavePlayer()
            return
        }
        if (Math.abs(dx) > TAP_SLOP || Math.abs(dy) > TAP_SLOP) return

        const now = Date.now()
        if (now < seeking) {
            seeking = now + DOUBLE_TAP_MS * 2
            seek(e.clientX)
            return
        }
        if (lastTap && now - lastTap.t < DOUBLE_TAP_MS && Math.abs(e.clientX - lastTap.x) < 200) {
            clearTimeout(singleTimer)
            lastTap = null
            seeking = now + DOUBLE_TAP_MS * 2
            seek(e.clientX)
            return
        }
        lastTap = { t: now, x: e.clientX }
        clearTimeout(singleTimer)
        singleTimer = setTimeout(() => {
            lastTap = null
            togglePause()
        }, DOUBLE_TAP_MS)
    }, true)

    window.addEventListener('touchend', (e) => {
        if (swallow && e.cancelable) e.preventDefault()
    }, { capture: true, passive: false })
}

module.exports = () => {
    if (window.top !== window) return

    css.inject('vt-touch', `
        html { -webkit-user-select: none; -webkit-touch-callout: none; }
        ytlr-tile-header-renderer::after, yt-lockup-view-model thumbnail::after { display: none !important; }
        ytlr-watch-default ytlr-pivot { display: none !important; }
        ytlr-squeezeback-player-overlay yt-focus-container:has(ytlr-progress-bar) { top: auto !important; bottom: 2rem !important; }
    `)

    window.__vtBack = back
    window.__vtLeavePlayer = leavePlayerAndWait
    // The native side shrinks the player into a corner: our buttons go away and an open panel is hidden (one Escape; more would leave).
    window.__vtMinimized = async (mini) => {
        window.__vtMini = mini
        if (!mini || !isWatch()) return
        if (sidePanelOpen()) await closeSidePanels()
        else if (overlayVisible()) pressKey(BACK)
    }

    if (document.head) disableZoom()
    else document.addEventListener('DOMContentLoaded', disableZoom, { once: true })

    overlayButton('10px', [{ d: 'M15 5l-7 7 7 7' }], back, () => !window.__vtMini && ((isWatch() && overlayVisible()) || isShorts() || (playerOpened() && !isWatch())))
    overlayButton('64px', [{ d: 'M21 11V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h5' }, { d: 'M14 14h7v6h-7z', fill: 'white' }], togglePictureInPicture, () => !window.__vtMini && isWatch() && overlayVisible())
    feedFollowsScroll()
    endScreenTaps()
    playerGestures()
    shortsGestures()
    stateReporting()
}
