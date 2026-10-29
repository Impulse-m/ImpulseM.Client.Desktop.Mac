import Foundation
import TelegramCore
import Postbox
import SwiftSignalKit
import MtProtoKit
import FoundationUtils
import ImpulseProxy

public func proxySettings(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<ProxySettings, NoError>  {
    return accountManager.sharedData(keys: [SharedDataKeys.proxySettings]) |> map { view in
        return view.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
    }
}

public extension ProxySettings {
    func withUpdatedActiveServer(_ activeServer: ProxyServerSettings?) -> ProxySettings {
        return ProxySettings(enabled: self.enabled, servers: servers, activeServer: activeServer, useForCalls: self.useForCalls)
    }
    
    func withUpdatedEnabled(_ enabled: Bool) -> ProxySettings {
        return ProxySettings(enabled: enabled, servers: self.servers, activeServer: self.activeServer, useForCalls: self.useForCalls)
    }
    
    func withAddedServer(_ proxy: ProxyServerSettings) -> ProxySettings {
        var servers = self.servers
        if servers.first(where: {$0 == proxy}) == nil {
            servers.append(proxy)
        }
        return ProxySettings(enabled: self.enabled, servers: servers, activeServer: self.activeServer, useForCalls: self.useForCalls)
    }
    
    func withUpdatedServer(_ current: ProxyServerSettings, with updated: ProxyServerSettings) -> ProxySettings {
        var servers = self.servers
        if let index = servers.firstIndex(where: {$0 == current}) {
            servers[index] = updated
        } else {
            servers.append(updated)
        }
        var activeServer = self.activeServer
        if activeServer == current {
            activeServer = updated
        }
        return ProxySettings(enabled: self.enabled, servers: servers, activeServer: activeServer, useForCalls: self.useForCalls)
    }
    
    func withUpdatedUseForCalls(_ enable: Bool) -> ProxySettings {
        return ProxySettings(enabled: self.enabled, servers: servers, activeServer: self.activeServer, useForCalls: enable)
    }
    
    func withRemovedServer(_ proxy: ProxyServerSettings) -> ProxySettings {
        var servers = self.servers
        var activeServer = self.activeServer
        var enabled: Bool = self.enabled
        if let index = servers.firstIndex(where: {$0 == proxy}) {
            _ = servers.remove(at: index)
        }
        if proxy == activeServer {
            activeServer = nil
            enabled = false
        }
        return ProxySettings(enabled: enabled, servers: servers, activeServer: activeServer, useForCalls: self.useForCalls)
    }
}

public extension ProxyServerSettings {
    var isEmpty: Bool {
        if host.isEmpty {
            return true
        }
        if port == 0 {
            return true
        }
        switch self.connection {
        case let .mtp(secret):
            if secret.isEmpty {
                return true
            }
        case let .web(secret, path):
            let address = path.isEmpty ? host : "\(host)/\(path)"
            if parseWebProxySecret(webProxySecretString(secret)) == nil || canonicalWebProxyAddress(address) == nil {
                return true
            }
        default:
            break
        }
        return false
    }
}


/// A proxy link found in pasted text: a VLESS share line or an http(s) subscription URL.
public enum ProxyLinkCandidate: Equatable {
    case vless(String)
    case subscription(URL)
}


/// Finds the ImpulseM proxy link candidates in text, one per line. Telegram proxy links (`tg://proxy`,
/// `tg://socks`, `t.me/proxy`, `t.me/socks`) are not candidates.
public enum ProxyLinkCandidates {
    private static let telegramDomains: [String] = ["t.me", "telegram.me", "telegram.dog"]


    public static func extract(
        text: String
    ) -> [ProxyLinkCandidate] {
        var candidates: [ProxyLinkCandidate] = []
        for rawLine: Substring in text.split(whereSeparator: { (character: Character) -> Bool in
            return character.isNewline
        }) {
            let line: String = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            switch ProxyLinks.detectInputKind(text: line) {
            case .links:
                candidates.append(.vless(line))
            case .subscription:
                if let url: URL = URL(string: line), !isTelegramLink(url) {
                    candidates.append(.subscription(url))
                }
            case .unknown:
                break
            }
        }
        return candidates
    }


    private static func isTelegramLink(
        _ url: URL
    ) -> Bool {
        guard let host: String = url.host?.lowercased() else {
            return false
        }
        return telegramDomains.contains(where: { (domain: String) -> Bool in
            return host == domain || host.hasSuffix("." + domain)
        })
    }
}
