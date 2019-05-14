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

