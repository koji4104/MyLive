import UIKit
import AVFoundation
import Vision
import CoreML

/*
 Sources/Media/VideoIOComponent.swift line 444
 Sources/ISO/TSWriter.swift line 97
 */
class VideoIOComponentEx {
    var isDisplay:Bool = false
    
    enum DetectType {
        case none
        case detectFace
    }
    var detectType:DetectType = .none
    var detecting:Bool = false
    
    var fpsCount:Int = 0
    var fpsDate:Date = Date()
    public var fps = 0
    public var test:Bool = false
    public var vision = VisionAdapter()
}

extension VideoIOComponent {
    /// フレーム毎に呼ばれる
    func appendSampleBufferEx(_ sampleBuffer: CMSampleBuffer) {
        if ex.test == true {
          return
        }
        guard var buffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        // フレームレートを計算
        if self.ex.fpsCount == 50 {
            let elapsed:Double = Double(Date().timeIntervalSince(self.ex.fpsDate))
            self.ex.fps = Int(50.0/elapsed)
            self.ex.fpsCount = 0
            self.ex.fpsDate = Date()
        }
        self.ex.fpsCount += 1

        /// 検出
        switch ex.detectType {
        case .detectFace: detectFace(buffer:buffer)
        default: break
        }

        encoder.encodeImageBuffer(
            buffer,
            presentationTimeStamp: sampleBuffer.presentationTimeStamp,
            duration: sampleBuffer.duration
        )
        let image: CIImage = CIImage(cvPixelBuffer: buffer)
        drawable?.draw(image: image)

        mixer?.recorder.appendSampleBuffer(sampleBuffer, mediaType: .video)
    }
    
    /// 検出（顔）
    func detectFace(buffer:CVImageBuffer) {
        let ciImage:CIImage = CIImage(cvPixelBuffer: buffer)
        let uiImage:UIImage = UIImage(ciImage: ciImage)
        let sz:CGSize = uiImage.size
        
        if (self.ex.detecting == false) {
            self.ex.detecting = true
            DispatchQueue(label:"detecting.queue").async {
                let ciCopyImage = ciImage.copyImage()
                self.ex.vision.detectFace(on: ciCopyImage)
                usleep(64*1000) // 64ms
                self.ex.detecting = false
            }
        }
    
        UIGraphicsBeginImageContext(CGSize(width:sz.width, height:sz.height))
        let context1 = UIGraphicsGetCurrentContext()!
        uiImage.draw(in:CGRect(x:0, y:0, width:sz.width, height:sz.height))
        
        // 右目と左目に線を描画
        for r in self.ex.vision.results {
            let p1:CGPoint = CGPoint(x:r.bzLeftEye.bounds.midX, y:r.bzLeftEye.bounds.midY)
            let p2:CGPoint = CGPoint(x:r.bzRightEye.bounds.midX, y:r.bzRightEye.bounds.midY)
            let a = (p1.y-p2.y)/(p1.x-p2.x)
            let b = p1.y - (a*p1.x)
            let w:CGFloat = (r.bounds.size.width+40)/5
            let p3 = CGPoint(x:p1.x-w, y:a*(p1.x-w)+b)
            let p4 = CGPoint(x:p2.x+w, y:a*(p2.x+w)+b)
            
            UIColor.black.setStroke()
            let path = UIBezierPath()
            path.move(to: p3)
            path.addLine(to: p4)
            path.lineWidth = w-4
            path.stroke()
        }

        UIGraphicsEndImageContext()
        let ciImage1:CIImage = CIImage(cgImage:context1.makeImage()!)
        context?.render(ciImage1, to:buffer)
    }
}
