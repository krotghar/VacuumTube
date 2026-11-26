module.exports = {
    readFileSync(p) {
        if (String(p).endsWith('style.css')) {
            return require('../../../src/preload/style.css')
        }
        throw new Error('fs shim: ' + p)
    }
}
