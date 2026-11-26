// AV1 decodes in hardware on M-series iPads; the simulator overrides this in LeanbackView.swift.
module.exports = {
    touch_overlay: false,
    h264ify: true,
    h264ify_disable_av1: false,
    h264ify_disable_webm: false,
    h264ify_disable_vp8: false,
    h264ify_disable_vp9: false
}
