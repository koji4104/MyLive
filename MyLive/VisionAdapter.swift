import UIKit
import AVFoundation
import Vision

//-------------------------------------
// Vision Adapter
//-------------------------------------
class VisionAdapter {
    
    let faceDetection = VNDetectFaceRectanglesRequest()
    let faceLandmarks = VNDetectFaceLandmarksRequest()
    let faceLandmarksDetectionRequest = VNSequenceRequestHandler()
    let faceDetectionRequest = VNSequenceRequestHandler()
    
    public var rcView:CGRect = CGRect(x:0,y:0,width:1,height:1)
    public var rcRect:CGRect = CGRect(x:0,y:0,width:1,height:1)
    
    /// Results
    public var results:[Result] = []
    struct Result {
        public var bounds:CGRect = CGRect(x:0,y:0,width:1,height:1)
        
        public var bzFaceContour:UIBezierPath = UIBezierPath()
        public var bzLeftEye:UIBezierPath = UIBezierPath()
        public var bzRightEye:UIBezierPath = UIBezierPath()
        public var bzInnerLips:UIBezierPath = UIBezierPath()
        public var bzNose:UIBezierPath = UIBezierPath()
        public var bzLeftEyebrow:UIBezierPath = UIBezierPath()
        public var bzRightEyebrow:UIBezierPath = UIBezierPath()
        public var bzNoseCrest:UIBezierPath = UIBezierPath()
        public var bzOuterLips:UIBezierPath = UIBezierPath()
        public var bzMedianLine:UIBezierPath = UIBezierPath()
        public var bzLeftPupil:UIBezierPath = UIBezierPath()
        public var bzRightPupil:UIBezierPath = UIBezierPath()
    }

    /// 顔の検出
    func detectFace(on image: CIImage) {
        try? self.faceDetectionRequest.perform([self.faceDetection], on:image)
        if let results1 = self.faceDetection.results as? [VNFaceObservation] {
            if !results1.isEmpty {
                self.faceLandmarks.inputFaceObservations = results1
                
                let ar:[Result] = self.results
                self.detectLandmarks(on: image)
                
                let w:CGFloat = 12
                for (index, r2) in self.results.enumerated() {
                    for r1 in ar {
                        if abs(r2.bzLeftEye.bounds.midX  - r1.bzLeftEye.bounds.midX)  < w
                        && abs(r2.bzLeftEye.bounds.midY  - r1.bzLeftEye.bounds.midY)  < w
                        && abs(r2.bzRightEye.bounds.midX - r1.bzRightEye.bounds.midX) < w
                        && abs(r2.bzRightEye.bounds.midY - r1.bzRightEye.bounds.midY) < w {
                            self.results[index] = r1
                        }
                    }
                }
            } else {
                self.results.removeAll()
            }
        }
    }
    
    /// 顔特徴の検出
    func detectLandmarks(on image: CIImage) {
        var ar:[Result] = []
        self.rcView = image.extent
        try? faceLandmarksDetectionRequest.perform([faceLandmarks], on: image)
        if let landmarksResults = faceLandmarks.results as? [VNFaceObservation] {
            for observation in landmarksResults {

                self.rcRect = observation.boundingBox.scaled(sz:image.extent.size)
                let lm:VNFaceLandmarks2D? = observation.landmarks
                var r:Result = Result()
                r.bounds = self.rcRect.upsidedown(h:self.rcView.size.height)
                
                r.bzFaceContour = self.convertPoints(lm?.faceContour, false)
                r.bzLeftEyebrow = self.convertPoints(lm?.leftEyebrow, false)
                r.bzRightEyebrow = self.convertPoints(lm?.rightEyebrow, false)
                r.bzMedianLine = self.convertPoints(lm?.medianLine, false)
                r.bzNoseCrest = self.convertPoints(lm?.noseCrest, false)
                r.bzLeftEye = self.convertPoints(lm?.leftEye, true)
                r.bzRightEye = self.convertPoints(lm?.rightEye, true)
                r.bzNose = self.convertPoints(lm?.nose, true)
                r.bzInnerLips = self.convertPoints(lm?.innerLips, true)
                r.bzOuterLips = self.convertPoints(lm?.outerLips, true)
                r.bzLeftPupil = self.convertPoints(lm?.leftPupil, true)
                r.bzRightPupil = self.convertPoints(lm?.rightPupil, true)
                
                ar.append(r)
            }
        }
        self.results = ar
    }
    
    /// 座標をベジェに変換
    func convertPoints(_ landmark: VNFaceLandmarkRegion2D?, _ close: Bool) -> UIBezierPath {
        let path = UIBezierPath()
        if let points = landmark?.normalizedPoints {
            let pt0 = self.convert(points[0])
            path.move(to: pt0)
            for i in 0..<points.count - 1 {
                let pt = self.convert(points[i])
                path.addLine(to: pt)
            }
            if close {
                path.addLine(to: pt0)
            }
        }
        return path
    }
    
    /// 比率をピクセルに変換、上下を変換
    func convert(_ p:CGPoint) -> CGPoint {
        var pt = CGPoint(x:p.x * self.rcRect.width + self.rcRect.origin.x,
                         y:p.y * self.rcRect.height + self.rcRect.origin.y)
        pt = pt.upsidedown(h:self.rcView.height)
        return pt
    }
}
