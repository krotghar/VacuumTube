// AV1 decodes in hardware on M-series iPads; the simulator overrides this in LeanbackView.swift.
module.exports = {
    adblock: true,
    sponsorblock: true,
    sponsorblock_skip_sponsor: true,
    sponsorblock_skip_selfpromo: false,
    sponsorblock_skip_interaction: false,
    sponsorblock_skip_intro: false,
    sponsorblock_skip_outro: false,
    sponsorblock_skip_preview: false,
    sponsorblock_skip_hook: false,
    sponsorblock_skip_filler: false,
    touch_overlay: false,
    h264ify: true,
    h264ify_disable_av1: false,
    h264ify_disable_webm: false,
    h264ify_disable_vp8: false,
    h264ify_disable_vp9: false
}
