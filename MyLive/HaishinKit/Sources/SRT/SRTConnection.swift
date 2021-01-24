import Foundation
import HaivisionSrt

open class SRTConnection: NSObject {
    /// SRT Library version
    static public let version: String = SRT_VERSION_STRING

    /// The URI passed to the SRTConnection.connect() method.
    public private(set) var uri: URL?
    /// This instance connect to server(true) or not(false)
    @objc dynamic public private(set) var connected: Bool = false

    @objc dynamic public private(set) var listening: Bool = false

    var recvSocket: SRTRecvSocket?
    var sendSocket: SRTSendSocket?
    
    private var streams: [SRTStream] = []

    public override init() {
        super.init()
    }

    deinit {
        streams.removeAll()
    }

    public func connect(_ uri: URL?) {
        guard let uri = uri, let scheme = uri.scheme, let port = uri.port, scheme == "srt" else { return }
        var host = uri.host
        if host == nil ||
           host == "" ||
           host == "localhost" ||
           host == "127.0.0.1" {
            host = "0.0.0.0"
        }
        
        self.uri = uri
        let options = SRTSocketOption.from(uri: uri)
        let addr = sockaddr_in(host!, port: UInt16(port))
        
        if host == "0.0.0.0" {
            sendSocket = SRTSendSocket()
            sendSocket?.delegate = self
            try? sendSocket?.listen(addr, options: options)
        } else {
            sendSocket = SRTSendSocket()
            sendSocket?.delegate = self
            try? sendSocket?.connect(addr, options: options)
        }
    }

    public func play(_ uri: URL?) {  
        guard let uri = uri, let scheme = uri.scheme, let host = uri.host, let port = uri.port, scheme == "srt" else { return }
        
        self.uri = uri
        let options = SRTSocketOption.from(uri: uri)
        let addr = sockaddr_in(host, port: UInt16(port))
        
        recvSocket = SRTRecvSocket()
        recvSocket?.delegate = self
        recvSocket?.stream = streams[0]
        
        recvSocket?.stream?.mixer.stopEncoding()
        //recvSocket?.mixer.startPlaying(srtConnection.audioEngine)
        recvSocket?.stream?.mixer.startRunning()
        
        //2020-12 Comment Package Depend HaishinKit
        //recvSocket?.stream?.mixer.videoIO.queue.startRunning()
        //recvSocket?.call(addr, options: options)
    }
    
    public func close() {
        for stream in streams {
            stream.close()
        }
        sendSocket?.close()
        recvSocket?.close()
    }

    public func attachStream(_ stream: SRTStream) {
        streams.append(stream)
    }

    private func sockaddr_in(_ host: String, port: UInt16) -> sockaddr_in {
        var addr: sockaddr_in = .init()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16BigToHost(UInt16(port))
        if inet_pton(AF_INET, host, &addr.sin_addr) == 1 {
            return addr
        }
        guard let hostent = gethostbyname(host), hostent.pointee.h_addrtype == AF_INET else {
            return addr
        }
        addr.sin_addr = UnsafeRawPointer(hostent.pointee.h_addr_list[0]!).assumingMemoryBound(to: in_addr.self).pointee
        return addr
    }
}

extension SRTConnection: SRTSocketDelegate {
    func status(_ socket: SRTSocket, status: SRT_SOCKSTATUS) {
        if let sendSocket = sendSocket {
            connected = sendSocket.status == SRTS_CONNECTED
            listening = sendSocket.status == SRTS_LISTENING
        }
    }
}
