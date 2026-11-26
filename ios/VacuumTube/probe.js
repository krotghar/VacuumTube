// Phase 0 diagnostics: environment, media capabilities, input events and focus, reported to native via the `vt` handler.
(() => {
    const post = (type, data) => {
        try { window.webkit.messageHandlers.vt.postMessage(type + ' ' + (typeof data === 'string' ? data : JSON.stringify(data))) } catch (e) {}
    }
    window.__vtLog = post

    const describe = (el) => {
        if (!el || !el.tagName) return String(el)
        let s = el.tagName.toLowerCase()
        if (el.id) s += '#' + el.id
        if (typeof el.className === 'string' && el.className.trim()) s += '.' + el.className.trim().split(/\s+/).slice(0, 3).join('.')
        const label = el.getAttribute('aria-label') || (el.textContent || '').trim().slice(0, 30)
        if (label) s += ' "' + label.replace(/\s+/g, ' ') + '"'
        return s
    }
    window.__vtDescribe = describe

    const codecs = {
        'h264': 'video/mp4; codecs="avc1.640028"',
        'vp9': 'video/webm; codecs="vp9"',
        'vp9.2': 'video/webm; codecs="vp09.02.51.10.01.09.16.09.00"',
        'av1': 'video/mp4; codecs="av01.0.08M.08"',
        'av1-10bit': 'video/mp4; codecs="av01.0.12M.10.0.110.09.16.09.0"',
        'aac': 'audio/mp4; codecs="mp4a.40.2"',
        'opus': 'audio/webm; codecs="opus"',
    }
    const support = (MS) => {
        if (!MS) return null
        const out = {}
        for (const [name, type] of Object.entries(codecs)) out[name] = MS.isTypeSupported(type)
        return out
    }

    window.__vtEnv = () => ({
        href: location.href,
        ua: navigator.userAgent,
        uaData: navigator.userAgentData ? JSON.stringify(navigator.userAgentData) : null,
        screen: [screen.width, screen.height, devicePixelRatio],
        viewport: [innerWidth, innerHeight],
        maxTouchPoints: navigator.maxTouchPoints,
        MediaSource: support(window.MediaSource),
        ManagedMediaSource: support(window.ManagedMediaSource),
        eme: typeof navigator.requestMediaKeySystemAccess,
    })

    window.addEventListener('DOMContentLoaded', () => post('env', window.__vtEnv()))
    window.addEventListener('error', (e) => post('error', e.message + ' @ ' + e.filename + ':' + e.lineno))
    window.addEventListener('unhandledrejection', (e) => post('rejection', String(e.reason).slice(0, 300)))

    const inputTypes = ['pointerdown', 'pointerup', 'click', 'touchstart', 'touchend', 'keydown', 'keyup']
    for (const type of inputTypes) {
        window.addEventListener(type, (e) => {
            const info = {
                target: describe(e.target),
                pointerType: e.pointerType,
                key: e.key,
                keyCode: e.keyCode,
                trusted: e.isTrusted,
            }
            post('input.' + type, info)
            setTimeout(() => post('focus.after.' + type, describe(document.activeElement)), 50)
        }, true)
    }

    window.addEventListener('focusin', (e) => post('focusin', describe(e.target)), true)

    let lastScroll = 0
    window.addEventListener('scroll', (e) => {
        const now = Date.now()
        if (now - lastScroll < 500) return
        lastScroll = now
        const t = e.target === document ? document.scrollingElement : e.target
        post('scroll', describe(t) + ' top=' + t.scrollTop + ' left=' + t.scrollLeft)
    }, true)

    const mediaEvents = ['loadedmetadata', 'playing', 'pause', 'waiting', 'error', 'ended', 'resize']
    for (const type of mediaEvents) {
        document.addEventListener(type, (e) => {
            const v = e.target
            if (!(v instanceof HTMLMediaElement)) return
            post('media.' + type, {
                src: (v.currentSrc || v.src || '').slice(0, 80),
                size: [v.videoWidth, v.videoHeight],
                time: v.currentTime,
                error: v.error ? v.error.code + ' ' + v.error.message : null,
            })
        }, true)
    }
})();
