// Leanback is laid out on an 80x45 rem canvas; on 4:3 screens turn every 45rem height into 100vh.
module.exports = () => {
    if (window.top !== window) return

    const fill = new CSSStyleSheet()
    fill.replaceSync(`
ytlr-tv-surface-content-renderer, ytlr-section-list-renderer { height: auto !important; max-height: none !important; }
ytlr-section-list-renderer > yt-virtual-list { height: calc(100vh - 6.75rem) !important; }
`)

    const done = new Set()
    let lastCount = -1

    function scan() {
        const sheets = [...document.styleSheets, ...document.adoptedStyleSheets.filter(s => s !== fill)]
        let count = 0
        for (const s of sheets) {
            try { count += s.cssRules.length } catch (e) {}
        }
        if (count !== lastCount) {
            lastCount = count
            for (const s of sheets) {
                let rules
                try { rules = s.cssRules } catch (e) { continue }
                for (const r of rules) {
                    if (r.selectorText && r.style && r.style.height === '45rem' && !done.has(r.selectorText)) {
                        done.add(r.selectorText)
                        fill.insertRule(`${r.selectorText}{height:100vh !important}`, fill.cssRules.length)
                    }
                }
            }
        }
        const adopted = document.adoptedStyleSheets
        if (adopted[adopted.length - 1] !== fill) {
            document.adoptedStyleSheets = [...adopted.filter(s => s !== fill), fill]
        }
    }

    scan()
    setInterval(scan, 1000)
}
