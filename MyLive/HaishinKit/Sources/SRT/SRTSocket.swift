import Foundation
import HaishinKit

protocol SRTSocketDelegate: class {
    func status(_ socket: SRTSocket, status: SRT_SOCKSTATUS)
}

class SRTSocket {
    static let defaultOptions: [SRTSocketOption: Any] = [:]

    weak var delegate: SRTSocketDelegate?
    var timeout: Int = 0
    var options: [SRTSocketOption: Any] = [:] {
        didSet {
            options[.rcvsyn] = true
            options[.tsbdmode] = true
        }
    }
    private(set) var isRunning: Bool = false
    private let lockQueue: DispatchQueue = DispatchQueue(label: "SRTSocket.lock")
    var socket: SRTSOCKET = SRT_INVALID_SOCK 
    var bindSocket: SRTSOCKET = SRT_INVALID_SOCK
    var pollid: Int32 = -1     

    var status: SRT_SOCKSTATUS = SRTS_INIT { 
        didSet {
            guard status != oldValue else { return }
            delegate?.status(self, status: status)
            switch status {
            case SRTS_INIT: // 1
                break
            case SRTS_OPENED:
                break
            case SRTS_LISTENING:
                break
            case SRTS_CONNECTING:
                break
            case SRTS_CONNECTED:
                break
            case SRTS_BROKEN:
                close()
            case SRTS_CLOSING:
                break
            case SRTS_CLOSED:
                stopRunning()
            case SRTS_NONEXIST:
                break
            default:
                break
            }
        }
    }

    func connect(_ addr: sockaddr_in, options: [SRTSocketOption: Any] = SRTSocket.defaultOptions) throws {
        guard socket == SRT_INVALID_SOCK else { return }
        // prepare socket
        socket = srt_socket(AF_INET, SOCK_DGRAM, 0)
        if socket == SRT_ERROR {
            throw SRTError.illegalState(message: "")
        }
        self.options = options
        guard configure(.pre) else { return }
        // prepare connect
        var addr_cp = addr
        let stat = withUnsafePointer(to: &addr_cp) { ptr -> Int32 in
            let psa = UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self)
            return srt_connect(socket, psa, Int32(MemoryLayout.size(ofValue: addr)))
        }
        if stat == SRT_ERROR {
            throw SRTError.illegalState(message: "")
        }
        guard configure(.post) else { return }
        startRunning()
    }

    func close() {
        self.status = SRTS_CLOSED
        if socket != SRT_INVALID_SOCK {
            srt_close(socket)
            socket = SRT_INVALID_SOCK
        }
        if bindSocket != SRT_INVALID_SOCK { 
            srt_close(bindSocket)
            bindSocket = SRT_INVALID_SOCK
        }        
    }

    func configure(_ binding: SRTSocketOption.Binding) -> Bool {
        return configure(binding, self.socket)
    }

    func configure(_ binding: SRTSocketOption.Binding, _ sock: SRTSOCKET) -> Bool {
        let failures = SRTSocketOption.configure(sock, binding: binding, options: options)
        guard failures.isEmpty else { logger.error(failures); return false }
        return true
    }

    func listen(_ addr: sockaddr_in, options: [SRTSocketOption: Any] = SRTSocket.defaultOptions) throws {
        self.options = options
        DispatchQueue(label:"com.SRTOutgoingSocket.listen").async {
            self.listening(addr)
        }
    }

    func listening(_ addr: sockaddr_in) {
        guard bindSocket == SRT_INVALID_SOCK else { return }
        
        pollid = srt_epoll_create()
        guard pollid >= 0 else {
            return
        }
        bindSocket = srt_socket(AF_INET, SOCK_DGRAM, 0)
        if bindSocket == SRT_ERROR {
            return
        }
        
        var result: Int32 = 0
        var no: Int32 = 0
        result = srt_setsockopt(bindSocket, 0, SRTO_TSBPDMODE, &no, Int32(MemoryLayout.size(ofValue: no)))
        if result == -1 {
            return
        }
        result = srt_setsockopt(bindSocket, 0, SRTO_RCVSYN, &no, Int32(MemoryLayout.size(ofValue: no)))
        if result == -1 {
            return
        }
        guard configure(.pre, bindSocket) else { return }
        
        var addr_cp = addr
        var stat = withUnsafePointer(to: &addr_cp) { ptr -> Int32 in
            let psa = UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self)
            return srt_bind(bindSocket, psa, Int32(MemoryLayout.size(ofValue: addr)))
        }
        if stat == SRT_ERROR {
            logger.error("srt_bind SRT_ERROR")
            return
        }
        stat = srt_listen(bindSocket, 1)
        if stat == SRT_ERROR {
            srt_close(bindSocket)
            logger.error("srt_listen SRT_ERROR")
            return
        }

        var modes:Int32 = Int32(SRT_EPOLL_IN.rawValue | SRT_EPOLL_ERR.rawValue)
        srt_epoll_add_usock(pollid, bindSocket, &modes)
        self.status = srt_getsockstate(bindSocket)
        
        var count = 0
        while count < 100000 {
            count += 1
            usleep(200 * 1000)
             
            if bindSocket == SRT_INVALID_SOCK && socket == SRT_INVALID_SOCK {
                logger.info("listening break")
                break
            }

            var rfdslen: Int32 = 1
            var wfdslen: Int32 = 1
            var rfds: [SRTSOCKET] = .init(repeating: SRT_INVALID_SOCK, count: 1)
            var wfds: [SRTSOCKET] = .init(repeating: SRT_INVALID_SOCK, count: 1)
            if srt_epoll_wait(pollid, &rfds, &rfdslen, &wfds, &wfdslen, 0, nil, nil, nil, nil) >= 0 {
                var doabort: Bool = false
                
                if rfdslen > 0 || wfdslen > 0 {
                    let s = rfdslen > 0 ? rfds[0] : wfds[0]

                    let status = srt_getsockstate(s)
                                        
                    switch status {
                    case SRTS_LISTENING:
                        var scl: sockaddr_in = .init()
                        var sclen: Int32 = Int32(MemoryLayout.size(ofValue: scl))
                        
                        withUnsafeMutablePointer(to: &scl) {
                            let pscl = UnsafeMutableRawPointer($0).assumingMemoryBound(to: sockaddr.self)
                            socket = srt_accept(bindSocket, pscl, &sclen)
                        }
                        if socket == SRT_INVALID_SOCK {
                            srt_close(bindSocket)
                            bindSocket = SRT_INVALID_SOCK
                            doabort = true
                            break
                        }

                        srt_epoll_remove_usock(pollid, s)
                        
                        srt_close(bindSocket)
                        bindSocket = SRT_INVALID_SOCK

                        var events: Int32 = Int32(SRT_EPOLL_IN.rawValue | SRT_EPOLL_OUT.rawValue | SRT_EPOLL_ERR.rawValue)
                        let stat = srt_epoll_add_usock(pollid, socket, &events)
                        if stat != 0 {
                            doabort = true
                            break
                        }
    
                        guard configure(.post, socket) else {
                            doabort = true
                            break
                        }

                    case SRTS_BROKEN, SRTS_NONEXIST, SRTS_CLOSED:
                        if self.status == SRTS_CONNECTED {
                            srt_epoll_remove_usock(pollid, s)
                            doabort = true
                            logger.info("SRTS_BROKEN SRTS_CLOSED")
                        }
                        
                    case SRTS_CONNECTED:
                        if self.status != SRTS_CONNECTED {
                            startRunning()
                            logger.info("SRTS_CONNECTED")
                        }

                    default:
                        break
                    }
                }
                
                if doabort {
                    break
                } 
            } 
        }           
    }    
}

//extension SRTSocket: Running {
extension SRTSocket {
    // MARK: Running
    func startRunning() {
        lockQueue.async {
            self.isRunning = true
            repeat {
                self.status = srt_getsockstate(self.socket)
                usleep(3 * 10000)
            } while self.isRunning
        }
    }

    func stopRunning() {
        isRunning = false
    }
}
