import Foundation

/// Incremental parser for multipart/x-mixed-replace streams (MJPEG).
/// Feed raw chunks as they arrive; complete part bodies come back in order.
/// Pure value type: no I/O, no clock.
public struct MultipartParser {
    private var buffer: [UInt8] = []
    public private(set) var boundary: [UInt8]?
    static let maxBuffer = 8 * 1024 * 1024

    /// `boundary` may be given with or without the leading "--"; nil means
    /// "learn it from the first delimiter line".
    public init(boundary: String? = nil) {
        if let boundary { self.boundary = Self.marker(for: boundary) }
    }

    /// Extracts the boundary parameter from a Content-Type header value.
    public static func boundary(fromContentType value: String) -> String? {
        for part in value.split(separator: ";").dropFirst() {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0].lowercased() == "boundary" {
                return kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }

    private static func marker(for boundary: String) -> [UInt8] {
        var b = boundary
        while b.hasPrefix("--") { b.removeFirst(2) }
        return Array(("--" + b).utf8)
    }

    /// Feeds a chunk; returns every part body completed by it.
    public mutating func feed(_ data: Data) -> [Data] {
        buffer.append(contentsOf: data)
        var parts: [Data] = []
        while let body = nextPart() { parts.append(body) }
        if buffer.count > Self.maxBuffer { buffer.removeAll() }
        return parts
    }

    /// Like `feed`, but only the newest completed part (older ones are dropped).
    public mutating func feedNewest(_ data: Data) -> Data? { feed(data).last }

    // MARK: - Parsing

    private mutating func nextPart() -> Data? {
        // 1. Locate the delimiter line.
        let start: Int
        if let boundary {
            guard let s = Self.find(boundary, in: buffer, from: 0) else {
                keepTail(boundary.count)
                return nil
            }
            start = s
        } else {
            guard let s = Self.find([0x2D, 0x2D], in: buffer, from: 0),
                  let eol = Self.lineEnd(in: buffer, from: s) else { return nil }
            let line = String(decoding: buffer[s..<eol.start], as: UTF8.self)
            boundary = Self.marker(for: line.trimmingCharacters(in: .whitespaces))
            return nextPart()
        }
        guard let boundary else { return nil }
        guard let eol = Self.lineEnd(in: buffer, from: start + boundary.count) else { return nil }
        // Closing delimiter "--boundary--": nothing more to read.
        if buffer[(start + boundary.count)..<eol.start].starts(with: [0x2D, 0x2D]) {
            buffer.removeSubrange(0..<eol.next)
            return nil
        }
        // 2. Headers.
        guard let hdr = Self.headerEnd(in: buffer, from: eol.next) else { return nil }
        let headers = String(decoding: buffer[eol.next..<hdr.start], as: UTF8.self)
        let bodyStart = hdr.next
        // 3. Body: by Content-Length, else up to the next delimiter.
        if let length = Self.contentLength(in: headers) {
            guard buffer.count >= bodyStart + length else { return nil }
            let body = Data(buffer[bodyStart..<(bodyStart + length)])
            buffer.removeSubrange(0..<(bodyStart + length))
            return body
        }
        guard let next = Self.find(boundary, in: buffer, from: bodyStart) else { return nil }
        var end = next
        if end > bodyStart, buffer[end - 1] == 0x0A { end -= 1 }
        if end > bodyStart, buffer[end - 1] == 0x0D { end -= 1 }
        let body = Data(buffer[bodyStart..<end])
        buffer.removeSubrange(0..<next)
        return body
    }

    private mutating func keepTail(_ n: Int) {
        if buffer.count > n { buffer.removeSubrange(0..<(buffer.count - n)) }
    }

    private static func contentLength(in headers: String) -> Int? {
        for line in headers.components(separatedBy: .newlines) {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(kv[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private static func find(_ pattern: [UInt8], in buf: [UInt8], from: Int) -> Int? {
        guard !pattern.isEmpty, buf.count >= pattern.count, from <= buf.count - pattern.count else { return nil }
        let first = pattern[0]
        var i = from
        let last = buf.count - pattern.count
        while i <= last {
            if buf[i] == first, buf[i..<(i + pattern.count)].elementsEqual(pattern) { return i }
            i += 1
        }
        return nil
    }

    /// End of the line starting the search at `from`: (index of EOL, index after it).
    private static func lineEnd(in buf: [UInt8], from: Int) -> (start: Int, next: Int)? {
        var i = from
        while i < buf.count {
            if buf[i] == 0x0A { return (i, i + 1) }
            if buf[i] == 0x0D, i + 1 < buf.count, buf[i + 1] == 0x0A { return (i, i + 2) }
            if buf[i] == 0x0D, i + 1 >= buf.count { return nil }
            i += 1
        }
        return nil
    }

    /// Blank line ending the header block (CRLF CRLF or LF LF).
    private static func headerEnd(in buf: [UInt8], from: Int) -> (start: Int, next: Int)? {
        let a = find([13, 10, 13, 10], in: buf, from: from).map { ($0, $0 + 4) }
        let b = find([10, 10], in: buf, from: from).map { ($0, $0 + 2) }
        // A part with no headers at all begins with a blank line right at `from`.
        if from < buf.count, buf[from] == 0x0A { return (from, from + 1) }
        if from + 1 < buf.count, buf[from] == 0x0D, buf[from + 1] == 0x0A { return (from, from + 2) }
        switch (a, b) {
        case let (x?, y?): return x.0 <= y.0 ? x : y
        case let (x?, nil): return x
        case let (nil, y?): return y
        default: return nil
        }
    }
}
