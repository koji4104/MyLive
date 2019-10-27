import AVFoundation

extension CIImage {
    func cropImage(rect:CGRect) -> CIImage {
        UIGraphicsBeginImageContext(CGSize(width:rect.size.width, height:rect.size.height))
        let filter:CIFilter! = CIFilter(name: "CICrop")
        filter.setValue(self, forKey:kCIInputImageKey)
        filter.setValue(CIVector(cgRect:rect), forKey:"inputRectangle")
        let ciContext:CIContext = CIContext(options: nil)
        let cgImage = ciContext.createCGImage(filter!.outputImage!, from:filter!.outputImage!.extent)!
        UIGraphicsEndImageContext()
        return CIImage(cgImage:cgImage)
    }
    func copyImage() -> CIImage {
        let uiImage:UIImage = UIImage(ciImage: self)
        UIGraphicsBeginImageContext(self.extent.size)
        uiImage.draw(in: self.extent)
        let copyImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return CIImage(cgImage:copyImage.cgImage!)
    }
}

extension CGRect {
    func scaled(sz:CGSize) -> CGRect {
        return CGRect(
            x: self.origin.x * sz.width,
            y: self.origin.y * sz.height,
            width: self.size.width * sz.width,
            height: self.size.height * sz.height
        )
    }
    func upsidedown(h:CGFloat) -> CGRect {
        return CGRect(
            x: self.origin.x,
            y: (h - self.size.height - self.origin.y),
            width: self.size.width,
            height: self.size.height
        )
    }
    func expanded() -> CGRect {
        let b:CGFloat = self.width/8
        return CGRect(
            x: self.minX-(b*1),
            y: self.minY-(b*3),
            width: self.size.width+(b*2),
            height: self.size.height+(b*4)
        )
    }
}

extension CGPoint {
    func scaled(sz: CGSize) -> CGPoint {
        return CGPoint(x:self.x * sz.width, y: self.y * sz.height)
    }
    func upsidedown(h:CGFloat) -> CGPoint {
        return CGPoint(x:self.x, y:h-self.y)
    }
}

extension ViewController {
    func makeSampleBuffer(from pixelBuffer: CVPixelBuffer, at frameTime: CMTime) -> CMSampleBuffer?
    {
        // CVPixelBufferからのCMVideoFormatDescriptionの作成
        var description:CMVideoFormatDescription?
        var status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &description)

        guard let _description:CMVideoFormatDescription = description else {
            return nil
        }

        // CVPixelBufferからのCMSampleBufferの作成
        var sampleBuffer:CMSampleBuffer?
        var timing:CMSampleTimingInfo = CMSampleTimingInfo()
        timing.presentationTimeStamp = frameTime
        status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: _description,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
    
    /// クロップ
    func cropThumbnailImage(image :UIImage, w:Int, h:Int) ->UIImage {
        // リサイズ処理
        let origRef    = image.cgImage
        let origWidth  = Int(origRef!.width)
        let origHeight = Int(origRef!.height)
        var resizeWidth:Int = 0, resizeHeight:Int = 0
        
        if (origWidth < origHeight) {
            resizeWidth = w
            resizeHeight = origHeight * resizeWidth / origWidth
        } else {
            resizeHeight = h
            resizeWidth = origWidth * resizeHeight / origHeight
        }
        
        let resizeSize = CGSize.init(width: CGFloat(resizeWidth), height: CGFloat(resizeHeight))
        UIGraphicsBeginImageContext(resizeSize)
        image.draw(in: CGRect.init(x: 0, y: 0, width: CGFloat(resizeWidth), height: CGFloat(resizeHeight)))
        let resizeImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // 切り抜き処理
        let cropRect  = CGRect.init(x: CGFloat((resizeWidth - w) / 2), y: CGFloat((resizeHeight - h) / 2), width: CGFloat(w), height: CGFloat(h))
        let cropRef   = resizeImage!.cgImage!.cropping(to: cropRect)
        let cropImage = UIImage(cgImage: cropRef!)
        return cropImage
    }
    
    func convertFromCIImageToCVPixelBuffer (ciImage:CIImage) -> CVPixelBuffer? {
        let size:CGSize = ciImage.extent.size
        var pixelBuffer:CVPixelBuffer?
        let options = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ] as [String : Any]
        
        let status:CVReturn = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &pixelBuffer)
        
        let ciContext = CIContext()
        if (status == kCVReturnSuccess && pixelBuffer != nil) {
            ciContext.render(ciImage, to: pixelBuffer!)
        }
        return pixelBuffer
    }
}

extension UIDevice {
    // Return Cpu Cores
    var cpuCores: Int {
        var r = Int(self.getSysInfo(typeSpecifier:HW_NCPU))
        if (r==0) { r=1 }
        return r
    }
    func getSysInfo(typeSpecifier: Int32) -> Int {
        var size: size_t = MemoryLayout<Int>.size
        var results: Int = 0
        var mib: [Int32] = [CTL_HW, typeSpecifier]
        sysctl(&mib, 2, &results, &size, nil,0)
        return results
    }
}
