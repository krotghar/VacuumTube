import WebKit

// Leanback's CSP (connect-src) blocks sponsor.ajay.app, so sponsorblock.js fetches through the app (ios/js/sponsor-fetch.js).
@MainActor
final class SponsorFetch: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let string = message.body as? String, let url = URL(string: string),
              url.scheme == "https", url.host == "sponsor.ajay.app" else { return (nil, "vtFetch: URL not allowed") }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (["status": status, "body": String(decoding: data, as: UTF8.self)], nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}
