// Leanback starts the next video by itself a few seconds after the end. The end screen ("UP NEXT") needs a tap instead.
// The account setting stays untouched (it is shared with the user's TVs): only the watch-next response is adjusted, and
// the client follows isAutoplayEnabled from it.
const jsonModifiers = require('../../src/preload/util/jsonModifiers')

// For some videos the server answers as if autoplay were on: no "UP NEXT" / "Replay" overlay data, only the autoplay sets.
// The end screen is rebuilt from those sets, the same way the server builds it for the other videos.
function addEndScreen(overlay, autoplay) {
    const set = autoplay?.sets?.find(item => item.mode === 'NORMAL') ?? autoplay?.sets?.[0]
    const endpoint = set?.autoplayVideoRenderer?.autonavEndpointRenderer?.endpoint
    const preview = set?.nextVideoRenderer?.maybeHistoryEndpointRenderer?.item?.previewButtonRenderer
    if (!overlay.autoplay && endpoint?.watchEndpoint && preview) {
        overlay.autoplay = {
            playerOverlayAutoplayRenderer: {
                title: autoplay.title,
                videoTitle: preview.title,
                byline: preview.byline,
                cancelText: { simpleText: 'Cancel' },
                pauseText: { simpleText: 'Auto-play is paused' },
                background: preview.thumbnail,
                countDownSecs: autoplay.countDownSecs,
                nextButton: {
                    buttonRenderer: {
                        isDisabled: false,
                        icon: { iconType: 'PLAYING' },
                        navigationEndpoint: endpoint,
                        accessibility: { label: 'Play next video' },
                        accessibilityData: { accessibilityData: { label: 'Play next video' } }
                    }
                },
                preferImmediateRedirect: false,
                videoId: endpoint.watchEndpoint.videoId
            }
        }
    }

    const replay = autoplay?.replayVideoRenderer?.pivotVideoRenderer
    if (!overlay.replay && replay?.navigationEndpoint) {
        overlay.replay = {
            playerOverlayReplayRenderer: {
                background: replay.thumbnail,
                overlayIcon: replay.overlayIcon,
                overlayLabel: replay.overlayLabel,
                navigationEndpoint: replay.navigationEndpoint,
                shortBylineText: replay.shortBylineText,
                title: replay.title
            }
        }
    }
}

module.exports = () => {
    if (window.top !== window) return

    jsonModifiers.addModifier((json) => {
        const overlay = json.playerOverlays?.playerOverlayRenderer
        if (!overlay) return json
        overlay.isAutoplayEnabled = false
        if (Array.isArray(overlay.timelyActionRenderers)) {
            overlay.timelyActionRenderers = overlay.timelyActionRenderers.filter(item => !JSON.stringify(item).includes('upNextCountdownViewModel'))
        }
        addEndScreen(overlay, json.contents?.singleColumnWatchNextResults?.autoplay?.autoplay)
        return json
    })
}
