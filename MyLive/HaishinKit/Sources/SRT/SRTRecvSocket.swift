import Foundation
import HaishinKit

import AVFoundation
import CoreFoundation
import CoreVideo
import VideoToolbox

class SRTRecvSocket: SRTSocket {
    private let readQueue: DispatchQueue = DispatchQueue(label:"com.SRTRecvSocket.read")

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

    func call(_ addr: sockaddr_in, options: [SRTSocketOption: Any] = SRTSocket.defaultOptions) {
        self.options = options
        DispatchQueue(label:"com.SRTRecvSocket.call").async {
            self.calling(addr)
        }
    }

    func calling(_ addr: sockaddr_in, options: [SRTSocketOption: Any] = SRTSocket.defaultOptions) {
        guard socket == SRT_INVALID_SOCK else { return }
        
        socket = srt_socket(AF_INET, SOCK_DGRAM, 0)
        if socket == SRT_ERROR {
            logger.error("srt_socket SRT_ERROR")
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
            logger.error("srt_connect SRT_ERROR")
            return
        }
        guard configure(.post) else { return }
        
        let chunk:Int = 1316+10
        for _ in 0..<1000000 {
            var buf:[Int8] = .init(repeating: 0, count: chunk+1)
            let r1 = read(chunk, data: &buf)

            var offset = 0
            while (offset+188)<=r1 {  
                var buf188:[UInt8] = .init(repeating:0, count:188)
                for i in 0..<188 {
                    buf188[i] = UInt8(bitPattern: buf[offset+i])
                }
                let packet:TSPacket = TSPacket(data: Data(buf188))!
                tsReader.readPaket(packet)
                offset += 188
            }
        }
        srt_close(bindSocket)
        bindSocket = SRT_INVALID_SOCK
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
                if srt_getlasterror(nil) == SRT_EASYNCRCV.rawValue {
                    data.removeAll()
                    return 0
                }
            }
            if stat == 0 {
                ready = false
                usleep(10 * 1000)
            }
        } while !ready
        return Int(stat)
    }    
}

extension SRTRecvSocket: TSReader2Delegate {
    // func enqueueSampleBuffer(_ stream: RTMPStream) {
    final public func didReadPacketizedElementaryStream(_ data1: ElementaryStreamSpecificData, PES: PacketizedElementaryStream) {

        // PES.optionalPESHeader.PTSDTSIndicator
        let pts = Int32(data: PES.optionalPESHeader!.optionalFields[1..<4]).bigEndian
        var timing = CMSampleTimingInfo(
            duration: CMTimeMake(value: Int64(33), timescale: 1000),
            presentationTimeStamp: CMTimeMake(value: Int64(pts), timescale: 1000),
            decodeTimeStamp: CMTime.invalid
        )
        
        let len = (PES.data[10] == 103) ? 49 : 10
        var data: Data = Data()
        data.append(0)
        data.append(0)
        data.append(UInt8( (PES.data.count-len)>>8 & 0xFF ))
        data.append(UInt8( (PES.data.count-len)    & 0xFF ))
        data.append(PES.data.subdata(in: len..<PES.data.count))
        
        var localData = data
        
        if stream?.mixer.videoIO.decoder.formatDescription == nil {             
            var formatDescription: CMFormatDescription?
            var config = AVCConfigurationRecord()
            config.setData(PES.data.subdata(in: 6..<PES.data.count))
            config.createFormatDescription(&formatDescription)
            stream?.mixer.videoIO.decoder.formatDescription = formatDescription
        }
        
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
                formatDescription: stream?.mixer.videoIO.decoder.formatDescription,
                sampleCount: 1, sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 1,
                sampleSizeArray: &sampleSizes,
                sampleBufferOut: &sampleBuffer) == noErr else {
                return
            }
            let status = (stream?.mixer.videoIO.decoder.decodeSampleBuffer(sampleBuffer!))!
        }
    }
}

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
        if let data: ElementaryStreamSpecificData = dictionaryForESSpecData[packet.PID] {
            readPacketizedElementaryStream(data, packet: packet)
        }
    }
    
    func readPacketizedElementaryStream(_ data: ElementaryStreamSpecificData, packet: TSPacket) {        
        if packet.payloadUnitStartIndicator {
            if let PES: PacketizedElementaryStream = packetizedElementaryStreams[packet.PID] {
                delegate?.didReadPacketizedElementaryStream(data, PES: PES)
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

extension AVCConfigurationRecord {
    mutating func setData(_ data:Data) {
        let buffer = ByteArray(data: data)
        do {
            // 1, 100, 8, 31, 255, 225(0x0E=1), [0,26], 103,
            self.configurationVersion = 1
            self.AVCProfileIndication = 100
            self.profileCompatibility = 8
            self.AVCLevelIndication = 31
            self.lengthSizeMinusOneWithReserved = 255
            self.numOfSequenceParameterSetsWithReserved = 225
                
            //0, 0, 0, 1,
            //103, 100, 8, 31, 172, 217, 64, 240, 17, 126, 240, 17, 0, 0, 3, 0, 1, 0, 0, 3, 0, 60, 15, 24, 49, 150,
            //0, 0, 0, 1,
            //104, 235, 227, 203, 34, 192
            _ = try buffer.readBytes(4)
            self.sequenceParameterSets.append(try buffer.readBytes(26).bytes)
            _ = try buffer.readBytes(4)
            self.pictureParameterSets.append(try buffer.readBytes(6).bytes)
        } catch {
            logger.error("\(buffer)")
        }
    }
}
