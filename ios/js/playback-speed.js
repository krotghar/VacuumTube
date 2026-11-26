// Leanback forgets the playback speed for every new video. Remember what the user picked in the player settings
// and apply it to regular videos (#/watch); Shorts and home previews stay at 1x.
const KEY = 'vt.playbackRate'
const MIN_RATE = 0.25
const MAX_RATE = 2
const OWN_CHANGE_MS = 1000
const VERIFY_MS = 3000
const MAX_RETRIES = 2

const clamp = (rate) => Math.min(MAX_RATE, Math.max(MIN_RATE, rate))
const isWatch = () => location.hash.startsWith('#/watch')
const player = () => document.querySelector('.html5-video-player')
// Settings, its sub-menus and the speed list open in this stage.
const settingsOpen = () => !!document.querySelector('yt-unified-overlay-stage ytlr-animated-overlay')

function savedRate() {
    try {
        const rate = parseFloat(localStorage.getItem(KEY))
        return Number.isFinite(rate) ? clamp(rate) : null
    } catch (e) {
        return null
    }
}

function saveRate(rate) {
    try {
        localStorage.setItem(KEY, String(rate))
    } catch (e) {}
}

module.exports = () => {
    if (window.top !== window) return

    let appliedFor = null
    let ownChangeAt = 0

    function apply(retries) {
        const p = player()
        const saved = savedRate()
        if (!p || saved === null || !isWatch() || p.getVideoData?.().isLive) return
        if (Math.abs(p.getPlaybackRate() - saved) > 0.001) {
            ownChangeAt = Date.now()
            try {
                p.setPlaybackRate(saved)
            } catch (e) {
                return
            }
        }
        if (retries < MAX_RETRIES) {
            const id = appliedFor
            setTimeout(() => {
                const current = player()
                if (appliedFor !== id || !current || !isWatch()) return
                if (Math.abs(current.getPlaybackRate() - saved) > 0.001 && savedRate() === saved) apply(retries + 1)
            }, VERIFY_MS)
        }
    }

    // Leanback reuses one <video>, so a speed set on a regular video would leak into previews and Shorts.
    function resetOutsideWatch() {
        const p = player()
        if (!p || p.getPlaybackRate() === 1) return
        ownChangeAt = Date.now()
        try {
            p.setPlaybackRate(1)
        } catch (e) {}
    }

    document.addEventListener('playing', () => {
        if (!isWatch()) {
            appliedFor = null
            if (savedRate() !== null) resetOutsideWatch()
            return
        }
        const id = player()?.getVideoData?.().video_id
        if (!id || id === appliedFor) return
        appliedFor = id
        apply(0)
    }, true)

    document.addEventListener('emptied', () => {
        appliedFor = null
    }, true)

    document.addEventListener('ratechange', () => {
        if (!isWatch() || !settingsOpen() || Date.now() - ownChangeAt < OWN_CHANGE_MS) return
        const rate = player()?.getPlaybackRate?.()
        if (typeof rate === 'number' && rate > 0) saveRate(clamp(rate))
    }, true)
}
