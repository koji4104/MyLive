import Foundation
import HaishinKit1

final class SRTSendSocket: SRTSocket {
    static let payloadSize: Int = 1316

    private var lostBytes: Int64 = 0
    private var wroteBytes: Int64 = 0
    private var pendingData: [Data] = []
    private let writeQueue: DispatchQueue = DispatchQueue(label:"com.SRTSendSocket.write")

    override func configure(_ binding: SRTSocketOption.Binding, _ sock: SRTSOCKET) -> Bool {
        switch binding {
        case .pre:
            return super.configure(binding, sock)
        case .post:
            options[.sndsyn] = true
            if 0 < timeout {
                options[.sndtimeo] = timeout
            }
            return super.configure(binding, sock)
        }
    }

    func write(_ data: Data) {
        writeQueue.async {
            //self.pendingData.append(contentsOf: data.chunk(SRTSendSocket.payloadSize))
            //repeat {
            //    if let data = self.pendingData.first {
            //        data.withUnsafeBytes { (buffer: UnsafePointer<Int8>) -> Void in
            //            srt_sendmsg2(self.socket, buffer, Int32(data.count), nil)
            //        }
            //        self.pendingData.remove(at: 0)
            //    }
            //} while !self.pendingData.isEmpty
       
            var offset = 0
            while (data.count-offset) > 0 {
                if (data.count-offset) <= SRTSendSocket.payloadSize {
                    self.pendingData.append(data.subdata(in: offset..<data.count))
                } else {
                    self.pendingData.append(data.subdata(in: offset..<offset+SRTSendSocket.payloadSize))
                }
                offset += SRTSendSocket.payloadSize
            }
                
            repeat {
                if let data = self.pendingData.first {
                    data.withUnsafeBytes { (buffer: UnsafePointer<Int8>) -> Void in
                        srt_sendmsg2(self.socket, buffer, Int32(data.count), nil)
                    }
                    self.pendingData.remove(at: 0)
                }
            } while !self.pendingData.isEmpty
        }
    }
}
