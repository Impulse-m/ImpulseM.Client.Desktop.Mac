import Foundation
import SwiftSignalKit

/// Process-wide copy of the active account's `me_url_prefix`, for code that builds
/// links while rendering text and has no account context at hand.
public enum MeUrlPrefixMirror {
    private static let storage: Atomic<String> = Atomic(value: "")

    public static func set(_ prefix: String) {
        _ = storage.swap(prefix)
    }

    public static func current() -> String {
        return storage.with { $0 }
    }
}
