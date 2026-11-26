// connect-src of the Leanback CSP has no sponsor.ajay.app, so these requests go through the app (vtFetch in LeanbackView.swift).
const PREFIX = 'https://sponsor.ajay.app/'

module.exports = () => {
    const bridge = window.webkit?.messageHandlers?.vtFetch
    if (!bridge) return

    const nativeFetch = window.fetch
    window.fetch = function (input, init) {
        const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input?.url
        if (!url?.startsWith(PREFIX)) return nativeFetch.apply(this, arguments)
        return bridge.postMessage(url).then(({ status, body }) => new Response(body, { status }))
    }
}
