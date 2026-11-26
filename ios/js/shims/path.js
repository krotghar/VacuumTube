module.exports = {
    join(...parts) {
        const out = []
        for (const segment of parts.join('/').split('/')) {
            if (segment === '' || segment === '.') continue
            if (segment === '..') out.pop()
            else out.push(segment)
        }
        return '/' + out.join('/')
    }
}
