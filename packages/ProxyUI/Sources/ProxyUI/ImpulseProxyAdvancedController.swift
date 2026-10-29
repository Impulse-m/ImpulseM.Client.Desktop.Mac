import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramTheme
import TelegramContext
import GeneralRows
import InputDataUI
import AlertsUI
import Localization
import ColorPalette
import ImpulseProxy


/// Rules of the advanced proxy page. The defaults, the value sanitizer and the restart rule belong to the core
/// (`ImpulseProxyState.Advanced`, `XrayPing`); this type only names the choices and checks typed text with those rules.
public enum ImpulseProxyAdvancedRules {
    public static let fragmentOff: String = "off"
    public static let fragmentClassic: String = "classic"
    public static let fragmentFinalMask: String = "finalmask"
    public static let packetsDefault: String = "tlshello"
    public static let packetsExample: String = "1-3"
    /// Picker value that opens the text prompt. It is not a valid packets value, so it never reaches the state.
    public static let packetsCustom: String = "custom"
    public static let dnsModeSystem: String = "system"
    public static let dnsModeCloudflare: String = "cloudflare"
    public static let dnsModeGoogle: String = "google"
    public static let dnsModeCustom: String = "custom"
    public static let pingModeBatch: String = "batch"
    public static let pingModeSequential: String = "sequential"
    public static let fingerprints: [String] = [
        "chrome",
        "firefox",
        "safari",
        "ios",
        "android",
        "edge",
        "360",
        "qq",
        "random",
        "randomized"
    ]


    /// True when a core-affecting field differs. Ping-only settings never restart the core.
    public static func restartRequired(
        previous: ImpulseProxyState.Advanced,
        next: ImpulseProxyState.Advanced
    ) -> Bool {
        return XrayPing.restartRequired(previous: previous, next: next)
    }


    /// Parses a non-empty run of ASCII digits of at most nine characters.
    public static func parseNumber(_ text: String) -> Int? {
        let isDigits: Bool = text.allSatisfy { (character: Character) -> Bool in
            return character.isASCII && character.isNumber
        }
        if text.isEmpty || text.count > 9 || !isDigits {
            return nil
        }
        return Int(text)
    }


    /// Returns the number when the sanitizer keeps it unchanged at `keyPath`, that is when it is inside the allowed range.
    public static func acceptNumber(
        _ text: String,
        at keyPath: WritableKeyPath<ImpulseProxyState.Advanced, Int>
    ) -> Int? {
        guard let value: Int = parseNumber(text) else {
            return nil
        }
        var probe: ImpulseProxyState.Advanced = ImpulseProxyState.Advanced()
        probe[keyPath: keyPath] = value
        probe.sanitize()
        return probe[keyPath: keyPath] == value ? value : nil
    }


    /// Returns the text when it is non-empty, has no spaces and the sanitizer keeps it unchanged at `keyPath`.
    public static func acceptText(
        _ text: String,
        at keyPath: WritableKeyPath<ImpulseProxyState.Advanced, String>
    ) -> String? {
        if text.isEmpty || text.contains(" ") {
            return nil
        }
        var probe: ImpulseProxyState.Advanced = ImpulseProxyState.Advanced()
        probe[keyPath: keyPath] = text
        probe.sanitize()
        return probe[keyPath: keyPath] == text ? text : nil
    }
}


/// Holds the proxy controller for the page. Every edit goes through `ProxyController.update`, so the core restarts
/// only for the settings that affect it, and the page refreshes from the controller's snapshot.
private final class ImpulseProxyAdvancedPage {
    let statePromise: ValuePromise<ImpulseProxyState>
    private let proxy: ProxyController


    init(proxy: ProxyController) {
        self.proxy = proxy
        self.statePromise = ValuePromise(proxy.snapshot, ignoreRepeated: false)
    }


    func editAdvanced(_ change: (inout ImpulseProxyState.Advanced) -> Void) {
        proxy.update { (state: inout ImpulseProxyState) -> Void in
            var edited: ImpulseProxyState.Advanced = state.advanced
            change(&edited)
            edited.sanitize()
            state.advanced = edited
        }
        statePromise.set(proxy.snapshot)
    }


    func resetAdvanced() {
        editAdvanced { (advanced: inout ImpulseProxyState.Advanced) -> Void in
            advanced = ImpulseProxyState.Advanced()
        }
    }


    func confirmReset() {
        verifyAlert(
            for: mainWindow,
            header: strings().impulseProxyAdvancedResetTitle,
            information: nil,
            ok: strings().impulseProxyAdvancedResetButton,
            successHandler: { (_: ConfirmResult) -> Void in
                self.resetAdvanced()
            }
        )
    }


    /// Turns one transport off or on. At least one of the two stays on; otherwise the page explains why nothing changed.
    func toggleUseFor(transport: Bool) {
        let current: ImpulseProxyState = proxy.snapshot
        let applied: Bool = setUseFor(
            useForTransport: transport ? !current.useForTransport : current.useForTransport,
            useForCalls: transport ? current.useForCalls : !current.useForCalls
        )
        if !applied {
            alert(for: mainWindow, info: strings().impulseProxyAdvancedUseForNeedOne)
        }
    }


    private func setUseFor(
        useForTransport: Bool,
        useForCalls: Bool
    ) -> Bool {
        var applied: Bool = false
        proxy.update { (state: inout ImpulseProxyState) -> Void in
            applied = state.setToggles(useForTransport: useForTransport, useForCalls: useForCalls)
        }
        statePromise.set(proxy.snapshot)
        return applied
    }


    func choose(
        title: String,
        values: [ValuesSelectorValue<String>],
        selected: String,
        completion: @escaping (String) -> Void
    ) {
        let current: ValuesSelectorValue<String>? = values.first(where: { (value: ValuesSelectorValue<String>) -> Bool in
            return value.value == selected
        })
        let controller: ValuesSelectorModalController<String> = ValuesSelectorModalController(
            values: values,
            selected: current,
            title: title,
            onComplete: { (value: ValuesSelectorValue<String>) -> Void in
                completion(value.value)
            }
        )
        showModal(with: controller, for: mainWindow)
    }


    /// Opens a text prompt. Text that `parse` rejects shows `error` and changes nothing.
    func ask<Value>(
        title: String,
        placeholder: String,
        initial: String,
        error: String,
        parse: @escaping (String) -> Value?,
        completion: @escaping (Value) -> Void
    ) {
        guard let context: any AccountContextProtocol = ProxyHooks.installed?.currentContext() else {
            return
        }
        let controller: InputDataModalController = TextInputController(
            context: context,
            title: title,
            placeholder: placeholder,
            initialText: initial,
            callback: { (text: String) -> Void in
                let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let value: Value = parse(trimmed) {
                    completion(value)
                } else {
                    alert(for: mainWindow, info: error)
                }
            }
        )
        showModal(with: controller, for: mainWindow)
    }


    func askNumber(
        title: String,
        rule: String,
        current: Int,
        keyPath: WritableKeyPath<ImpulseProxyState.Advanced, Int>
    ) {
        ask(
            title: title,
            placeholder: rule,
            initial: String(current),
            error: rule,
            parse: { (text: String) -> Int? in
                return ImpulseProxyAdvancedRules.acceptNumber(text, at: keyPath)
            },
            completion: { (value: Int) -> Void in
                self.editAdvanced { (advanced: inout ImpulseProxyState.Advanced) -> Void in
                    advanced[keyPath: keyPath] = value
                }
            }
        )
    }


    func askText(
        title: String,
        placeholder: String,
        current: String,
        keyPath: WritableKeyPath<ImpulseProxyState.Advanced, String>,
        rule: String
    ) {
        ask(
            title: title,
            placeholder: placeholder,
            initial: current,
            error: rule,
            parse: { (text: String) -> String? in
                return ImpulseProxyAdvancedRules.acceptText(text, at: keyPath)
            },
            completion: { (value: String) -> Void in
                self.editAdvanced { (advanced: inout ImpulseProxyState.Advanced) -> Void in
                    advanced[keyPath: keyPath] = value
                }
            }
        )
    }
}


private struct ImpulseProxyAdvancedRow {
    let identifier: InputDataIdentifier
    let name: String
    let value: String
    let type: GeneralInteractedType
    let enabled: Bool
    let destructive: Bool
    let action: () -> Void


    init(
        identifier: InputDataIdentifier,
        name: String,
        value: String,
        type: GeneralInteractedType,
        enabled: Bool,
        destructive: Bool,
        action: @escaping () -> Void
    ) {
        self.identifier = identifier
        self.name = name
        self.value = value
        self.type = type
        self.enabled = enabled
        self.destructive = destructive
        self.action = action
    }
}


/// What a row shows. Equal keys mean the row does not need to be redrawn.
private struct ImpulseProxyAdvancedRowKey: Equatable {
    let name: String
    let value: String
    let enabled: Bool
    let destructive: Bool
    let viewType: GeneralViewType
}


/// Builds the sections of the page, mirroring the Android advanced page: the rows that only matter while
/// fragmentation is on appear with it, and the reset row closes the page.
private final class ImpulseProxyAdvancedEntries {
    private let page: ImpulseProxyAdvancedPage
    private var entries: [InputDataEntry] = []
    private var sectionId: Int32 = 0
    private var index: Int32 = 0


    private init(page: ImpulseProxyAdvancedPage) {
        self.page = page
    }


    static func build(
        state: ImpulseProxyState,
        page: ImpulseProxyAdvancedPage
    ) -> [InputDataEntry] {
        let builder: ImpulseProxyAdvancedEntries = ImpulseProxyAdvancedEntries(page: page)
        builder.appendAll(state: state)
        return builder.entries
    }


    private func appendAll(state: ImpulseProxyState) {
        let advanced: ImpulseProxyState.Advanced = state.advanced
        let fragmentOn: Bool = advanced.fragmentMode != ImpulseProxyAdvancedRules.fragmentOff
        let page: ImpulseProxyAdvancedPage = self.page

        startSection(header: strings().impulseProxyAdvancedUseFor)
        var useForRows: [ImpulseProxyAdvancedRow] = []
        useForRows.append(toggleRow(
            "useForTransport",
            name: strings().impulseProxyAdvancedUseForTransport,
            isOn: state.useForTransport,
            action: { () -> Void in
                page.toggleUseFor(transport: true)
            }
        ))
        useForRows.append(toggleRow(
            "useForCalls",
            name: strings().impulseProxyAdvancedUseForCalls,
            isOn: state.useForCalls,
            action: { () -> Void in
                page.toggleUseFor(transport: false)
            }
        ))
        appendRows(useForRows)
        appendFooter(strings().impulseProxyAdvancedUseForInfo)

        startSection(header: strings().impulseProxyAdvancedFragmentation)
        var fragmentRows: [ImpulseProxyAdvancedRow] = []
        fragmentRows.append(buttonRow(
            "fragmentMode",
            name: strings().impulseProxyAdvancedMode,
            value: fragmentModeName(advanced.fragmentMode),
            action: { () -> Void in
                page.choose(
                    title: strings().impulseProxyAdvancedMode,
                    values: [
                        ValuesSelectorValue(localized: strings().impulseProxyAdvancedOff, value: ImpulseProxyAdvancedRules.fragmentOff),
                        ValuesSelectorValue(localized: strings().impulseProxyAdvancedClassic, value: ImpulseProxyAdvancedRules.fragmentClassic),
                        ValuesSelectorValue(localized: strings().impulseProxyAdvancedFinalMask, value: ImpulseProxyAdvancedRules.fragmentFinalMask)
                    ],
                    selected: advanced.fragmentMode,
                    completion: { (mode: String) -> Void in
                        page.editAdvanced { (edited: inout ImpulseProxyState.Advanced) -> Void in
                            edited.fragmentMode = mode
                        }
                    }
                )
            }
        ))
        if fragmentOn {
            fragmentRows.append(buttonRow(
                "fragmentPackets",
                name: strings().impulseProxyAdvancedPackets,
                value: advanced.fragmentPackets,
                action: { () -> Void in
                    self.choosePackets(page: page, advanced: advanced)
                }
            ))
            fragmentRows.append(buttonRow(
                "fragmentLength",
                name: strings().impulseProxyAdvancedLength,
                value: advanced.fragmentLength,
                action: { () -> Void in
                    page.askText(
                        title: strings().impulseProxyAdvancedLength,
                        placeholder: strings().impulseProxyAdvancedRangeError,
                        current: advanced.fragmentLength,
                        keyPath: \.fragmentLength,
                        rule: strings().impulseProxyAdvancedRangeError
                    )
                }
            ))
            fragmentRows.append(buttonRow(
                "fragmentInterval",
                name: strings().impulseProxyAdvancedInterval,
                value: strings().impulseProxyAdvancedRangeMillisValue(advanced.fragmentInterval),
                action: { () -> Void in
                    page.askText(
                        title: strings().impulseProxyAdvancedInterval,
                        placeholder: strings().impulseProxyAdvancedRangeError,
                        current: advanced.fragmentInterval,
                        keyPath: \.fragmentInterval,
                        rule: strings().impulseProxyAdvancedRangeError
                    )
                }
            ))
        }
        fragmentRows.append(toggleRow(
            "fragmentFromLink",
            name: strings().impulseProxyAdvancedFromLink,
            isOn: advanced.fragmentFromLink,
            action: { () -> Void in
                page.editAdvanced { (edited: inout ImpulseProxyState.Advanced) -> Void in
                    edited.fragmentFromLink = !edited.fragmentFromLink
                }
            }
        ))
        appendRows(fragmentRows)
        appendFooter(strings().impulseProxyAdvancedFragmentInfo)

        startSection(header: strings().impulseProxyAdvancedFingerprint)
        var fingerprintValues: [ValuesSelectorValue<String>] = [
            ValuesSelectorValue(localized: strings().impulseProxyAdvancedAsInLink, value: "")
        ]
        for fingerprint: String in ImpulseProxyAdvancedRules.fingerprints {
            fingerprintValues.append(ValuesSelectorValue(localized: fingerprint, value: fingerprint))
        }
        var fingerprintRows: [ImpulseProxyAdvancedRow] = []
        fingerprintRows.append(buttonRow(
            "fingerprint",
            name: strings().impulseProxyAdvancedFingerprint,
            value: advanced.fingerprint.isEmpty ? strings().impulseProxyAdvancedAsInLink : advanced.fingerprint,
            action: { () -> Void in
                page.choose(
                    title: strings().impulseProxyAdvancedFingerprint,
                    values: fingerprintValues,
                    selected: advanced.fingerprint,
                    completion: { (fingerprint: String) -> Void in
                        page.editAdvanced { (edited: inout ImpulseProxyState.Advanced) -> Void in
                            edited.fingerprint = fingerprint
                        }
                    }
                )
            }
        ))
        appendRows(fingerprintRows)
        appendFooter(strings().impulseProxyAdvancedFingerprintInfo)

        startSection(header: strings().impulseProxyAdvancedMultiplexing)
        var muxRows: [ImpulseProxyAdvancedRow] = []
        muxRows.append(toggleRow(
            "mux",
            name: strings().impulseProxyAdvancedMux,
            isOn: advanced.muxEnabled,
            action: { () -> Void in
                page.editAdvanced { (edited: inout ImpulseProxyState.Advanced) -> Void in
                    edited.muxEnabled = !edited.muxEnabled
                }
            }
        ))
        if advanced.muxEnabled {
            muxRows.append(buttonRow(
                "muxConcurrency",
                name: strings().impulseProxyAdvancedMuxConcurrency,
                value: String(advanced.muxConcurrency),
                action: { () -> Void in
                    page.askNumber(
                        title: strings().impulseProxyAdvancedMuxConcurrency,
                        rule: strings().impulseProxyAdvancedNumberError(1, 128),
                        current: advanced.muxConcurrency,
                        keyPath: \.muxConcurrency
                    )
                }
            ))
        }
        appendRows(muxRows)
        appendFooter(strings().impulseProxyAdvancedMuxInfo)

        startSection(header: strings().impulseProxyAdvancedTcp)
        var tcpRows: [ImpulseProxyAdvancedRow] = []
        tcpRows.append(buttonRow(
            "keepAliveIdle",
            name: strings().impulseProxyAdvancedKeepIdle,
            value: secondsOrSystem(advanced.keepAliveIdle),
            action: { () -> Void in
                page.askNumber(
                    title: strings().impulseProxyAdvancedKeepIdle,
                    rule: strings().impulseProxyAdvancedSecondsError(0, 86400),
                    current: advanced.keepAliveIdle,
                    keyPath: \.keepAliveIdle
                )
            }
        ))
        tcpRows.append(buttonRow(
            "keepAliveInterval",
            name: strings().impulseProxyAdvancedKeepInterval,
            value: secondsOrSystem(advanced.keepAliveInterval),
            action: { () -> Void in
                page.askNumber(
                    title: strings().impulseProxyAdvancedKeepInterval,
                    rule: strings().impulseProxyAdvancedSecondsError(0, 86400),
                    current: advanced.keepAliveInterval,
                    keyPath: \.keepAliveInterval
                )
            }
        ))
        tcpRows.append(toggleRow(
            "tcpFastOpen",
            name: strings().impulseProxyAdvancedFastOpen,
            isOn: advanced.tcpFastOpen,
            action: { () -> Void in
                page.editAdvanced { (edited: inout ImpulseProxyState.Advanced) -> Void in
                    edited.tcpFastOpen = !edited.tcpFastOpen
                }
            }
        ))
        tcpRows.append(buttonRow(
            "tcpMaxSeg",
            name: strings().impulseProxyAdvancedMss,
            value: systemOr(advanced.tcpMaxSeg),
            action: { () -> Void in
                page.askNumber(
                    title: strings().impulseProxyAdvancedMss,
                    rule: strings().impulseProxyAdvancedMssError,
                    current: advanced.tcpMaxSeg,
                    keyPath: \.tcpMaxSeg
                )
            }
        ))
        appendRows(tcpRows)
        appendFooter(strings().impulseProxyAdvancedTcpInfo)

        startSection(header: strings().impulseProxyAdvancedDns)
        var dnsRows: [ImpulseProxyAdvancedRow] = []
        dnsRows.append(buttonRow(
            "dns",
            name: strings().impulseProxyAdvancedDnsServer,
            value: dnsName(advanced),
            action: { () -> Void in
                self.chooseDns(page: page, advanced: advanced)
            }
        ))
        appendRows(dnsRows)
        appendFooter(strings().impulseProxyAdvancedDnsInfo)

        startSection(header: strings().impulseProxyAdvancedChecks)
        var checkRows: [ImpulseProxyAdvancedRow] = []
        checkRows.append(buttonRow(
            "pingMode",
            name: strings().impulseProxyAdvancedMode,
            value: pingModeName(advanced.pingMode),
            action: { () -> Void in
                page.choose(
                    title: strings().impulseProxyAdvancedMode,
                    values: [
                        ValuesSelectorValue(localized: strings().impulseProxyAdvancedChecksBatch, value: ImpulseProxyAdvancedRules.pingModeBatch),
                        ValuesSelectorValue(localized: strings().impulseProxyAdvancedChecksOne, value: ImpulseProxyAdvancedRules.pingModeSequential)
                    ],
                    selected: advanced.pingMode,
                    completion: { (mode: String) -> Void in
                        page.editAdvanced { (edited: inout ImpulseProxyState.Advanced) -> Void in
                            edited.pingMode = mode
                        }
                    }
                )
            }
        ))
        checkRows.append(buttonRow(
            "pingPause",
            name: strings().impulseProxyAdvancedPause,
            value: strings().impulseProxyAdvancedMillisValue(advanced.pingPauseMillis),
            action: { () -> Void in
                page.askNumber(
                    title: strings().impulseProxyAdvancedPause,
                    rule: strings().impulseProxyAdvancedMillisError(0, 10000),
                    current: advanced.pingPauseMillis,
                    keyPath: \.pingPauseMillis
                )
            }
        ))
        checkRows.append(buttonRow(
            "pingTimeout",
            name: strings().impulseProxyAdvancedTimeout,
            value: strings().impulseProxyAdvancedSecondsValue(advanced.pingTimeoutSeconds),
            action: { () -> Void in
                page.askNumber(
                    title: strings().impulseProxyAdvancedTimeout,
                    rule: strings().impulseProxyAdvancedSecondsError(1, 30),
                    current: advanced.pingTimeoutSeconds,
                    keyPath: \.pingTimeoutSeconds
                )
            }
        ))
        checkRows.append(buttonRow(
            "pingUrl",
            name: strings().impulseProxyAdvancedUrl,
            value: advanced.pingUrl,
            action: { () -> Void in
                page.askText(
                    title: strings().impulseProxyAdvancedUrl,
                    placeholder: strings().impulseProxyAdvancedUrlError,
                    current: advanced.pingUrl,
                    keyPath: \.pingUrl,
                    rule: strings().impulseProxyAdvancedUrlError
                )
            }
        ))
        checkRows.append(toggleRow(
            "pingSkipWhileConnected",
            name: strings().impulseProxyAdvancedSkipConnected,
            isOn: advanced.pingSkipWhileConnected,
            action: { () -> Void in
                page.editAdvanced { (edited: inout ImpulseProxyState.Advanced) -> Void in
                    edited.pingSkipWhileConnected = !edited.pingSkipWhileConnected
                }
            }
        ))
        appendRows(checkRows)
        appendFooter(strings().impulseProxyAdvancedChecksInfo)

        startSection(header: nil)
        var resetRows: [ImpulseProxyAdvancedRow] = []
        resetRows.append(ImpulseProxyAdvancedRow(
            identifier: rowId("reset"),
            name: strings().impulseProxyAdvancedReset,
            value: "",
            type: .none,
            enabled: true,
            destructive: true,
            action: { () -> Void in
                page.confirmReset()
            }
        ))
        appendRows(resetRows)
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }


    private func choosePackets(
        page: ImpulseProxyAdvancedPage,
        advanced: ImpulseProxyState.Advanced
    ) {
        let isPreset: Bool = advanced.fragmentPackets == ImpulseProxyAdvancedRules.packetsDefault || advanced.fragmentPackets == ImpulseProxyAdvancedRules.packetsExample
        let selected: String = isPreset ? advanced.fragmentPackets : ImpulseProxyAdvancedRules.packetsCustom
        page.choose(
            title: strings().impulseProxyAdvancedPackets,
            values: [
                ValuesSelectorValue(localized: ImpulseProxyAdvancedRules.packetsDefault, value: ImpulseProxyAdvancedRules.packetsDefault),
                ValuesSelectorValue(localized: ImpulseProxyAdvancedRules.packetsExample, value: ImpulseProxyAdvancedRules.packetsExample),
                ValuesSelectorValue(localized: strings().impulseProxyAdvancedCustom, value: ImpulseProxyAdvancedRules.packetsCustom)
            ],
            selected: selected,
            completion: { (choice: String) -> Void in
                if choice == ImpulseProxyAdvancedRules.packetsCustom {
                    page.ask(
                        title: strings().impulseProxyAdvancedPackets,
                        placeholder: strings().impulseProxyAdvancedPacketsError,
                        initial: advanced.fragmentPackets,
                        error: strings().impulseProxyAdvancedPacketsError,
                        parse: { (text: String) -> String? in
                            return ImpulseProxyAdvancedRules.acceptText(text, at: \.fragmentPackets)
                        },
                        completion: { (value: String) -> Void in
                            page.editAdvanced { (edited: inout ImpulseProxyState.Advanced) -> Void in
                                edited.fragmentPackets = value
                            }
                        }
                    )
                } else {
                    page.editAdvanced { (edited: inout ImpulseProxyState.Advanced) -> Void in
                        edited.fragmentPackets = choice
                    }
                }
            }
        )
    }


    /// Picks one of the DNS modes. The custom mode asks for a DoH URL or an IPv4 address first.
    private func chooseDns(
        page: ImpulseProxyAdvancedPage,
        advanced: ImpulseProxyState.Advanced
    ) {
        page.choose(
            title: strings().impulseProxyAdvancedDnsServer,
            values: [
                ValuesSelectorValue(localized: strings().impulseProxyAdvancedSystem, value: ImpulseProxyAdvancedRules.dnsModeSystem),
                ValuesSelectorValue(localized: strings().impulseProxyAdvancedDnsCloudflare, value: ImpulseProxyAdvancedRules.dnsModeCloudflare),
                ValuesSelectorValue(localized: strings().impulseProxyAdvancedDnsGoogle, value: ImpulseProxyAdvancedRules.dnsModeGoogle),
                ValuesSelectorValue(localized: strings().impulseProxyAdvancedCustom, value: ImpulseProxyAdvancedRules.dnsModeCustom)
            ],
            selected: advanced.dnsMode,
            completion: { (mode: String) -> Void in
                if mode == ImpulseProxyAdvancedRules.dnsModeCustom {
                    page.ask(
                        title: strings().impulseProxyAdvancedDnsServer,
                        placeholder: strings().impulseProxyAdvancedDnsError,
                        initial: advanced.dnsCustom,
                        error: strings().impulseProxyAdvancedDnsError,
                        parse: { (text: String) -> String? in
                            return ImpulseProxyAdvancedRules.acceptText(text, at: \.dnsCustom)
                        },
                        completion: { (server: String) -> Void in
                            page.editAdvanced { (edited: inout ImpulseProxyState.Advanced) -> Void in
                                edited.dnsMode = ImpulseProxyAdvancedRules.dnsModeCustom
                                edited.dnsCustom = server
                            }
                        }
                    )
                } else {
                    page.editAdvanced { (edited: inout ImpulseProxyState.Advanced) -> Void in
                        edited.dnsMode = mode
                    }
                }
            }
        )
    }


    private func startSection(header: String?) {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        if let header: String = header {
            entries.append(.desc(
                sectionId: sectionId,
                index: index,
                text: .plain(header),
                data: InputDataGeneralTextData(viewType: .textTopItem)
            ))
            index += 1
        }
    }


    private func appendFooter(_ text: String) {
        entries.append(.desc(
            sectionId: sectionId,
            index: index,
            text: .plain(text),
            data: InputDataGeneralTextData(viewType: .textBottomItem)
        ))
        index += 1
    }


    private func appendRows(_ rows: [ImpulseProxyAdvancedRow]) {
        for (position, row) in rows.enumerated() {
            let viewType: GeneralViewType = ImpulseProxyAdvancedEntries.viewType(position: position, count: rows.count)
            let key: ImpulseProxyAdvancedRowKey = ImpulseProxyAdvancedRowKey(
                name: row.name,
                value: row.value,
                enabled: row.enabled,
                destructive: row.destructive,
                viewType: viewType
            )
            entries.append(InputDataEntry.custom(
                sectionId: sectionId,
                index: index,
                value: .string(nil),
                identifier: row.identifier,
                equatable: InputDataEquatable(key),
                comparable: nil,
                item: { (initialSize: NSSize, stableId: InputDataEntryId) -> TableRowItem in
                    if row.destructive {
                        return GeneralInteractedRowItem(
                            initialSize,
                            stableId: stableId,
                            name: row.name,
                            nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.redUI),
                            type: row.type,
                            viewType: viewType,
                            action: row.action,
                            enabled: row.enabled
                        )
                    }
                    return GeneralInteractedRowItem(
                        initialSize,
                        stableId: stableId,
                        name: row.name,
                        type: row.type,
                        viewType: viewType,
                        action: row.action,
                        enabled: row.enabled
                    )
                }
            ))
            index += 1
        }
    }


    private func toggleRow(
        _ name: String,
        name title: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> ImpulseProxyAdvancedRow {
        return ImpulseProxyAdvancedRow(
            identifier: rowId(name),
            name: title,
            value: isOn ? "1" : "0",
            type: .switchable(isOn),
            enabled: true,
            destructive: false,
            action: action
        )
    }


    private func buttonRow(
        _ name: String,
        name title: String,
        value: String,
        action: @escaping () -> Void
    ) -> ImpulseProxyAdvancedRow {
        return ImpulseProxyAdvancedRow(
            identifier: rowId(name),
            name: title,
            value: value,
            type: .nextContext(value),
            enabled: true,
            destructive: false,
            action: action
        )
    }


    private func rowId(_ name: String) -> InputDataIdentifier {
        return InputDataIdentifier("impulseProxyAdvanced.\(name)")
    }


    private func fragmentModeName(_ mode: String) -> String {
        if mode == ImpulseProxyAdvancedRules.fragmentClassic {
            return strings().impulseProxyAdvancedClassic
        }
        if mode == ImpulseProxyAdvancedRules.fragmentFinalMask {
            return strings().impulseProxyAdvancedFinalMask
        }
        return strings().impulseProxyAdvancedOff
    }


    private func pingModeName(_ mode: String) -> String {
        if mode == ImpulseProxyAdvancedRules.pingModeSequential {
            return strings().impulseProxyAdvancedChecksOne
        }
        return strings().impulseProxyAdvancedChecksBatch
    }


    private func dnsName(_ advanced: ImpulseProxyState.Advanced) -> String {
        if advanced.dnsMode == ImpulseProxyAdvancedRules.dnsModeCloudflare {
            return strings().impulseProxyAdvancedDnsCloudflare
        }
        if advanced.dnsMode == ImpulseProxyAdvancedRules.dnsModeGoogle {
            return strings().impulseProxyAdvancedDnsGoogle
        }
        if advanced.dnsMode == ImpulseProxyAdvancedRules.dnsModeCustom {
            return advanced.dnsCustom
        }
        return strings().impulseProxyAdvancedSystem
    }


    private func secondsOrSystem(_ value: Int) -> String {
        if value == 0 {
            return strings().impulseProxyAdvancedSystem
        }
        return strings().impulseProxyAdvancedSecondsValue(value)
    }


    private func systemOr(_ value: Int) -> String {
        if value == 0 {
            return strings().impulseProxyAdvancedSystem
        }
        return String(value)
    }


    private static func viewType(
        position: Int,
        count: Int
    ) -> GeneralViewType {
        if count == 1 {
            return .singleItem
        }
        if position == 0 {
            return .firstItem
        }
        if position == count - 1 {
            return .lastItem
        }
        return .innerItem
    }
}


/// The advanced proxy page. Every edit is stored by the proxy controller; the core restarts only for the core settings
/// (`ImpulseProxyAdvancedRules.restartRequired`), and ping settings never restart it.
public func impulseProxyAdvancedController(proxy: ProxyController) -> InputDataController {
    let page: ImpulseProxyAdvancedPage = ImpulseProxyAdvancedPage(proxy: proxy)
    let signal: Signal<InputDataSignalValue, NoError> = combineLatest(
        page.statePromise.get() |> deliverOnPrepareQueue,
        appearanceSignal |> deliverOnPrepareQueue
    ) |> map { state, _ in
        return InputDataSignalValue(entries: ImpulseProxyAdvancedEntries.build(state: state, page: page))
    }
    let controller: InputDataController = InputDataController(
        dataSignal: signal,
        title: strings().impulseProxyAdvancedTitle,
        hasDone: false,
        identifier: "impulseProxyAdvanced"
    )
    return controller
}
