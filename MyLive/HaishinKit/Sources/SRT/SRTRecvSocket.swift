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
    var olddts: UInt64 = 0
    var framesec: UInt64 = 33
    
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
    // func enqueueSampleBuffer(_ stream: RTMPStream)
    final public func didReadPacketizedElementaryStream(_ data1: ElementaryStreamSpecificData, PES: PacketizedElementaryStream) {

        let pts: UInt64 = PES.optionalPESHeader!.PTS
        if pts < 1 {
            logger.error("no PTS")
            return
        }
        
        let dts: UInt64 = PES.optionalPESHeader!.DTS
        if dts > 0 {
            if olddts > 0 {
                framesec = dts - olddts
            }
            olddts = dts
        } else {
            olddts += framesec
        }
         
        var timing = CMSampleTimingInfo(
            duration: CMTimeMake(value: Int64(framesec), timescale: 1000),
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
            _ = (stream?.mixer.videoIO.decoder.decodeSampleBuffer(sampleBuffer!))!
        }
    }
}

protocol TSReader2Delegate: class {
    func didReadPacketizedElementaryStream(_ data: ElementaryStreamSpecificData, PES: PacketizedElementaryStream)
}

class TSReader2 {
    weak var delegate: TSReader2Delegate?

    private(set) var numberOfPackets: Int = 0

    private var eof: UInt64 = 0
    private var cursor: Int = 0
    private var fileHandle: FileHandle?
    private var dictionaryForPrograms: [UInt16: UInt16] = [: ]
    private var dictionaryForESSpecData: [UInt16: ElementaryStreamSpecificData] = [: ]
    private var packetizedElementaryStreams: [UInt16: PacketizedElementaryStream] = [: ]
    
    var PCR: UInt64 = 0
    
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

        // PCR (Program Clock Reference)
        if packet.adaptationFieldFlag && packet.adaptationField!.PCRFlag {
            let buf = ByteArray(data: packet.adaptationField!.PCR)
            do {
                let pcr = TSProgramClockReference.decode(try buf.readBytes(buf.length))
                PCR = pcr.0 * 1000 / UInt64(TSProgramClockReference.resolutionForBase)
            } catch {
                logger.error("\(buf)")
            }
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
    
    func close() {
        fileHandle?.closeFile()
    }
}

extension AVCConfigurationRecord {
    mutating func setData(_ data:Data) {
        let buffer = ByteArray(data: data)
        do {
            // 1, 100, 8, 31, 255, 225(0x0E=1), [0,26]
            self.configurationVersion = 1
            self.AVCProfileIndication = 100
            self.profileCompatibility = 8
            self.AVCLevelIndication = 31
            self.lengthSizeMinusOneWithReserved = 255
            self.numOfSequenceParameterSetsWithReserved = 225
                
            _ = try buffer.readBytes(4)
            self.sequenceParameterSets.append(try buffer.readBytes(26).bytes)
            _ = try buffer.readBytes(4)
            self.pictureParameterSets.append(try buffer.readBytes(6).bytes)
        } catch {
            logger.error("\(buffer)")
        }
    }
}

extension PESOptionalHeader {
    var PTS: UInt64 {
        get {
            var pts: UInt64 = 0
            do {
                let buffer = ByteArray(data: optionalFields)
                if (PTSDTSIndicator & 0x02) == 0x02 {
                    pts = TSTimestamp.decode(try buffer.readBytes(5)) * 1000 / UInt64(TSTimestamp.resolution)
                }
            } catch { }
            return pts
        }
    }
    var DTS: UInt64 {
        get {
            var dts: UInt64 = 0
            do {
                let buffer = ByteArray(data: optionalFields)
                if (PTSDTSIndicator & 0x01) == 0x01 {
                    _ = TSTimestamp.decode(try buffer.readBytes(5))
                    dts = TSTimestamp.decode(try buffer.readBytes(5)) * 1000 / UInt64(TSTimestamp.resolution)
                }
            } catch { }
            return dts
        }
    }    
}
