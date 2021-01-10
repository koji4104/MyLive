import Foundation
import HaishinKit1

private let enummapTranstype: [String: Any] = [
    "live": SRTT_LIVE,
    "file": SRTT_FILE
]

public enum SRTSocketOption: String {
    static func from(uri: URL?) -> [SRTSocketOption: Any] {
        guard let uri = uri, let queryItems = URLComponents(url: uri, resolvingAgainstBaseURL: true)?.queryItems else { return [:] }
        var options: [SRTSocketOption: Any] = [:]
        for item in queryItems {
            guard let option = SRTSocketOption(rawValue: item.name) else { continue }
            options[option] = item.value
        }
        return options
    }

    enum `Type`: Int {
        case string
        case int
        case int64
        case bool
        case enumeration
    }

    enum Binding: Int {
        case pre
        case post
    }

    case mss
    case sndsyn
    case rcvsyn
    case isn
    case fc
    case sndbuf
    case rcvbuf
    case linger
    case udpsndbuf
    case udprcvbuf
    case rendezvous
    case sndtimeo
    case rcvtimeo
    case reuseaddr
    case maxbw
    case state
    case event
    case snddata
    case rcvdata
    case sender
    case tsbdmode
    case latency
    case tsbpddelay
    case inputbw
    case oheadbw
    case passphrase
    case pbkeylen
    case kmstate
    case ipttl
    case iptos
    case tlpktdrop
    case snddropdelay
    case nakreport
    case conntimeo
    case sndkmstate
    case lossmaxttl
    case rcvlatency
    case peerlatency
    case minversion
    case streamid
    case smoother
    case messageapi
    case payloadsize
    case transtype
    case kmrefreshrate
    case kmpreannounce

    public var symbol: SRT_SOCKOPT {
        switch self {
        case .rcvsyn: return SRTO_RCVSYN
        case .maxbw: return SRTO_MAXBW
        case .pbkeylen: return SRTO_PBKEYLEN
        case .passphrase: return SRTO_PASSPHRASE
        case .mss: return SRTO_MSS
        case .fc: return SRTO_FC
        case .sndbuf: return SRTO_SNDBUF
        case .rcvbuf: return SRTO_RCVBUF
        case .ipttl: return SRTO_IPTTL
        case .iptos: return SRTO_IPTOS
        case .inputbw: return SRTO_INPUTBW
        case .oheadbw: return SRTO_OHEADBW
        case .latency: return SRTO_LATENCY
        case .tsbdmode: return SRTO_TSBPDMODE
        case .tsbpddelay: return SRTO_TSBPDDELAY
        case .tlpktdrop: return SRTO_TLPKTDROP
        case .nakreport: return SRTO_NAKREPORT
        case .conntimeo: return SRTO_CONNTIMEO
        case .lossmaxttl: return SRTO_LOSSMAXTTL
        case .rcvlatency: return SRTO_RCVLATENCY
        case .peerlatency: return SRTO_PEERLATENCY
        case .minversion: return SRTO_MINVERSION
        case .streamid: return SRTO_STREAMID
        case .smoother: return SRTO_SMOOTHER
        case .messageapi: return SRTO_MESSAGEAPI
        case .payloadsize: return SRTO_PAYLOADSIZE
        case .transtype: return SRTO_TRANSTYPE
        case .kmrefreshrate: return SRTO_KMREFRESHRATE
        case .kmpreannounce: return SRTO_KMPREANNOUNCE
        case .sndsyn: return SRTO_SNDSYN
        case .isn: return SRTO_ISN
        case .linger: return SRTO_LINGER
        case .udpsndbuf: return SRTO_UDP_SNDBUF
        case .udprcvbuf: return SRTO_UDP_RCVBUF
        case .rendezvous: return SRTO_RENDEZVOUS
        case .sndtimeo: return SRTO_SNDTIMEO
        case .rcvtimeo: return SRTO_RCVTIMEO
        case .reuseaddr: return SRTO_REUSEADDR
        case .state: return SRTO_STATE
        case .event: return SRTO_EVENT
        case .snddata: return SRTO_SNDDATA
        case .rcvdata: return SRTO_RCVDATA
        case .sender: return SRTO_SENDER
        case .kmstate: return SRTO_KMSTATE
        case .snddropdelay: return SRT_SOCKOPT(rawValue: 32)
        case .sndkmstate: return SRTO_SNDKMSTATE
        }
    }

    var binding: Binding {
        switch self {
        case .rcvsyn: return .pre
        case .maxbw: return .pre
        case .pbkeylen: return .pre
        case .passphrase: return .pre
        case .mss: return .pre
        case .fc: return .pre
        case .sndbuf: return .pre
        case .rcvbuf: return .pre
        case .ipttl: return .pre
        case .iptos: return .pre
        case .inputbw: return .post
        case .oheadbw: return .post
        case .tsbdmode: return .pre
        case .latency: return .pre
        case .tsbpddelay: return .pre
        case .tlpktdrop: return .pre
        case .nakreport: return .pre
        case .conntimeo: return .pre
        case .lossmaxttl: return .pre
        case .rcvlatency: return .pre
        case .peerlatency: return .pre
        case .minversion: return .pre
        case .streamid: return .pre
        case .smoother: return .pre
        case .messageapi: return .pre
        case .payloadsize: return .pre
        case .transtype: return .pre
        case .kmrefreshrate: return .pre
        case .kmpreannounce: return .pre
        case .sndsyn: return .post
        case .isn: return .post
        case .linger: return .post
        case .udpsndbuf: return .pre
        case .udprcvbuf: return .pre
        case .rendezvous: return .pre
        case .sndtimeo: return .post
        case .rcvtimeo: return .post
        case .reuseaddr: return .post // WIP
        case .state: return .post // WIP
        case .event: return .post // WIP
        case .snddata: return .post // WIP
        case .rcvdata: return .post // WIP
        case .sender: return .post // WIP
        case .kmstate: return .post // WIP
        case .snddropdelay: return .post // WIP
        case .sndkmstate: return .post // WIP
        }
    }

    var type: Type {
        switch self {
        case .tsbdmode: return .bool
        case .rcvsyn: return .bool
        case .maxbw: return .int64
        case .pbkeylen: return .int
        case .passphrase: return .string
        case .mss: return .int
        case .fc: return .int
        case .sndbuf: return .int
        case .rcvbuf: return .int
        case .ipttl: return .int
        case .iptos: return .int
        case .inputbw: return .int64
        case .oheadbw: return .int
        case .latency: return .int
        case .tsbpddelay: return .int
        case .tlpktdrop: return .bool
        case .nakreport: return .bool
        case .conntimeo: return .int
        case .lossmaxttl: return .int
        case .rcvlatency: return .int
        case .peerlatency: return .int
        case .minversion: return .int
        case .streamid: return .string
        case .smoother: return .string
        case .messageapi: return .bool
        case .payloadsize: return .int
        case .transtype: return .enumeration
        case .kmrefreshrate: return .int
        case .kmpreannounce: return .int
        case .sndsyn: return .bool
        case .isn: return .int
        case .linger: return .int
        case .udpsndbuf: return .int
        case .udprcvbuf: return .int
        case .rendezvous: return .bool
        case .sndtimeo: return .int
        case .rcvtimeo: return .int
        case .reuseaddr: return .bool // WIP
        case .state: return .int // WIP
        case .event: return .int // WIP
        case .snddata: return .int // WIP
        case .rcvdata: return .int // WIP
        case .sender: return .int // WIP
        case .kmstate: return .int // WIP
        case .snddropdelay: return .int // WIP
        case .sndkmstate: return .int // WIP
        }
    }

    var valmap: [String: Any]? {
        switch self {
        case .transtype:
            return enummapTranstype
        default:
            return nil
        }
    }

    func apply(_ socket: SRTSOCKET, value: Any) -> Bool {
        guard let data = data(value) else { return false }
        let result = data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
            return srt_setsockopt(socket, 0, symbol, ptr, Int32(data.count))
        }
        return result != -1
    }

    func data(_ value: Any) -> Data? {
        switch type {
        case .string:
            return String(describing: value).data(using: .utf8)
        case .int:
            var v: Int32 = 0
            if let value = value as? Int {
                v = Int32(value)
            }
            return .init(Data(bytes: &v, count: MemoryLayout.size(ofValue: v)))
        case .int64:
            guard var v = value as? Int64 else { return nil }
            return .init(Data(bytes: &v, count: MemoryLayout.size(ofValue: v)))
        case .bool:
            var v: Int32 = 0
            if let value = value as? Bool {
                v = value ? 1 : 0
            }
            return .init(Data(bytes: &v, count: MemoryLayout.size(ofValue: v)))
        case .enumeration:
            return nil
        }
    }

    static func configure(_ socket: SRTSOCKET, binding: Binding, options: [SRTSocketOption: Any]) -> [String] {
        var failures: [String] = []
        for (key, value) in options where key.binding == binding {
            if !key.apply(socket, value: value) { failures.append(key.rawValue) }
        }
        return failures
    }
}
