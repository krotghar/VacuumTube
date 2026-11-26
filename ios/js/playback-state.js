module.exports = () => {
    let lastPlaying = null

    const report = (playing) => {
        if (playing === lastPlaying) return
        lastPlaying = playing
        try {
            window.webkit?.messageHandlers?.vtPlayback?.postMessage(playing)
        } catch (e) {}
    }

    const update = () => {
        report([...document.querySelectorAll('video')].some(v => !v.paused && !v.ended))
    }

    for (const type of ['playing', 'pause', 'ended', 'emptied']) {
        document.addEventListener(type, update, true)
    }
    window.addEventListener('pagehide', () => report(false))
}
