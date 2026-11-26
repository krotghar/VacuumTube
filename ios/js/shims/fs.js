// __VT_LOCALES__ is defined by build-js.mjs: the file names in locale/.
module.exports = {
    readFileSync(p) {
        if (String(p).endsWith('style.css')) {
            return require('../../../src/preload/style.css')
        }
        throw new Error('fs shim: ' + p)
    },
    promises: {
        async readdir(p) {
            if (String(p) === '/locale') return __VT_LOCALES__
            throw new Error('fs shim: ' + p)
        },
        async readFile(p) {
            const name = /^\/locale\/(.+)\.json$/.exec(String(p))?.[1]
            if (!name || !__VT_LOCALES__.includes(name + '.json')) throw new Error('fs shim: ' + p)
            return JSON.stringify(require(`../../../locale/${name}.json`))
        }
    }
}
