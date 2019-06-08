import Foundation

extension Data {
    var bytes: [UInt8] {
        return withUnsafeBytes {
            [UInt8](UnsafeBufferPointer(start: $0, count: count))
        }
    }
    func chunk(_ size: Int) -> [Data] {
        if count < size {
            return [self]
        }
        var chunks: [Data] = []
        let length = count
        var offset = 0
        repeat {
            let thisChunkSize = ((length - offset) > size) ? size : (length - offset)
            chunks.append(subdata(in: offset..<offset + thisChunkSize))
            offset += thisChunkSize
        } while offset < length
        return chunks
    }
}
