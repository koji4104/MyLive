import Foundation
import HaishinKit

final class SRTIncomingSocket: SRTSocket {
    private let readQueue: DispatchQueue = DispatchQueue(label:"com.SRTIncomingSocket.read")

    override func configure(_ binding: SRTSocketOption.Binding) -> Bool {
        switch binding {
        case .pre:
            return super.configure(binding)
        case .post:
            options[.rcvsyn] = true
            if 0 < timeout {
                options[.rcvtimeo] = timeout
            }
            return super.configure(binding)
        }
    }

    func read(_ chunk: Int, data: inout [Int8]) -> Bool {
        if data.count < chunk {
            data = .init(repeating: 0, count: chunk)
        }
        var ready: Bool = true
        var stat: Int32
        repeat {
            stat = srt_recvmsg(socket, &data, Int32(chunk))
            if stat == SRT_ERROR {
                // EAGAIN for SRT READING
                if srt_getlasterror(nil) == SRT_EASYNCRCV.rawValue {
                    data.removeAll()
                    return false
                }
            }
            if stat == 0 {
                // Not necessarily eof. Closed connection is reported as error.
                ready = false
                usleep(10 * 1000)
            }
        } while !ready

        if stat > 0 {
            let chunk = MemoryLayout.size(ofValue: stat)
            if chunk < data.count {
                data = .init(repeating: 0, count: chunk)
            }
        }
        return true
    }

    func run(_ addr: sockaddr_in, options: [SRTSocketOption: Any] = SRTSocket.defaultOptions) {
        self.options = options
        DispatchQueue(label:"com.SRTOutgoingSocket.run").async {
            self.running1(addr)
        }
    }

    func running1(_ addr: sockaddr_in, options: [SRTSocketOption: Any] = SRTSocket.defaultOptions) {
        guard socket == SRT_INVALID_SOCK else { return }
        
        socket = srt_socket(AF_INET, SOCK_DGRAM, 0)
        if socket == SRT_ERROR {
            logger.error("srt_bind SRT_ERROR1")
            return
        }
        
        self.options = options
        guard configure(.pre) else { return }
        
        var addr_cp = addr
        let stat = withUnsafePointer(to: &addr_cp) { ptr -> Int32 in
            let psa = UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self)
            return srt_connect(socket, psa, Int32(MemoryLayout.size(ofValue: addr)))
        }
        
        if stat == SRT_ERROR {
            logger.error("srt_bind SRT_ERROR2")
            return
        }
        guard configure(.post) else { return }
        
        let chunk: Int = 1328
        var count = 0
        while count < 1000000 {
            count += 1
            var buf:[Int8] = .init()
            let r1 = read(chunk, data: &buf)
            if (count % 100) == 0 {
                print("count=\(count) - \(buf.count)" )
            }
        }
        srt_close(bindSocket)
        bindSocket = SRT_INVALID_SOCK
    }
}
