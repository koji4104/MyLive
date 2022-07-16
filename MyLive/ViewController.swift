import UIKit
import AVFoundation
import Photos
import VideoToolbox //def kVTProfileLevel_H264_High_3_1
import HaishinKit //2020-12

let sampleRate:Double = 44_100

class ViewController: UIViewController {
    let test:Bool = false // Test background
    let recv:Bool = false
        
    var httpStream:HTTPStream!
    var httpService:HLSService!
    var rtmpConnection:RTMPConnection!
    var rtmpStream:RTMPStream!
    var srtConnection:SRTConnection!
    var srtStream:SRTStream!
    
    @IBOutlet weak var myView: GLHKView!
    
    @IBOutlet weak var segBps:UISegmentedControl!
    @IBOutlet weak var segFps:UISegmentedControl!
    @IBOutlet weak var segZoom:UISegmentedControl!
    
    @IBOutlet weak var btnPublish:CircleButton!
    @IBOutlet weak var btnSettings:RoundRectButton!
    @IBOutlet weak var btnTurn:RoundRectButton!
    @IBOutlet weak var btnOption:RoundRectButton!
    @IBOutlet weak var btnAudio:RoundRectButton!
    @IBOutlet weak var btnRotLock: RoundRectButton!
    
    var timer:Timer!
    var date1:Date = Date()
    var isPublish:Bool = false
    var isOption:Bool = false
    var isOrientation = true
    var isLandscape = true
    
    var timerTest:Timer!
    var frameCount:Int = 0
    
    /// Initialization
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    /// Status bar white text
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return UIStatusBarStyle.lightContent
    }
    
    /// true = Hide status bar
    override var prefersStatusBarHidden: Bool {
        return true
    }

    /// Screen display
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        initControl()
        NotificationCenter.default.addObserver(self,
            selector: #selector(self.onOrientationChange(_:)),
            name: UIDevice.orientationDidChangeNotification, 
            object: nil)
    }
    
    /// Erase screen
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        closeStream()
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification, // swift4.2
            object: nil)
    }
        
    /// Control initial value
    public func initControl() {
        let env = Environment()
        if (env.isRtmp()) {
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
        } else if(env.videoHeight<=1080) {
            preset = AVCaptureSession.Preset.hd1920x1080.rawValue
        } else if(env.videoHeight<=2160) {
            preset = AVCaptureSession.Preset.hd4K3840x2160.rawValue
        }

        currentStream.captureSettings = [
            .sessionPreset: preset,
            .continuousAutofocus: true,
            .continuousExposure: true, 
            .fps: env.videoFramerate, // def=30
        ]

        // Codec/H264Encoder.swift
        currentStream.videoSettings = [
            .width: isLandscape ? env.videoHeight/9 * 16 : env.videoHeight,
            .height: isLandscape ? env.videoHeight : env.videoHeight/9 * 16,
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
            print(error.description)
        }
        currentStream.attachAudio(AVCaptureDevice.default(for: .audio),
            automaticallyConfiguresApplicationAudioSession: true) { error in
            print(error.description)
        }
        
        myView?.attachStream(currentStream)
        setOrientation()
        
        switch env.videoBitrate {
        case 1000: segBps.selectedSegmentIndex = 0
        case 2000: segBps.selectedSegmentIndex = 1
        case 4000: segBps.selectedSegmentIndex = 2
        case 8000: segBps.selectedSegmentIndex = 3
        default: break
        }
        switch env.videoFramerate {
        case 10: segFps.selectedSegmentIndex = 0
        case 20: segFps.selectedSegmentIndex = 1
        case 30: segFps.selectedSegmentIndex = 2
        case 60: segFps.selectedSegmentIndex = 3
        default: break
        }
        switch env.zoom {
        case 100: segZoom.selectedSegmentIndex = 0
        case 200: segZoom.selectedSegmentIndex = 1
        case 300: segZoom.selectedSegmentIndex = 2
        case 400: segZoom.selectedSegmentIndex = 3
        default: break
        }
        
        // Timer
        timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector:#selector(self.onTimer(_:)), userInfo: nil, repeats: true)
        timer.fire()
        
    }
    
    func closeStream() {
        if timer.isValid == true { timer.invalidate() }
        //if timerTest.isValid == true { timerTest.invalidate() }
        changePublish(false)

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
            if (env.isRtmp()) {
                return rtmpStream
            } else if (env.isSrt()) {
                return srtStream
            } else {
                return httpStream
            }
        }
    }

    /// Rotation enabled/disabled
    override var shouldAutorotate: Bool {
        get {
            return self.isOrientation
        }
    }
    
    /// The orientation is fixed in the horizontal direction
    //override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    //    get {
    //        return .landscape
    //    }
    //}

    /// When the direction changes
    @objc func onOrientationChange(_ notification: Notification) {
        if self.isOrientation == true {
            setOrientation()
        }
    }

    func setOrientation() {
        let env = Environment()
        if (env.cameraPosition==0) { 
            myView.isMirrored = false
        } else {
            myView.isMirrored = true
        }
        
        var isNowLandscape = true;
        if #available(iOS 13.0, *) {
            switch(self.view.window?.windowScene!.interfaceOrientation){
            case .landscapeLeft: currentStream.orientation = .landscapeLeft
            case .landscapeRight: currentStream.orientation = .landscapeRight
            case .portrait: currentStream.orientation = .portrait
                isNowLandscape = false
            case .portraitUpsideDown: currentStream.orientation = .portraitUpsideDown
                isNowLandscape = false
            default: break
            }
        } else {
            // Fallback on earlier versions
        }
        
        if(isLandscape != isNowLandscape){
            isLandscape = isNowLandscape
            currentStream.videoSettings = [
            .width: isLandscape ? env.videoHeight/9 * 16 : env.videoHeight,
            .height: isLandscape ? env.videoHeight : env.videoHeight/9 * 16,
            .profileLevel: kVTProfileLevel_H264_High_AutoLevel,
            .maxKeyFrameIntervalDuration: 2.0, // 2.0
            .bitrate: env.videoBitrate * 1024, // Average
            ]
        }
        /*
        if (UIApplication.shared.statusBarOrientation == .landscapeLeft) {
            currentStream.orientation = .landscapeLeft
        } else if (UIApplication.shared.statusBarOrientation == .landscapeRight) {
            currentStream.orientation = .landscapeRight
        } else if (UIApplication.shared.statusBarOrientation == .portrait) {
            currentStream.orientation = .portrait
        } else if (UIApplication.shared.statusBarOrientation == .portraitUpsideDown) {
            currentStream.orientation = .portraitUpsideDown
        }
         */
    }
    
    /// publish
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
        if env.isHls() && httpStream != nil {
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
                rtmpConnection.addEventListener(
                    .rtmpStatus,
                    selector:#selector(self.rtmpStatusHandler(_:)),
                    observer: self)
                rtmpConnection.connect(env.getUrl())
            } else {
                rtmpConnection.close()
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
                    // 2020-12 comment
                    //self.srtConnection?.attachStream(srtStream)
                    //srtStream.mixer.stopEncoding()
                    //srtStream.mixer.startRunning()
                    //srtStream.mixer.videoIO.queue.startRunning()
                    //srtConnection.play(URL(string: env.getUrl()))
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
    
    /// Button state
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
                // RTMP Automatic low image quality
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
                            rtmpStream.videoSettings = [.bitrate: (env.videoBitrate/2) * 1024]
                            aryFps.removeAll(keepingCapacity: true)
                            isAutoLow = true
                        } else if (isAutoLow==true && env.videoFramerate-avg <= 2) {
                            rtmpStream.videoSettings = [.bitrate: (env.videoBitrate) * 1024]
                            aryFps.removeAll(keepingCapacity: true)
                            isAutoLow = false
                        }
                    }
                }
            }
        }
        
        // Delivery method
        var state:String = ""
        if env.isHls() {
            titleRps.text = "HLS"
            if httpService != nil && httpService.isRunning.value {
                state = "publishing"
            }
        } else if env.isRtmp() {
            titleRps.text = "RTMP"
            if rtmpStream != nil {
                if rtmpConnection.totalStreamsCount>0 {
                    state = "publishing"
                }
            }
        } else if env.isSrt() {
            titleRps.text = "SRT"
            if srtStream != nil && srtStream.readyState == .publishing {
                state = "publishing"
            } else if srtConnection != nil && srtConnection.listening {
                state = "listening"
            }    
        }
        
        if env.isRtmp() {
            labelRps.text = "   " + state
        } else {
            labelRps.text = state
        }
        
        if state == "publishing" {
            changeButtonState(.publishing)
        } else if state == "listening" {
            changeButtonState(.listening)
        } else {
            changeButtonState(.closed)
        }

        // Elapsed seconds
        if (isPublish == true) {
            let elapsed = Int32(Date().timeIntervalSince(date1))
            if elapsed<120 {
                labelRps.text = labelRps.text! + "  \(elapsed)" + " sec"
            } else {
                labelRps.text = labelRps.text! + "  \(elapsed/60)" + " min"
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
            labelFps.text = "\(env.videoFramerate)"
        }
        
        // CPU
        nDispCpu += 1
        if nDispCpu >= 3 {
            nDispCpu = 0
            labelCpu.text = "\(getCPUPer())" + "%"
        }
    }

    /// frame rate
    @IBAction func onFpsChanged(_ sender: UISegmentedControl) {
        var fps:Double = 5.0
        switch sender.selectedSegmentIndex {
        case 0: fps = 10.0
        case 1: fps = 20.0
        case 2: fps = 30.0
        case 3: fps = 60.0
        default: break
        }
        let env = Environment()
        env.videoFramerate = Int(fps)
        currentStream.captureSettings = [.fps: fps]
    }
    
    /// bit rate
    @IBAction func onBpsChanged(_ sender: UISegmentedControl) {
        var bps:Int = 250
        switch sender.selectedSegmentIndex {
        case 0: bps = 1000;
        case 1: bps = 2000;
        case 2: bps = 4000;
        case 3: bps = 8000;
        default: break
        }
        let env = Environment()
        env.videoBitrate = bps
        currentStream.videoSettings = [.bitrate: bps * 1024]
        aryFps.removeAll(keepingCapacity: true)
    }
    
    /// 解像度
    @IBAction func onHeightChanged(_ sender: UISegmentedControl) {
        var w:Int = 1280
        var h:Int = 720
        switch sender.selectedSegmentIndex {
        case 0: h = 540
        case 1: h = 720
        case 2: h = 1080
        case 3: h = 2160
        default: break
        }      
        w = (h/9) * 16
        let env = Environment()
        env.videoHeight = h
        currentStream.videoSettings = [.width:w, .height:h]
    }
  
    /// Zoom
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
    
    /// Setting screen
    // MARK: Settings
    @IBAction func settingsTouchUpInside(_ sender: UIButton) {
        viewWillDisappear(true)
        let vc: SettingsViewController = SettingsViewController()
        vc.mainView = self
        self.present(vc, animated: true, completion: nil)
    }

    /// Inversion
    @IBAction func turnTouchUpInside(_ sender: Any) {
        let env = Environment()
        env.cameraPosition = (env.cameraPosition==0) ? 1 : 0
        let pos:AVCaptureDevice.Position = (env.cameraPosition==0) ? .back : .front 
        currentStream.attachCamera(DeviceUtil.device(withPosition: pos)) { error in
            print("-- " + error.description)
        }
        if (env.cameraPosition==0) { // back
            myView.isMirrored = false
        } else {
            myView.isMirrored = true
        }
    }
    
    /// audio
    @IBAction func audioTouchUpInside(_ sender: Any) { 
        let env = Environment()
        env.audioMode = (env.audioMode==1) ? 0 : 1
        let b:Bool = (env.audioMode==1) ? true : false
        currentStream.audioSettings = [.muted: !b]
        btnAudio.setSwitch(b)
    }
    
    /// Rotation disabled
    @IBAction func rotlockTouchUpInside(_ sender: Any) {
        self.isOrientation = !self.isOrientation
        btnRotLock.setSwitch(!self.isOrientation)
    }
    
    var labelCpu:ValueLabel = ValueLabel()
    var labelFps:ValueLabel = ValueLabel()
    var labelRps:ValueLabel = ValueLabel()
    var labelBg1:ValueLabel = ValueLabel()
    
    var titleCpu:TitleLabel = TitleLabel()
    var titleFps:TitleLabel = TitleLabel()
    var titleRps:TitleLabel = TitleLabel()
    
    /// Button position
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // ip5  568 320 (640x1136)
        // ip7  667 375 (750x1334)
        // 10.5 1112 834 (1668x2224)
        let vieww:Int = Int(self.view.frame.width)
        let viewh:Int = Int(self.view.frame.height)
        
        let stbar:Int = 0
        let cy = viewh/2
        let btnw = Int(btnSettings.frame.width)

        let px:Int = 36
        let py:Int = 18
        let top = py + stbar/2
        let btnx = px + btnw/2
        btnPublish.center = CGPoint(x:vieww-btnx, y:cy)
        btnTurn.center = CGPoint(x:vieww-btnx, y:top+btnw/2)
        btnSettings.center = CGPoint(x:btnx, y:top+btnw/2)
        
        // Button
        var bottomy = viewh - py - btnw/2 + stbar/2
        let bw = btnw + 6
        btnOption.center = CGPoint(x:btnx+bw*0, y:bottomy)
        btnAudio.center = CGPoint(x:btnx+bw*1, y:bottomy)
        btnRotLock.center = CGPoint(x:btnx+bw*2, y:bottomy)
        btnRotLock.colOn = UIColor(red:0.8,green:0.1,blue:0.1,alpha:1.0)
        
        // segment
        let segw = Int(segBps.frame.width)
        let segx = px + segw/2
        let sh = Int(segBps.frame.height) + 8
        bottomy -= 56
        segBps.center  = CGPoint(x:segx, y:bottomy-sh*2)
        segFps.center  = CGPoint(x:segx, y:bottomy-sh*1)
        segZoom.center = CGPoint(x:segx, y:bottomy-sh*0)
        
        // Label
        let ly = Int(btnSettings.center.y)
        titleCpu.text = "CPU"
        titleFps.text = "FPS"
        titleRps.text = ""
        
        let lx1 = 148
        let lx2 = lx1 + 84
        let lx3 = lx2 + 72
        titleCpu.center = CGPoint(x:lx1, y:ly)
        titleFps.center = CGPoint(x:lx2, y:ly)
        titleRps.center = CGPoint(x:lx3, y:ly)
        
        labelRps.textAlignment = .left
        labelRps.frame.size = CGSize.init(width:220, height:25)
        
        labelCpu.center = CGPoint(x:Int(titleCpu.center.x)-6, y:ly)
        labelFps.center = CGPoint(x:Int(titleFps.center.x)-22, y:ly)
        labelRps.center = CGPoint(x:Int(titleRps.center.x)+114, y:ly)
        
        let cpux1 = Int(titleCpu.frame.minX + 400/2 - 10)
        labelBg1.frame.size = CGSize.init(width:400, height:28)
        labelBg1.center = CGPoint(x:cpux1, y:ly)
        labelBg1.backgroundColor = UIColor(red:0.0,green:0.0,blue:0.0,alpha:0.4)
        labelBg1.layer.cornerRadius = 4
        labelBg1.clipsToBounds = true
        
        // Test background
        if (test==true) {
            let rect = CGRect(x:0, y:(viewh-(vieww*9/16))/2, width:vieww, height:vieww*9/16)
            let testImage = cropThumbnailImage(image:UIImage(named:"TestImage")!,
                               w:Int(rect.width),
                               h:Int(rect.height))
            let testView = UIImageView(image:testImage)
            testView.frame = rect
            self.view.addSubview(testView)
            print("test y=\(rect.minY)-\(rect.maxY) w=\(rect.width) h=\(rect.height)")
            self.view.sendSubviewToBack(testView)
        }
        
        self.view.addSubview(labelBg1)
        self.view.addSubview(labelFps)
        self.view.addSubview(labelFps)
        self.view.addSubview(labelRps)
        self.view.addSubview(labelCpu)
        self.view.addSubview(titleCpu)
        self.view.addSubview(titleFps)
        self.view.addSubview(titleRps)
 
        let env = Environment()
        btnAudio.setSwitch(env.audioMode==1)
        
        isOption = true
        optionButton(hidden:true)
    }
    
    /// Image quality options
    @IBAction func optionTouchUpInside(_ sender: UIButton) {
        isOption = !isOption
        optionButton(hidden:isOption)
    }
    func optionButton(hidden:Bool) {
        btnAudio.hideLeft(b:hidden)
        btnRotLock.hideLeft(b:hidden)
        segBps.hideLeft(b:hidden)
        segFps.hideLeft(b:hidden)
        segZoom.hideLeft(b:hidden)
    }
    
    /// CPU（0-100%）
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

/// Button 
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

/// Segment
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
