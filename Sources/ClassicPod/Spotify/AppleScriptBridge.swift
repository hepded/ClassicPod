import AppKit
import PodCore

enum SpotifyAppleEvent {
    enum Command: Sendable { case play, pause, next, previous, seek(Double), volume(Double), playURI(String), state }
    static let sendOptions: NSAppleEventDescriptor.SendOptions = [.waitForReply, .neverInteract]
    static let timeout: TimeInterval = 5
    static func code(_ value: String) -> UInt32 {
        precondition(value.utf8.count == 4)
        return value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
    static func property(_ name: String, container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(name)), forKeyword: AEKeyword(keyAEKeyData))
        return record.coerce(toDescriptorType: typeObjectSpecifier)!
    }
    static func event(_ command: Command, pid: pid_t) throws -> NSAppleEventDescriptor {
        let eventClass: String
        let eventID: String
        var direct: NSAppleEventDescriptor?
        var data: NSAppleEventDescriptor?
        switch command {
        case .play: eventClass = "spfy"; eventID = "Play"
        case .pause: eventClass = "spfy"; eventID = "Paus"
        case .next: eventClass = "spfy"; eventID = "Next"
        case .previous: eventClass = "spfy"; eventID = "Prev"
        case .state: eventClass = "core"; eventID = "getd"; direct = property("pPlS")
        case .seek(let seconds):
            guard seconds.isFinite else { throw PodError.message(L10n.text("Неверная позиция")) }
            eventClass = "core"; eventID = "setd"; direct = property("pPos"); data = NSAppleEventDescriptor(double: max(0, seconds))
        case .volume(let value):
            guard value.isFinite else { throw PodError.message(L10n.text("Неверная громкость")) }
            eventClass = "core"; eventID = "setd"; direct = property("pVol"); data = NSAppleEventDescriptor(int32: Int32(min(1, max(0, value)) * 100))
        case .playURI(let uri):
            guard uri.hasPrefix("spotify:track:"), uri.count > 14, uri.dropFirst(14).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                throw PodError.message(L10n.text("Неверный Spotify URI"))
            }
            eventClass = "spfy"; eventID = "PCtx"; direct = NSAppleEventDescriptor(string: uri)
        }
        let event = NSAppleEventDescriptor(eventClass: code(eventClass), eventID: code(eventID), targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid), returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let direct { event.setParam(direct, forKeyword: keyDirectObject) }
        if let data { event.setParam(data, forKeyword: keyAEData) }
        return event
    }
}
actor SpotifyAppleEventBridge {
    typealias Command = SpotifyAppleEvent.Command
    struct Failure: LocalizedError {
        let code: Int
        var errorDescription: String? {
            switch code {
            case -1743, -1744: return L10n.text("Разрешите Automation через «Spotify на этом Mac». Системные настройки → Конфиденциальность → Автоматизация.")
            case -1712: return L10n.text("Spotify не ответил за 5 секунд. Команда не повторена; состояние будет перечитано.")
            default: return L10n.format("Spotify Apple Events: ошибка %@", String(code))
            }
        }
    }
    private func process() throws -> NSRunningApplication {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first, !application.isTerminated else {
            throw PodError.message(L10n.text("Откройте Spotify вручную. ClassicPod не запускает и не активирует его автоматически."))
        }
        return application
    }
    func authorize() throws {
        let application = try process()
        try permission(pid: application.processIdentifier, ask: true)
    }
    private func permission(pid: pid_t, ask: Bool) throws {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        guard let descriptor = target.aeDesc else { throw Failure(code: -50) }
        let status = AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, ask)
        guard status == noErr else { throw Failure(code: Int(status)) }
    }
    func execute(_ command: Command) throws -> PlaybackSnapshot? {
        let application = try process()
        let pid = application.processIdentifier
        try permission(pid: pid, ask: false)
        let deadline = ProcessInfo.processInfo.systemUptime + SpotifyAppleEvent.timeout
        if case .state = command { return try readState(pid: pid, deadline: deadline) }
        _ = try send(SpotifyAppleEvent.event(command, pid: pid), deadline: deadline)
        return nil
    }
    private func send(_ event: NSAppleEventDescriptor, deadline: Double) throws -> NSAppleEventDescriptor {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { throw Failure(code: -1712) }
        let reply: NSAppleEventDescriptor
        do { reply = try event.sendEvent(options: SpotifyAppleEvent.sendOptions, timeout: min(SpotifyAppleEvent.timeout, remaining)) }
        catch { throw Failure(code: (error as NSError).code) }
        if let error = reply.paramDescriptor(forKeyword: keyErrorNumber), error.int32Value != 0 { throw Failure(code: Int(error.int32Value)) }
        return reply.paramDescriptor(forKeyword: keyDirectObject) ?? .null()
    }
    private func readState(pid: pid_t, deadline: Double) throws -> PlaybackSnapshot? {
        func get(_ property: String, track: Bool = false) throws -> NSAppleEventDescriptor {
            let event = try SpotifyAppleEvent.event(.state, pid: pid)
            let container = track ? SpotifyAppleEvent.property("pTrk") : .null()
            event.setParam(SpotifyAppleEvent.property(property, container: container), forKeyword: keyDirectObject)
            return try send(event, deadline: deadline)
        }
        var snapshot = PlaybackSnapshot(source: .spotify)
        let state = try get("pPlS").enumCodeValue
        snapshot.playing = state == SpotifyAppleEvent.code("kPSP")
        snapshot.capabilities = .all
        snapshot.volume = Double(try get("pVol").int32Value) / 100
        if state == SpotifyAppleEvent.code("kPSS") { return snapshot }
        do {
            let identifier = try get("ID  ", track: true).stringValue ?? ""
            guard !identifier.isEmpty else { return nil }
            let title = try get("pnam", track: true).stringValue ?? ""
            let artist = try get("pArt", track: true).stringValue ?? ""
            let album = try get("pAlb", track: true).stringValue ?? ""
            snapshot.duration = try get("pDur", track: true).doubleValue / 1000
            snapshot.position = try get("pPos").doubleValue
            let artwork = try get("aUrl", track: true).stringValue ?? ""
            guard try get("ID  ", track: true).stringValue == identifier else { return nil }
            snapshot.track = Track(id: identifier, title: title, artist: artist, album: album, duration: snapshot.duration, artworkURL: URL(string: artwork), location: .spotify(uri: identifier))
            return snapshot
        } catch let error as Failure where [-1728, -1700].contains(error.code) { return nil }
    }
}
