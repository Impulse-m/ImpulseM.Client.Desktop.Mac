/// A screen or window that a call can share. Replaces the Objective-C `VideoSourceMac` protocol of the removed tgcalls capture layer.
public protocol CallCaptureSource: AnyObject {
    func deviceIdKey() -> String

    func title() -> String

    func uniqueKey() -> String

    func isEqual(_ another: Any) -> Bool
}
