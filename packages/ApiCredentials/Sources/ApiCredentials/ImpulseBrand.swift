import Foundation


public enum ImpulseBrand {
    public static let displayName: String = "ImpulseM"


    public static let displayNameBeta: String = "ImpulseM Beta"


    /// Transport base URL (IMPULSEM_RPC_URL). nil when the build does not configure one.
    public static let rpcUrl: String? = ImpulseBrand.normalizedBaseUrl(ImpulseBrand.buildSetting("IMPULSEM_RPC_URL"))


    /// Share and deep-link host (IMPULSEM_LINK_HOST), for example `o.example.org`. nil when not configured.
    public static let linkHost: String? = ImpulseBrand.normalizedLinkHost(ImpulseBrand.buildSetting("IMPULSEM_LINK_HOST"))


    /// Website base URL (IMPULSEM_SITE_URL). nil when not configured; site links are then hidden or shown as plain text.
    public static let siteUrl: String? = ImpulseBrand.normalizedBaseUrl(ImpulseBrand.buildSetting("IMPULSEM_SITE_URL"))


    /// Base URL of the macOS update feeds (IMPULSEM_MACOS_FEED_URL). nil disables the updater.
    public static let macosFeedUrl: String? = ImpulseBrand.normalizedBaseUrl(ImpulseBrand.buildSetting("IMPULSEM_MACOS_FEED_URL"))


    public static let apiId: Int32 = 4


    public static let teamIdPlaceholder: String = "TEAM_ID_PLACEHOLDER"


    public static let groupPrefixPlaceholder: String = "GROUP_PREFIX_PLACEHOLDER"


    /// Placeholder that localised strings use for the configured website, for example `[Terms]({IMPULSEM_SITE_URL}/tos)`.
    private static let siteToken: String = "{IMPULSEM_SITE_URL}"


    /// `[label]({IMPULSEM_SITE_URL}/path)`: a Markdown link to the site.
    private static let markdownSiteLinkExpression: NSRegularExpression = try! NSRegularExpression(pattern: "\\[([^\\]]*)\\]\\(\\{IMPULSEM_SITE_URL\\}([^)]*)\\)", options: [])


    /// `{IMPULSEM_SITE_URL}/path` on its own: a bare URL.
    private static let bareSiteUrlExpression: NSRegularExpression = try! NSRegularExpression(pattern: "\\{IMPULSEM_SITE_URL\\}(\\S*)", options: [])


    public static func buildSetting(_ key: String, in info: [String: Any]? = Bundle.main.infoDictionary) -> String? {
        guard let rawValue = info?[key] as? String else {
            return nil
        }
        let value: String = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value.hasPrefix("$(") {
            return nil
        }
        return value
    }


    /// Host for share and deep links: trimmed, lowercased, without a scheme and trailing slashes. nil when empty.
    public static func normalizedLinkHost(_ value: String?) -> String? {
        guard let value: String = value else {
            return nil
        }
        var host: String = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme: String in ["https://", "http://"] {
            if host.hasPrefix(scheme) {
                host = String(host.dropFirst(scheme.count))
                break
            }
        }
        host = ImpulseBrand.trimmingTrailingSlashes(host)
        return host.isEmpty ? nil : host
    }


    /// Base URL without surrounding whitespace and trailing slashes. nil when empty.
    public static func normalizedBaseUrl(_ value: String?) -> String? {
        guard let value: String = value else {
            return nil
        }
        let trimmed: String = ImpulseBrand.trimmingTrailingSlashes(value.trimmingCharacters(in: .whitespacesAndNewlines))
        return trimmed.isEmpty ? nil : trimmed
    }


    /// Link on the configured website for a path such as `/privacy`. nil when no site is configured.
    public static func siteLink(path: String, siteUrl: String? = ImpulseBrand.siteUrl) -> String? {
        guard let base: String = siteUrl else {
            return nil
        }
        return base + (path.hasPrefix("/") ? path : "/" + path)
    }


    /// Resolves `{IMPULSEM_SITE_URL}` in a localised string. With a site, `[label]({IMPULSEM_SITE_URL}/path)` becomes a
    /// link to it and a bare `{IMPULSEM_SITE_URL}/path` becomes the URL. Without a site, the link keeps only its label
    /// and a bare URL becomes an empty string, so the caller can hide it.
    public static func resolveSiteLinks(in text: String, siteUrl: String? = ImpulseBrand.siteUrl) -> String {
        guard text.contains(ImpulseBrand.siteToken) else {
            return text
        }
        let linkTemplate: String
        let bareTemplate: String
        if let base: String = siteUrl {
            let escapedBase: String = NSRegularExpression.escapedTemplate(for: base)
            linkTemplate = "[$1](" + escapedBase + "$2)"
            bareTemplate = escapedBase + "$1"
        } else {
            linkTemplate = "$1"
            bareTemplate = ""
        }
        let linked: String = ImpulseBrand.markdownSiteLinkExpression.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text), withTemplate: linkTemplate)
        return ImpulseBrand.bareSiteUrlExpression.stringByReplacingMatches(in: linked, options: [], range: NSRange(linked.startIndex..<linked.endIndex, in: linked), withTemplate: bareTemplate)
    }


    private static func trimmingTrailingSlashes(_ value: String) -> String {
        var result: String = value
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
