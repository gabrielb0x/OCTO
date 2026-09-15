import Foundation

/// Removes the tracking parameters that sites and ChatGPT add to links, such as
/// `utm_source=chatgpt.com` on web search sources, so opening, copying or sharing a link doesn't
/// tell the site where it came from.
public enum LinkCleaner {
    static let trackingNames: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "igshid", "igsh", "li_fat_id", "mc_cid", "mc_eid", "mkt_tok", "_ga", "_gl", "gad_source",
        "gad_campaignid", "srsltid", "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp", "hsctatracking",
        "ref_src", "ref_url", "wickedid", "rb_clickid", "s_cid", "oly_anon_id", "oly_enc_id", "vero_id",
        "vero_conv", "_openstat", "ncid", "ocid", "cmpid", "zanpid", "spm", "trk", "trkcampaign", "sc_cid",
        "at_medium", "at_campaign", "epik", "__s", "ss_source", "ss_campaign_id", "_bta_tid", "_bta_c",
    ]
    static let trackingPrefixes = ["utm_", "pk_", "mtm_", "hsa_", "matomo_"]
    /// Sites where `si` identifies who shared the link.
    static let shareIdentifierHosts = ["youtube.com", "youtu.be", "spotify.com"]

    public static func isTracking(_ name: String, host: String?) -> Bool {
        let name = name.lowercased()
        if trackingNames.contains(name) || trackingPrefixes.contains(where: { name.hasPrefix($0) }) {
            return true
        }
        guard name == "si", let host = host?.lowercased() else { return false }
        return shareIdentifierHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The link without its tracking parameters. Other links, such as `mailto:`, are left alone.
    public static func clean(_ url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems, !items.isEmpty
        else { return url }
        let kept = items.filter { !isTracking($0.name.removingPercentEncoding ?? $0.name, host: components.host) }
        guard kept.count < items.count else { return url }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }

    /// Every web link of a text cleaned, for copying and sharing a reply.
    public static func cleanLinks(in text: String) -> String {
        guard text.contains("http"), text.contains("?") else { return text }
        return text.replacing(#/https?:\/\/[^\s<>"'`()\[\]]+/#) { match in
            var link = String(match.output)
            // Punctuation ending a sentence isn't part of the link.
            var ending = ""
            while let last = link.last, ".,;:!?".contains(last) {
                ending = String(last) + ending
                link.removeLast()
            }
            guard let url = URL(string: link) else { return String(match.output) }
            return clean(url).absoluteString + ending
        }
    }
}
