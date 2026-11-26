// Same effect as src/preload/modules/touch-support.js + util/configOverrides.js:
// merge { flags: { enable_touch_support: true } } into window.environment when Leanback sets it.
(() => {
    const override = { flags: { enable_touch_support: true } }
    const merge = (target, source) => {
        for (const [key, value] of Object.entries(source)) {
            if (value && typeof value === 'object' && !Array.isArray(value)) {
                if (!target[key] || typeof target[key] !== 'object') target[key] = {}
                merge(target[key], value)
            } else {
                target[key] = value
            }
        }
    }
    let environment
    Object.defineProperty(window, 'environment', {
        configurable: true,
        get() { return environment },
        set(value) {
            try { merge(value, override) } catch (e) { window.__vtLog?.('error', 'touch-flag merge ' + e) }
            environment = value
            window.__vtLog?.('touch-flag', JSON.stringify(value?.flags ?? null).slice(0, 300))
        }
    })
})();
