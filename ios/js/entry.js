// Counterpart of src/preload/index.js with an explicit module list (esbuild cannot bundle the dynamic require).
if (location.host === 'www.youtube.com' && location.pathname === '/tv') {
    const modules = [
        require('../../src/preload/modules/css'),
        require('../../src/preload/modules/h264ify'),
        require('../../src/preload/modules/media-capabilities'),
        require('../../src/preload/modules/touch-support'),
        require('./touch'),
        require('./playback-state'),
        require('./fill-4x3')
    ]

    for (const module of modules) {
        try {
            module()
        } catch (err) {
            console.error('a module experienced failure while loading', err)
        }
    }
}
