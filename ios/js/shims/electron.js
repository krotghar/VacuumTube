const defaults = require('../defaults')

const currentConfig = () => ({ ...defaults, ...(globalThis.__vtConfigOverrides || {}) })

const ipcRenderer = {
    sendSync(channel, payload) {
        if (channel === 'get-config') return currentConfig()
        if (channel === 'set-config') return { ...currentConfig(), ...payload }
        return undefined
    },
    on() {},
    once() {},
    removeListener() {},
    send() {},
    invoke() {
        return Promise.resolve(undefined)
    }
}

module.exports = { ipcRenderer }
