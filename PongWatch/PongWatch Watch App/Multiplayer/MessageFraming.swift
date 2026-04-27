import Foundation

/// Length-prefix framed message codec for TCP streams.
/// Wire format per message: [u32 big-endian length][JSON bytes]
enum MessageFraming {
    static func encode(_ message: NetworkMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        var lenBE = UInt32(payload.count).bigEndian
        var out = Data(bytes: &lenBE, count: 4)
        out.append(payload)
        return out
    }

    /// Parser that accumulates bytes and emits complete messages as they arrive.
    final class Decoder {
        private var buffer = Data()

        /// Append newly-received bytes; returns any complete messages decoded from the buffer.
        func feed(_ chunk: Data) -> [NetworkMessage] {
            buffer.append(chunk)
            var results: [NetworkMessage] = []
            while true {
                guard buffer.count >= 4 else { break }
                let len = buffer[0..<4].withUnsafeBytes { rawBuf -> UInt32 in
                    let ptr = rawBuf.bindMemory(to: UInt32.self)
                    return UInt32(bigEndian: ptr[0])
                }
                guard buffer.count >= 4 + Int(len) else { break }
                let payload = buffer.subdata(in: 4..<(4 + Int(len)))
                buffer.removeSubrange(0..<(4 + Int(len)))
                if let msg = try? JSONDecoder().decode(NetworkMessage.self, from: payload) {
                    results.append(msg)
                }
                // If decode fails, we've already consumed the bytes — drop and continue.
            }
            return results
        }
    }
}
