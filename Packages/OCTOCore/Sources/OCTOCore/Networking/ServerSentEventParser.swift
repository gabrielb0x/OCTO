import Foundation

/// A single Server-Sent Event as defined by the HTML living standard.
public struct ServerSentEvent: Equatable, Sendable {
    public var event: String?
    public var data: String
    public var id: String?

    public init(event: String? = nil, data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// Incremental, byte-oriented SSE parser.
///
/// `URLSession.AsyncBytes.lines` drops empty lines, which are the event
/// separators in SSE, so the stream is fed byte by byte instead.
public struct ServerSentEventParser: Sendable {
    private var lineBuffer: [UInt8] = []
    private var dataLines: [String] = []
    private var eventName: String?
    private var lastEventID: String?
    private var lastByteWasCR = false

    public init() {}

    /// Feeds one byte and returns an event when a blank line completes it.
    public mutating func consume(_ byte: UInt8) -> ServerSentEvent? {
        switch byte {
        case 0x0A: // \n
            if lastByteWasCR {
                lastByteWasCR = false
                return nil
            }
            return processLine()
        case 0x0D: // \r
            lastByteWasCR = true
            return processLine()
        default:
            lastByteWasCR = false
            lineBuffer.append(byte)
            return nil
        }
    }

    /// Feeds a chunk of bytes and returns every event it completes.
    public mutating func consume<Bytes: Sequence>(_ bytes: Bytes) -> [ServerSentEvent] where Bytes.Element == UInt8 {
        var events: [ServerSentEvent] = []
        for byte in bytes {
            if let event = consume(byte) {
                events.append(event)
            }
        }
        return events
    }

    /// Flushes a trailing event when the stream ends without a final blank line.
    public mutating func finish() -> ServerSentEvent? {
        if !lineBuffer.isEmpty, let event = processLine() {
            return event
        }
        return dispatch()
    }

    private mutating func processLine() -> ServerSentEvent? {
        let line = String(decoding: lineBuffer, as: UTF8.self)
        lineBuffer.removeAll(keepingCapacity: true)

        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil // comment / keep-alive
        }

        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") {
                value = value.dropFirst()
            }
        } else {
            field = Substring(line)
            value = ""
        }

        switch field {
        case "data":
            dataLines.append(String(value))
        case "event":
            eventName = String(value)
        case "id":
            lastEventID = String(value)
        default:
            break
        }
        return nil
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            dataLines.removeAll(keepingCapacity: true)
            eventName = nil
        }
        guard !dataLines.isEmpty else { return nil }
        return ServerSentEvent(event: eventName, data: dataLines.joined(separator: "\n"), id: lastEventID)
    }
}
