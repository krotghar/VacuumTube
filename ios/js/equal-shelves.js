// The server marks every shelf with tvhtml5Style.effects.enlarge, which makes Leanback blow up the shelf in focus
// (and relayout everything while scrolling). Without the flag all shelves keep the regular size.
const jsonModifiers = require('../../src/preload/util/jsonModifiers')

const MAX_DEPTH = 40

function stripEnlarge(node, depth = 0) {
    if (!node || typeof node !== 'object' || depth > MAX_DEPTH) return
    if (Array.isArray(node)) {
        for (const item of node) stripEnlarge(item, depth + 1)
        return
    }
    const effects = node.shelfRenderer?.tvhtml5Style?.effects
    if (effects && 'enlarge' in effects) {
        delete effects.enlarge
        window.__vtEnlargeStripped++
    }
    for (const key in node) stripEnlarge(node[key], depth + 1)
}

module.exports = () => {
    if (window.top !== window) return

    window.__vtEnlargeStripped = 0
    jsonModifiers.addModifier((json) => {
        if (json.contents || json.continuationContents || json.onResponseReceivedActions) stripEnlarge(json)
        return json
    })
}
