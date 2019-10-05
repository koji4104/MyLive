import Foundation
import HaishinKit

import AVFoundation
import CoreFoundation
import CoreVideo
import VideoToolbox

protocol TSReader2Delegate: class {
    func didReadPacketizedElementaryStream(_ data: ElementaryStreamSpecificData, PES: PacketizedElementaryStream)
}

class TSReader2 {
    weak var delegate: TSReader2Delegate?

    private(set) var PAT: ProgramAssociationSpecific? {
        didSet {
            guard let PAT: ProgramAssociationSpecific = PAT else {
                return
            }
            for (channel, PID) in PAT.programs {
                dictionaryForPrograms[PID] = channel
            }
        }
    }
    private(set) var PMT: [UInt16: ProgramMapSpecific] = [: ] {
        didSet {
            for (_, pmt) in PMT {
                  for data in pmt.elementaryStreamSpecificData {
                    dictionaryForESSpecData[data.elementaryPID] = data
                }
            }
        }
    }
    private(set) var numberOfPackets: Int = 0

    private var eof: UInt64 = 0
    private var cursor: Int = 0
    private var fileHandle: FileHandle?
    private var dictionaryForPrograms: [UInt16: UInt16] = [: ]
    private var dictionaryForESSpecData: [UInt16: ElementaryStreamSpecificData] = [: ]
    private var packetizedElementaryStreams: [UInt16: PacketizedElementaryStream] = [: ]

    init() {
    }
    func readPaket(_ packet: TSPacket) {
        numberOfPackets += 1
        if packet.PID == 0x0000 {
            PAT = ProgramAssociationSpecific(packet.payload)
            return
        }
        if let channel: UInt16 = dictionaryForPrograms[packet.PID] {
            PMT[channel] = ProgramMapSpecific(packet.payload)
            return
        }
        //if let data: ElementaryStreamSpecificData = dictionaryForESSpecData[packet.PID] {
        if let data: ElementaryStreamSpecificData = dictionaryForESSpecData[3840] {
            readPacketizedElementaryStream(data, packet: packet)
        }
    }

    func readPacketizedElementaryStream(_ data: ElementaryStreamSpecificData, packet: TSPacket) {
        if packet.payloadUnitStartIndicator {
            if let PES: PacketizedElementaryStream = packetizedElementaryStreams[packet.PID] {
                delegate?.didReadPacketizedElementaryStream(data, PES: PES)
            }
            if packet.payload.count<58 {
                return
            }
            packetizedElementaryStreams[packet.PID] = PacketizedElementaryStream(packet.payload)
            return
        }
        _ = packetizedElementaryStreams[packet.PID]?.append(packet.payload)
    }

    func close() {
        fileHandle?.closeFile()
    }
}

extension SRTIncomingSocket: TSReader2Delegate {
    final public func didReadPacketizedElementaryStream(_ data: ElementaryStreamSpecificData, PES: PacketizedElementaryStream) {
        
        // func enqueueSampleBuffer(_ stream: RTMPStream) {
        
        self.timestamp += 1
        let compositionTimeoffset = 0
        
        var timing = CMSampleTimingInfo(
            duration: CMTimeMake(value: Int64(timestamp), timescale: 1000),
            presentationTimeStamp: CMTimeMake(value: Int64(timestamp) + Int64(compositionTimeoffset), timescale: 1000),
            decodeTimeStamp: CMTime.invalid
        )

        let data: Data = PES.data
        var localData = data
        localData.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) -> Void in
            var blockBuffer: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: bytes,
                blockLength: data.count,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: data.count,
                flags: 0,
                blockBufferOut: &blockBuffer) == noErr else {
                return
            }
            var sampleBuffer: CMSampleBuffer?
            var sampleSizes: [Int] = [data.count]
            guard CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer!,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: stream?.mixer.videoIO.formatDescription,
                sampleCount: 1, sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 1,
                sampleSizeArray: &sampleSizes,
                sampleBufferOut: &sampleBuffer) == noErr else {
                return
            }
            var status = stream?.mixer.videoIO.decoder.decodeSampleBuffer(sampleBuffer!)
        }
    }
}

class SRTIncomingSocket: SRTSocket {
    private let readQueue: DispatchQueue = DispatchQueue(label:"com.SRTIncomingSocket.read")

    private lazy var tsReader: TSReader2 = {
        var tsReader = TSReader2()
        tsReader.delegate = self
        return tsReader
    }()

    var stream: SRTStream?
    var timestamp: UInt32 = 0
    
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

    func read(_ chunk: Int, data: inout [Int8]) -> Int {
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
                    return 0
                }
            }
            if stat == 0 {
                // Not necessarily eof. Closed connection is reported as error.
                ready = false
                usleep(10 * 1000)
            }
        } while !ready
        return Int(stat)
    }

    func run(_ addr: sockaddr_in, options: [SRTSocketOption: Any] = SRTSocket.defaultOptions) {
        self.options = options
        DispatchQueue(label:"com.SRTOutgoingSocket.run").async {
            self.running(addr)
        }
    }

    func running(_ addr: sockaddr_in, options: [SRTSocketOption: Any] = SRTSocket.defaultOptions) {
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
            var buf:[Int8] = .init(repeating: 0, count: chunk)
            let r1 = read(chunk, data: &buf)
            
            var offset = 0
            while (offset+188)<=r1 {  
                var buf188:[UInt8] = .init(repeating: 0, count: 188)
                var i1:Int = 0
                while i1<188 {
                    let uu = UInt8.init( buf[offset+i1].magnitude )
                    buf188[i1] = uu
                    i1 += 1
                }
                let d1 = Data(buf188)
                let packet:TSPacket = TSPacket(data: d1)!
                offset += 188
               
                tsReader.readPaket(packet)
            }
        }
        srt_close(bindSocket)
        bindSocket = SRT_INVALID_SOCK
    }
}
