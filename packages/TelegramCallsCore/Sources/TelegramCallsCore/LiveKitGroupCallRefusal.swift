import TelegramCore


/// The group calls that LiveKit group media cannot run. Each of them ends before any room is joined, through the canonical error path.
enum LiveKitGroupCallRefusal {
    /// True for group E2E, conference and stream calls. LiveKit group media carry no group E2E, so these calls never reach a joined state.
    static func refusesCall(hasE2EContext: Bool, isConference: Bool, isStream: Bool) -> Bool {
        return hasE2EContext || isConference || isStream
    }


    /// True for a broadcast answer of the main join. Only RTC answers connect to a LiveKit room.
    static func refusesAnswer(connectionMode: JoinGroupCallResult.ConnectionMode) -> Bool {
        switch connectionMode {
        case .rtc:
            return false
        case .broadcast:
            return true
        }
    }
}
