import UIKit
import AVFoundation
import Photos
import VideoToolbox //def kVTProfileLevel_H264_High_3_1

let sampleRate:Double = 44_100

class ViewController: UIViewController {
    let test:Bool = true // テストソース
    let recv:Bool = false
    let record:Bool = false
        
    var httpStream:HTTPStream!
    var httpService:HLSService!

    var rtmpConnection:RTMPConnection!
    var rtmpStream:RTMPStream!
    
    var srtConnection:SRTConnection!
    var srtStream:SRTStream!

    var netStream:NetStream!
    
    @IBOutlet weak var myView: GLHKView!
    
    @IBOutlet weak var segBps:UISegmentedControl!
    @IBOutlet weak var segFps:UISegmentedControl!
    @IBOutlet weak var segZoom:UISegmentedControl!
    
    @IBOutlet weak var btnPublish:CircleButton!
    @IBOutlet weak var btnSettings:RoundRectButton!
    @IBOutlet weak var btnTurn:RoundRectButton!
    @IBOutlet weak var btnOption:RoundRectButton!
    @IBOutlet weak var btnAudio:RoundRectButton!
    @IBOutlet weak var btnFace:RoundRectButton!
    @IBOutlet weak var btnRotLock: RoundRectButton!
    
    var timer:Timer!
    var date1:Date = Date()
    var isPublish:Bool = false
    var isOption:Bool = false
    var isOrientation = true

    var timer2:Timer!
    var frameCount:Int = 0
    
    /// 初期化
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    /// ステータスバー白文字
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return UIStatusBarStyle.lightContent
    }
    
    /// 画面表示
    override func viewWillAppear(_ animated: Bool) {
        logger.info("viewWillAppear")
        super.viewWillAppear(animated)

        initControl()
        
        NotificationCenter.default.addObserver(
            self,
            selector:#selector(self.onOrientationChange(_:)),
            name: UIDevice.orientationDidChangeNotification, // swift4.2
            object: nil)
    }
    
    /// 画面消去
    override func viewWillDisappear(_ animated: Bool) {
        logger.info("viewWillDisappear")
        super.viewWillDisappear(animated)
        
        closeStream()
        
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification, // swift4.2
            object: nil)
    }
        
    /// コントロール初期値
    public func initControl() {
        let env = Environment()
        if (record == true) {
            self.netStream = NetStream()
        }else if (env.isRtmp()) {
            self.rtmpConnection = RTMPConnection()
            self.rtmpStream = RTMPStream(connection: rtmpConnection)
        } else if (env.isSrt()) {
            self.srtConnection = .init()
            self.srtStream = SRTStream(srtConnection)
            self.srtConnection?.attachStream(srtStream)
        } else {
            self.httpService = HLSService(domain: "", type: "_http._tcp", name: "my", port: 8080)
            self.httpStream = HTTPStream()
        }
        
        //currentStream.syncOrientation = false / Haishin 1.0.3
        
        print("env.videoHeight \(env.videoHeight)")
        var preset:String = AVCaptureSession.Preset.hd1920x1080.rawValue
        if(env.videoHeight<=540) {
            preset = AVCaptureSession.Preset.iFrame960x540.rawValue
        } else if(env.videoHeight<=720) {
            preset = AVCaptureSession.Preset.hd1280x720.rawValue
        }
        
        currentStream.captureSettings = [
            .sessionPreset: preset,
            .continuousAutofocus: true,
            .continuousExposure: true,
            .fps: env.videoFramerate, // def=30
        ]

        // Codec/H264Encoder.swift
        currentStream.videoSettings = [
            .width: env.videoHeight/9 * 16,
            .height: env.videoHeight,
            .profileLevel: kVTProfileLevel_H264_High_AutoLevel,
            .maxKeyFrameIntervalDuration: 2.0, // 2.0
            .bitrate: env.videoBitrate * 1024, // Average
            //.dataRateLimits: [2000*1024 / 8, 1], // MaxBitrate / Haishin 1.0.3
        ]
        currentStream.audioSettings = [
            .sampleRate: sampleRate,
            .bitrate: 64 * 1024,
            .muted: (env.audioMode == 0) ? true : false,
            //"profile": UInt32(MPEG4ObjectID.AAC_LC.rawValue), err ios12
        ]
        
        let pos:AVCaptureDevice.Position = (env.cameraPosition==0) ? .back : .front
        currentStream.attachCamera(DeviceUtil.device(withPosition:pos)) { error in
            logger.warn(error.description)
        }
        currentStream.attachAudio(AVCaptureDevice.default(for: .audio),
            automaticallyConfiguresApplicationAudioSession: true) { error in
            logger.warn(error.description)
        }
        
        setOrientation()
        myView?.attachStream(currentStream)
         
        if (record == true) {
            if test == true {
                currentStream.recorderSettings = [
                    AVMediaType.video: [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoHeightKey: 0,
                        AVVideoWidthKey: 0,
                    ]
                ]
            } else {
                currentStream.recorderSettings = [
                    AVMediaType.audio: [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 0,
                        AVNumberOfChannelsKey: 0,
                        // AVEncoderBitRateKey: 128000,
                    ],
                    AVMediaType.video: [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoHeightKey: 0,
                        AVVideoWidthKey: 0,
                        //AVVideoCompressionPropertiesKey: [
                        //    AVVideoMaxKeyFrameIntervalDurationKey: 2,
                        //    AVVideoProfileLevelKey: AVVideoProfileLevelH264Baseline30,
                        //    AVVideoAverageBitRateKey: 512000
                        //]
                    ],
                ]
            }
            currentStream.mixer.recorder.delegate = ExampleRecorderDelegate.default
        }
        
        if test || recv {
            currentStream.mixer.videoIO.ex.test = true
        }
        
        switch env.videoBitrate {
        case  250: segBps.selectedSegmentIndex = 0
        case  500: segBps.selectedSegmentIndex = 1
        case 1000: segBps.selectedSegmentIndex = 2
        case 2000: segBps.selectedSegmentIndex = 3
        default: break
        }
        switch env.videoFramerate {
        case  5: segFps.selectedSegmentIndex = 0
        case 10: segFps.selectedSegmentIndex = 1
        case 15: segFps.selectedSegmentIndex = 2
        case 30: segFps.selectedSegmentIndex = 3
        default: break
        }
        switch env.zoom {
        case 100: segZoom.selectedSegmentIndex = 0
        case 200: segZoom.selectedSegmentIndex = 1
        case 300: segZoom.selectedSegmentIndex = 2
        case 400: segZoom.selectedSegmentIndex = 3
        default: break
        }
        
        // タイマー
        timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector:#selector(self.onTimer(_:)), userInfo: nil, repeats: true)
        timer.fire()
        
        // タイマー
        timer2 = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector:#selector(self.onTestTimer(_:)), userInfo: nil, repeats: true)
        if test == true {
            timer2.fire()
        }
    }
    
    func closeStream() {
        if timer.isValid == true { timer.invalidate() }
        if timer2.isValid == true { timer2.invalidate() }
        changePublish(false)

        if netStream != nil {
            netStream.dispose()
            netStream = nil
        }
        if rtmpStream != nil {
            rtmpStream.close()
            rtmpStream.dispose()
            rtmpStream = nil
        }
        if srtStream != nil {
            srtStream.close()
            srtStream.dispose()
            srtStream = nil
        }
        if httpStream != nil {
            httpStream.dispose()
            httpStream = nil
        }
    }
    
    var currentStream: NetStream! {
        get {
            let env = Environment()
            if (record == true) {
                return netStream
            } else if (env.isRtmp()) {
                return rtmpStream
            } else if (env.isSrt()) {
                return srtStream
            } else {
                return httpStream
            }
        }
    }

    /// 回転の有効無効
    override var shouldAutorotate: Bool {
        get {
            return self.isOrientation
        }
    }
    
    /// 端末の向きは横方向固定（受け側が縦に対応していないため）
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        get {
            return .landscape
        }
    }

    /// 端末の向きが変わったとき
    @objc func onOrientationChange(_ notification: Notification) {
        if self.isOrientation == true {
            setOrientation()
        }
    }

    func setOrientation() {
        if (UIApplication.shared.statusBarOrientation == .landscapeLeft) {
            currentStream.orientation = .landscapeLeft
        } else if (UIApplication.shared.statusBarOrientation == .landscapeRight) {
            currentStream.orientation = .landscapeRight
        }
        if currentStream.orientation == .portrait
            || currentStream.orientation == .portraitUpsideDown {
            currentStream.orientation = .landscapeRight
        }
    }
    
    /// パブリッシュ
    @IBAction func publishTouchUpInside(_ sender: UIButton) {
        if liveState == .publishing || liveState == .listening {
            changePublish(false)
        } else {
            changePublish(true)
        }
        
        self.btnPublish.isEnabled = false
        self.btnPublish.layer.borderColor = UIColor.blue.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now()+1) {
            self.btnPublish.isEnabled = true
            self.btnPublish.layer.borderColor = UIColor.black.cgColor
        }
    }
        
    func changePublish(_ publish: Bool) {
        let env = Environment()
        if record == true && netStream != nil {
            if publish == true {
                netStream.mixer.recorder.fileName = "mylive"
                netStream.mixer.recorder.startRunning()
            } else {
                netStream.mixer.recorder.stopRunning()
            }
        } else if env.isHls() && httpStream != nil {
            if publish == true {
                httpStream.publish("my")
                httpService.startRunning()
                httpService.addHTTPStream(httpStream)
            } else {
                httpStream.publish(nil)
                httpService.stopRunning()
                httpService.removeHTTPStream(httpStream)
            }
        } else if env.isRtmp() && rtmpStream != nil {
            if publish == true {
                
                //rtmpConnection.addEventListener(
                //    Event.RTMP_STATUS,
                //    selector:#selector(self.rtmpStatusHandler(_:)),
                //    observer: self)
                
                rtmpConnection.addEventListener(
                    .rtmpStatus,
                    selector:#selector(self.rtmpStatusHandler(_:)),
                    observer: self)
                
                rtmpConnection.connect(env.getUrl())
            } else {
                rtmpConnection.close()
                
                //rtmpConnection.removeEventListener(
                //    Event.RTMP_STATUS,
                //    selector:#selector(self.rtmpStatusHandler(_:)),
                //    observer: self)
            
                rtmpConnection.removeEventListener(
                    .rtmpStatus,
                    selector:#selector(self.rtmpStatusHandler(_:)),
                    observer: self)
                    
            }
        } else if env.isSrt() && srtStream != nil {
            if publish == true {
                srtStream.publish("my")
                if recv == false {
                    srtConnection.connect(URL(string: env.getUrl()))
                } else {
                    self.srtConnection?.attachStream(srtStream)
                    
                    srtStream.mixer.stopEncoding()
                    //stream?.mixer.startPlaying(rtmpConnection.audioEngine)
                    srtStream.mixer.startRunning()
                    srtStream.mixer.videoIO.queue.startRunning()

                    srtConnection.play(URL(string: env.getUrl()))
                }
            } else {
                srtConnection.close()
            }
        }
    }
    
    @objc func rtmpStatusHandler(_ notification:Notification) {
        let e:Event = Event.from(notification)
        if recv == false {
            if let data:ASObject = e.data as? ASObject, let code:String = data["code"] as? String {
                switch code {
                case RTMPConnection.Code.connectSuccess.rawValue:
                    let env = Environment()
                    print("key \(env.getKey())")
                    rtmpStream!.publish(env.getKey())
                default:
                    break
                }
            }
        } else {
            guard
                let data: ASObject = e.data as? ASObject,
                let code: String = data["code"] as? String else {
                    return
            }
            switch code {
            case RTMPConnection.Code.connectSuccess.rawValue:
                let env = Environment()
                rtmpStream!.play(env.getKey())
            default:
                break
            }
        }
    }
    
    /// ボタンの状態
    enum LiveState {
        case closed
        case publishing
        case listening
        case initialized
    }
    public var liveState:LiveState = .initialized
    func changeButtonState(_ st: LiveState) {
        if st == .publishing {
            self.btnPublish.backgroundColor = UIColor.red
            self.btnPublish.layer.borderColor = UIColor.black.cgColor
            if self.isPublish == false {
                date1 = Date()
                aryFps.removeAll(keepingCapacity: true)
                isAutoLow = false
            }
            self.isPublish = true
        } else if st == .closed {
            self.btnPublish.backgroundColor = UIColor.white
            self.btnPublish.layer.borderColor = UIColor.black.cgColor
            if self.isPublish == true {
                changePublish(false)
            }
            self.isPublish = false
        } else if st == .listening {
            self.btnPublish.backgroundColor = UIColor.white
            self.btnPublish.layer.borderColor = UIColor.blue.cgColor
        }
        liveState = st
    }   

    /// タイマー
    // MARK: onTimer
    var aryFps:[Int] = []
    var isAutoLow:Bool = false
    var nDispCpu = 1
    @objc func onTimer(_ tm: Timer) {
        if currentStream == nil {
            return
        }
        let env = Environment()
        if (isPublish == true) {
            if (env.isRtmp() && rtmpStream != nil && rtmpStream.currentFPS >= 0) {
                // RTMP 自動低画質
                let f:Int = Int(rtmpStream.currentFPS)
                if (env.lowimageMode>0 && f>=2) {
                    aryFps.append(f)
                    if (aryFps.count > 10) {
                        aryFps.removeFirst()
                        var sum:Int=0
                        for (_, element) in aryFps.enumerated() {
                            sum += element
                        }
                        let avg:Int = sum / aryFps.count
                        if (isAutoLow==false && env.videoFramerate-avg >= 5) {
                            //rtmpStream.videoSettings["bitrate"] = (env.videoBitrate/2) * 1024
                            rtmpStream.videoSettings = [.bitrate: (env.videoBitrate/2) * 1024]
                                
                            aryFps.removeAll(keepingCapacity: true)
                            isAutoLow = true
                        } else if (isAutoLow==true && env.videoFramerate-avg <= 2) {
                            //rtmpStream.videoSettings["bitrate"] = (env.videoBitrate) * 1024
                            rtmpStream.videoSettings = [.bitrate: (env.videoBitrate) * 1024]
                            
                            aryFps.removeAll(keepingCapacity: true)
                            isAutoLow = false
                        }
                    }
                }
            }
        }
        
        // 配信方式
        var state:String = ""
        if record == true {
            titleRps.text = "REC"
            labelRps.text = ""
            if currentStream != nil && currentStream.mixer.recorder.isRunning.value {
                state = "publishing"
            }
        } else if env.isHls() {
            titleRps.text = "HLS"
            labelRps.text = ""
            if httpService != nil && httpService.isRunning.value {
                state = "publishing"
            }
        } else if env.isRtmp() {
            titleRps.text = "RTMP"
            if rtmpStream != nil {
                state = "\(rtmpStream.readyState)"
            }
        } else if env.isSrt() {
            titleRps.text = "SRT"
            if srtStream != nil && srtStream.readyState == .publishing {
                state = "publishing"
            } else if srtConnection != nil && srtConnection.listening {
                state = "listening"
            }    
        }
        labelRps.text = state
        if state == "publishing" {
            changeButtonState(.publishing)
        } else if state == "listening" {
            changeButtonState(.listening)
        } else {
            changeButtonState(.closed)
        }

        // 経過秒
        if (isPublish == true) {
            let elapsed = Int32(Date().timeIntervalSince(date1))
            if elapsed<120 {
                labelRps.text = labelRps.text! + "  \(elapsed)" + "sec"
            } else {
                labelRps.text = labelRps.text! + "  \(elapsed/60)" + "min"
            }
            // 自動停止
            if (env.publishTimeout > 0 && elapsed > env.publishTimeout) {
                changePublish(false) 
            }
        }
        
        // FPS
        if (env.isRtmp() && rtmpStream != nil && rtmpStream.currentFPS >= 0) {
            labelFps.text = "\(rtmpStream.currentFPS)"
        } else {
            labelFps.text = "\(currentStream.mixer.videoIO.ex.fps)"
        }
        
        // CPU
        nDispCpu += 1
        if nDispCpu >= 3 {
            nDispCpu = 0
            labelCpu.text = "\(getCPUPer())" + "%"
        }
    }

    var isTestCreated:Bool = false
    var uiTestImage:UIImage!
    @objc func onTestTimer(_ tm: Timer) {
        if test == false {
            return
        }
        let tw = 960
        let th = 540
        if isTestCreated == false {
            isTestCreated = true
            uiTestImage = cropThumbnailImage(image:UIImage(named:"TestImage")!, w:tw, h:th)
        }
        frameCount += 1
            
        UIGraphicsBeginImageContext(CGSize(width:tw, height:th))
        let context1 = UIGraphicsGetCurrentContext()!
        uiTestImage.draw(in:CGRect(x:0, y:0, width:tw, height:th))

        let font = UIFont.systemFont(ofSize: 30)
        let attrs = [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: UIColor.blue
        ]
        let text:String = String(frameCount)
        text.draw(at: CGPoint(x:100,y:100), withAttributes: attrs)

        UIGraphicsEndImageContext()
        let ciTestImage:CIImage = CIImage(cgImage: context1.makeImage()!)

        if isPublish == true {
            var pts = CMTimeMake(value: Int64(frameCount), timescale: 1)
            pts.flags = CMTimeFlags.init(rawValue: 3)
            
            let pxTestBuffer:CVPixelBuffer = convertFromCIImageToCVPixelBuffer(ciImage:ciTestImage)!
            
            currentStream.mixer.videoIO.encoder.encodeImageBuffer(
                pxTestBuffer,
                presentationTimeStamp: pts,
                duration: CMTimeMake(value: 0, timescale: 0))
            
            //let sampleBuffer = makeSampleBuffer(from: pxTestBuffer, at: pts)!
            //currentStream.mixer.recorder.appendSampleBuffer(sampleBuffer, mediaType: .video)

            currentStream.mixer.recorder.appendPixelBuffer(pxTestBuffer, withPresentationTime: pts)
        }
        if currentStream != nil {
            currentStream.mixer.videoIO.ex.test = true
            //currentStream.mixer.videoIO.drawable?.draw(image: ciTestImage)
            currentStream.mixer.videoIO.renderer?.render(image: ciTestImage)
        }
    }

    /// フレームレート
    @IBAction func onFpsChanged(_ sender: UISegmentedControl) {
        var fps:Double = 5.0
        switch sender.selectedSegmentIndex {
        case 0: fps = 5.0
        case 1: fps = 10.0
        case 2: fps = 15.0
        case 3: fps = 30.0
        default: break
        }
        let env = Environment()
        env.videoFramerate = Int(fps)
        //currentStream.captureSettings["fps"] = fps
        currentStream.captureSettings = [.fps: fps]
    }
    
    /// ビットレート
    @IBAction func onBpsChanged(_ sender: UISegmentedControl) {
        var bps:Int = 250
        switch sender.selectedSegmentIndex {
        case 0: bps = 250;
        case 1: bps = 500;
        case 2: bps = 1000;
        case 3: bps = 2000;
        default: break
        }
        let env = Environment()
        env.videoBitrate = bps
        //currentStream.videoSettings["bitrate"] = bps * 1024
        currentStream.videoSettings = [.bitrate: bps * 1024]
        aryFps.removeAll(keepingCapacity: true)
    }
    
    /// 解像度
    @IBAction func onHeightChanged(_ sender: UISegmentedControl) {
        var w:Int = 640
        var h:Int = 360
        switch sender.selectedSegmentIndex {
        case 0: h = 270
        case 1: h = 360
        case 2: h = 540
        case 3: h = 720
        default: break
        }      
        w = (h/9) * 16
        let env = Environment()
        env.videoHeight = h
        //currentStream.videoSettings = ["width":w, "height":h]
        currentStream.videoSettings = [.width:w, .height:h]
    }
  
    /// ズーム
    @IBAction func onZoomChanged(_ sender: UISegmentedControl) {
        var zoom:Int = 100
        switch sender.selectedSegmentIndex {
        case 0: zoom = 100
        case 1: zoom = 200
        case 2: zoom = 300
        case 3: zoom = 400
        default: break
        }
        // setZoomFactor（倍率1.0-100.0, アニメ, アニメのスピード）標準カメラは4倍まで
        let env = Environment()
        env.zoom = zoom
        currentStream.setZoomFactor(CGFloat(Double(zoom)/100.0), ramping: true, withRate: 2.0)
    }
    
    /// 設定画面
    // MARK: Settings
    @IBAction func settingsTouchUpInside(_ sender: UIButton) {
        viewWillDisappear(true)
        
        let vc: SettingsViewController = SettingsViewController()
        vc.mainView = self
        self.present(vc, animated: true, completion: nil)
    }

    /// 反転
    @IBAction func turnTouchUpInside(_ sender: Any) {
        let env = Environment()
        env.cameraPosition = (env.cameraPosition==0) ? 1 : 0
        let pos:AVCaptureDevice.Position = (env.cameraPosition==0) ? .back : .front 
        currentStream.attachCamera(DeviceUtil.device(withPosition: pos)) { error in
            logger.warn(error.description)
        }
    }
    
    /// オーディオ
    @IBAction func audioTouchUpInside(_ sender: Any) { 
        let env = Environment()
        env.audioMode = (env.audioMode==1) ? 0 : 1
        let b:Bool = (env.audioMode==1) ? true : false
        //currentStream.audioSettings = ["muted": !b]
        currentStream.audioSettings = [.muted: !b]
        btnAudio.setSwitch(b)
    }
    
    /// 回転無効
    @IBAction func rotlockTouchUpInside(_ sender: Any) {
        self.isOrientation = !self.isOrientation
        btnRotLock.setSwitch(!self.isOrientation)
    }
    
    /// 顔
    @IBAction func faceTouchUpInside(_ sender: UIButton) {
        if currentStream.mixer.videoIO.ex.detectType == .none {
            currentStream.mixer.videoIO.ex.detectType = .detectFace
            btnFace.setSwitch(true)
        } else {
            currentStream.mixer.videoIO.ex.detectType = .none
            btnFace.setSwitch(false)
        }
    }
    
    var labelCpu:ValueLabel = ValueLabel()
    var labelFps:ValueLabel = ValueLabel() 
    var labelRps:ValueLabel = ValueLabel() 
    var labelBg1:ValueLabel = ValueLabel()
    
    var titleCpu:TitleLabel = TitleLabel()
    var titleFps:TitleLabel = TitleLabel()
    var titleRps:TitleLabel = TitleLabel()
    
    /// ボタン位置
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 画面の幅高さ
        // ip5  568 320 (640x1136)
        // ip7  667 375 (750x1334)
        // 10.5 1112 834 (1668x2224)
        let vieww:Int = Int(self.myView.frame.width)
        let viewh:Int = Int(self.myView.frame.height)
        print("w=\(view.frame.width) h=\(view.frame.height) w=\(myView.frame.width) h=\(myView.frame.height)")
        
        let stbar:Int = 0
        let cy = viewh/2
        let btnw = Int(btnSettings.frame.width)

        let p:Int = 10
        let top = p + stbar/2
        let btnx = p + btnw/2
        btnPublish.center = CGPoint(x:vieww-btnx, y:cy)
        btnTurn.center = CGPoint(x:vieww-btnx, y:top+btnw/2)
        btnSettings.center = CGPoint(x:btnx, y:top+btnw/2)
        
        // ボタン
        var bottomy = viewh - p - btnw/2 + stbar/2
        let bw = btnw + 6
        btnOption.center = CGPoint(x:btnx+bw*0, y:bottomy)
        btnAudio.center  = CGPoint(x:btnx+bw*1, y:bottomy)
        btnFace.center   = CGPoint(x:btnx+bw*2, y:bottomy)
        btnRotLock.center   = CGPoint(x:btnx+bw*3, y:bottomy)
        
        btnRotLock.colOn = UIColor(red:0.8,green:0.1,blue:0.1,alpha:1.0)
        
        // セグメント
        let segw = Int(segBps.frame.width)
        let segx = p + segw/2
        let sh = Int(segBps.frame.height) + 8
        bottomy -= 56
        segBps.center  = CGPoint(x:segx, y:bottomy-sh*2)
        segFps.center  = CGPoint(x:segx, y:bottomy-sh*1)
        segZoom.center = CGPoint(x:segx, y:bottomy-sh*0)
        
        // ラベル
        let ly = Int(btnSettings.center.y)
        titleCpu.text = "CPU"
        titleFps.text = "FPS"
        titleRps.text = ""
        
        let lx1 = 120
        let lx2 = lx1 + 84
        let lx3 = lx2 + 76
        titleCpu.center = CGPoint(x:lx1, y:ly)
        titleFps.center = CGPoint(x:lx2, y:ly)
        titleRps.center = CGPoint(x:lx3, y:ly)
        
        labelRps.textAlignment = .left
        labelRps.frame.size = CGSize.init(width:220, height:25)
        
        labelCpu.center = CGPoint(x:Int(titleCpu.center.x)-6, y:ly)
        labelFps.center = CGPoint(x:Int(titleFps.center.x)-22, y:ly)
        labelRps.center = CGPoint(x:Int(titleRps.center.x)+130, y:ly)
        
        let cpux1 = Int(titleCpu.frame.minX + 360/2)
        labelBg1.frame.size = CGSize.init(width:380, height:28)
        labelBg1.center = CGPoint(x:cpux1, y:ly)
        labelBg1.backgroundColor = UIColor(red:0.0,green:0.0,blue:0.0,alpha:0.4)
        labelBg1.layer.cornerRadius = 4
        labelBg1.clipsToBounds = true
        
        // テスト用背景
        //if (test==true) {
        if (false) {
            let rect = CGRect(x:0, y:(viewh-(vieww*9/16))/2, width:vieww, height:vieww*9/16)
            let testImage = cropThumbnailImage(image:UIImage(named:"TestImage")!,
                               w:Int(rect.width),
                               h:Int(rect.height))
            let testView = UIImageView(image:testImage)
            testView.frame = rect
            self.myView.addSubview(testView)
            print("test y=\(rect.minY)-\(rect.maxY) w=\(rect.width) h=\(rect.height)")
        }
        
        self.myView.addSubview(labelFps)
        self.myView.addSubview(labelRps)
        self.myView.addSubview(labelCpu)
        self.myView.addSubview(titleCpu)
        self.myView.addSubview(titleFps)
        self.myView.addSubview(titleRps)
        self.myView.addSubview(labelBg1)
        
        self.myView.bringSubviewToFront(btnSettings)
        self.myView.bringSubviewToFront(btnTurn)
        self.myView.bringSubviewToFront(btnOption)
        self.myView.bringSubviewToFront(btnAudio)
        self.myView.bringSubviewToFront(btnPublish)
        self.myView.bringSubviewToFront(btnFace)
        self.myView.bringSubviewToFront(btnRotLock)
        
        self.myView.bringSubviewToFront(labelBg1)

        self.myView.bringSubviewToFront(labelFps)
        self.myView.bringSubviewToFront(labelRps)
        self.myView.bringSubviewToFront(labelCpu)
        
        self.myView.bringSubviewToFront(titleCpu)
        self.myView.bringSubviewToFront(titleFps)
        self.myView.bringSubviewToFront(titleRps)
        
        self.myView.bringSubviewToFront(segBps)
        self.myView.bringSubviewToFront(segFps)
        self.myView.bringSubviewToFront(segZoom)
        
        let env = Environment()
        btnAudio.setSwitch(env.audioMode==1)
        
        isOption = true
        optionButton(hidden:true)
    }
    
    /// 画質オプション
    @IBAction func optionTouchUpInside(_ sender: UIButton) {
        isOption = !isOption
        optionButton(hidden:isOption)
    }
    func optionButton(hidden:Bool) {
        btnAudio.hideLeft(b:hidden)
        btnFace.hideLeft(b:hidden)
        btnRotLock.hideLeft(b:hidden)
        segBps.hideLeft(b:hidden)
        segFps.hideLeft(b:hidden)
        segZoom.hideLeft(b:hidden)
    }
    
    /// CPU使用率（0-100%）
    var cpuCores:Int = UIDevice.current.cpuCores
    private func getCPUPer() -> Int {
        return Int(Int(getCPUUsage())/cpuCores)
    }
    private func getCPUUsage() -> Float {
        // カーネル処理の結果
        var result: Int32
        var threadList = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        var threadCount = UInt32(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        var threadInfo = thread_basic_info()
        // スレッド情報を取得
        result = withUnsafeMutablePointer(to: &threadList) {
            $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
            task_threads(mach_task_self_, $0, &threadCount)
            }
        }
        if result != KERN_SUCCESS { return 0 }
        // 各スレッドからCPU使用率を算出し合計を全体のCPU使用率とする
        return (0 ..< Int(threadCount))
            // スレッドのCPU使用率を取得
            .compactMap { index -> Float? in
                var threadInfoCount = UInt32(THREAD_INFO_MAX)
                result = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadList[index], UInt32(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                // スレッド情報が取れない = 該当スレッドのCPU使用率を0とみなす(基本nilが返ることはない)
                if result != KERN_SUCCESS { return nil }
                let isIdle = threadInfo.flags == TH_FLAGS_IDLE
                // CPU使用率がスケール調整済みのため`TH_USAGE_SCALE`で除算し戻す
                return !isIdle ? (Float(threadInfo.cpu_usage) / Float(TH_USAGE_SCALE)) * 100 : nil
            }
            // 合計算出
            .reduce(0, +)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

//------------------------------------------------------------
// Control
//------------------------------------------------------------
class TitleLabel: UILabel {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.font = UIFont.systemFont(ofSize:18)
        self.textAlignment = .left
        self.frame.size = CGSize.init(width:80, height:25)
        self.textColor = UIColor.green
    }
}

class ValueLabel: UILabel {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.font = UIFont.systemFont(ofSize:18)
        self.textAlignment = .right
        self.frame.size = CGSize.init(width:80, height:25)
        self.textColor = UIColor.white
    }
}

extension UIControl {
    public func hideLeft(b:Bool) {
        if (b==true) {
            UIView.animate(withDuration: 0.2, delay: 0.0, animations: {
                self.center.x -= 20
                self.alpha = 0
            }){_ in
                self.isHidden = b
            }
        } else {
            self.isHidden = b
            UIView.animate(withDuration: 0.2, delay: 0.0, animations: {
                self.center.x += 20
                self.alpha = 1.0
            }, completion: nil)
        }
    }
}

/// ボタン  
class MyButton: UIButton {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    open func myInit(width:CGFloat) {
        self.frame.size = CGSize.init(width:width, height:width)
        self.layer.cornerRadius = width/2
        self.center = CGPoint(x:0, y:0)
        self.imageEdgeInsets = UIEdgeInsets(top:10, left:10, bottom:10, right:10)
    }
}

class RoundRectButton: MyButton {
    var colOn: UIColor = UIColor(red:0.2,green:0.4,blue:0.8,alpha:1.0)
    var colOff: UIColor = UIColor(red:0.0,green:0.0,blue:0.0,alpha:0.5)
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.myInit(width:50)
        self.backgroundColor = colOff
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    public var isSwitch:Bool = true
    public func setSwitch(_ b:Bool) {
        isSwitch = b
        if isSwitch == true {
            self.backgroundColor = colOn
        } else {
            self.backgroundColor = colOff
        }
    }
}

class CircleButton: MyButton {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.myInit(width:60)
        self.backgroundColor = UIColor.white
        self.layer.borderColor = UIColor.black.cgColor
        self.layer.borderWidth = 8
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
}

/// セグメント
class MySegmentedControl: UISegmentedControl {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        self.tintColor = UIColor.white
        self.backgroundColor = UIColor(red:0.0,green:0.0,blue:0.0,alpha:0.3)
        
        self.frame.size = CGSize.init(width:220, height:30)  
        self.center = CGPoint(x:0, y:0)
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
}

//------------------------------------------------------------
// Recorder
//------------------------------------------------------------
final class ExampleRecorderDelegate: DefaultAVRecorderDelegate {
    static let `default` = ExampleRecorderDelegate()
    static let albumName = "MyLive"
    
    override func didStartRunning(_ recorder: AVRecorder) {
        ExampleRecorderDelegate.createAlbum()
    }
    
    override func didFinishWriting(_ recorder: AVRecorder) {
        guard let writer: AVAssetWriter = recorder.writer else { return }
        PHPhotoLibrary.shared().performChanges({() -> Void in
            if let album = ExampleRecorderDelegate.self.findAlbum() {
                let assetReq = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: writer.outputURL)
                if let asset = assetReq?.placeholderForCreatedAsset {
                    let request = PHAssetCollectionChangeRequest(for: album)
                    request?.addAssets([asset] as NSArray)
                }
            }
        }, completionHandler: { _, error -> Void in
            do {
                try FileManager.default.removeItem(at: writer.outputURL)
            } catch {
                print(error)
            }
        })
    }

    static func createAlbum() -> PHAssetCollection? {
        if let album = self.findAlbum() {
            return album
        } else {
            do {
                try PHPhotoLibrary.shared().performChangesAndWait({
                    PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                })
            } catch {
                print("Problem finding/creating album: ".appending(albumName))
                print(error)
            }
            return self.findAlbum()
        }
    }
    
    static func findAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        let findAlbumResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        return findAlbumResult.firstObject
    }    
}
