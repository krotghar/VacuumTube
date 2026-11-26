// Replaces src/preload/util/css.js: <style> injected from a WKUserScript is blocked by the page CSP, adoptedStyleSheets are not.
const sheets = {}
let timer = null

function apply() {
    const own = Object.values(sheets)
    const adopted = document.adoptedStyleSheets
    const inPlace = own.length === 0 || own.every((s, i) => adopted[adopted.length - own.length + i] === s)
    if (inPlace) return
    document.adoptedStyleSheets = [...adopted.filter(s => !own.includes(s)), ...own]
}

function inject(id, text) {
    let sheet = sheets[id]
    if (!sheet) {
        sheet = sheets[id] = new CSSStyleSheet()
    }
    sheet.replaceSync(text)
    apply()
    if (!timer) timer = setInterval(apply, 1000)
}

function remove(id) {
    const sheet = sheets[id]
    if (!sheet) return
    delete sheets[id]
    document.adoptedStyleSheets = document.adoptedStyleSheets.filter(s => s !== sheet)
}

module.exports = {
    inject,
    delete: remove
}
