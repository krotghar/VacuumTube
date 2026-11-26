// Touch gestures on top of Leanback's enable_touch_support (taps and list scrolling stay with Leanback).
const css = require('./shims/css')

const BACK = 27
const UP = 38
const DOWN = 40

const TAP_SLOP = 20
const SWIPE_MIN = 80
const DOUBLE_TAP_MS = 280
const SEEK_SECONDS = 10

const INTERACTIVE = 'yt-button-container, ytlr-button, ytlr-progress-bar, ytlr-tile-renderer, yt-lockup-view-model, button'

const sleep = (ms) => new Promise(r => setTimeout(r, ms))

function pressKey(keyCode) {
    for (const type of ['keydown', 'keyup']) {
        const event = new Event(type)
        event.keyCode = keyCode
        document.dispatchEvent(event)
    }
}

const isWatch = () => location.hash.startsWith('#/watch')
const player = () => document.querySelector('.html5-video-player')

function overlayVisible() {
    const active = document.activeElement
    return !!active && active.tagName !== 'YT-FOCUS-CONTAINER' && !!active.closest('ytlr-squeezeback-player-overlay')
}

function disableZoom() {
    const meta = document.createElement('meta')
    meta.name = 'viewport'
    meta.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no'
    document.head.appendChild(meta)
}

const isRoot = () => location.hash === '' || location.hash === '#/'

// A remote's Back sometimes only moves focus (e.g. to the search page's own back button); on touch it should leave the page.
async function back() {
    const from = location.hash
    for (let i = 0; i < 3 && location.hash === from && !isRoot(); i++) {
        pressKey(BACK)
        await sleep(300)
    }
}

async function leavePlayer() {
    for (let i = 0; i < 3 && isWatch(); i++) {
        pressKey(BACK)
        await sleep(300)
    }
}

async function togglePause() {
    const p = player()
    if (!p) return
    if (overlayVisible()) {
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

// Vertical lists are virtual: Leanback renders a window of shelves around the focused one and fetches more only when focus
// reaches the last shelf. A finger scroll does not move focus, so at the bottom we walk focus down to the last rendered shelf.
function backButton() {
    const button = document.createElement('div')
    // innerHTML is blocked by the page's Trusted Types policy.
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    for (const [name, value] of Object.entries({ viewBox: '0 0 24 24', width: '24', height: '24', fill: 'none', stroke: 'white', 'stroke-width': '2.2', 'stroke-linecap': 'round', 'stroke-linejoin': 'round' })) {
        svg.setAttribute(name, value)
    }
    path.setAttribute('d', 'M15 5l-7 7 7 7')
    svg.appendChild(path)
    button.appendChild(svg)
    Object.assign(button.style, {
        position: 'fixed', top: '10px', left: '10px', width: '44px', height: '44px', zIndex: '9999',
        display: 'none', alignItems: 'center', justifyContent: 'center',
        borderRadius: '50%', background: 'rgba(0, 0, 0, 0.5)'
    })

    for (const type of ['pointerdown', 'pointermove', 'pointerup', 'pointercancel', 'mousedown', 'mouseup', 'click']) {
        window.addEventListener(type, (e) => {
            if (e.target !== button && !button.contains(e.target)) return
            e.stopImmediatePropagation()
            if (type === 'pointerup') back()
        }, true)
    }

    // Leanback rebuilds <body> while booting, so re-attach whenever the button is gone.
    setInterval(() => {
        if (!button.isConnected && document.body) document.body.appendChild(button)
        button.style.display = isWatch() && overlayVisible() ? 'flex' : 'none'
    }, 250)
}

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

function playerGestures() {
    let start = null
    let swallow = false
    let lastTap = null
    let seeking = 0
    let singleTimer = null

    const owned = (e) => e.pointerType === 'touch' && isWatch() &&
        !!e.target.closest?.('ytlr-watch-default') && !e.target.closest(INTERACTIVE)

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

        if (Math.abs(dy) > SWIPE_MIN && Math.abs(dy) > 2 * Math.abs(dx)) {
            clearTimeout(singleTimer)
            lastTap = null
            if (dy > 0) leavePlayer()
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

    if (document.head) disableZoom()
    else document.addEventListener('DOMContentLoaded', disableZoom, { once: true })

    backButton()
    feedFollowsScroll()
    playerGestures()
}
