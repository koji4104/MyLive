//
//  SettingsViewController.swift
//  MyLive
//
//  Created by User on 2017/12/22.
//  Copyright c 2017 Koji4104. All rights reserved.
//
import UIKit
import Eureka

//------------------------------------------------------------
// Environment
//------------------------------------------------------------
open class Environment {
    
    public let typeHls:Int  = 0
    public let typeUrl1:Int = 1
    public let typeUrl2:Int = 2
    public let typeUrl3:Int = 3
    public let typeUrl4:Int = 4
    
    public func getUrl() -> String {
        var r = ""
        switch publishType {
        case typeHls:  r = "http://" + getWiFiAddress() + ":8080/my/playlist.m3u8"
        case typeUrl1: r = url1
        case typeUrl2: r = url2
        case typeUrl3: r = url3
        case typeUrl4: r = url4
        default: break
        }
        return r.lowercased()
    }
    
    public func getKey() -> String {
        var r = ""
        switch publishType {
        case typeHls:  r = ""
        case typeUrl1: r = key1
        case typeUrl2: r = key2
        case typeUrl3: r = key3
        case typeUrl4: r = key4
        default: break
        }
        return r
    }
    public func isHls() -> Bool {
        return (publishType==typeHls)
    }
    public func isRtmp() -> Bool {
        return getUrl().lowercased().hasPrefix("rt")
    }
    public func isSrt() -> Bool {
        return getUrl().lowercased().hasPrefix("srt")
    }

    public var publishType: Int {
        get { return readInt("publishType", def:0) }
        set(val) { saveInt("publishType", val:val) }
    }
    
    public var url1: String {
        get { return readString("url1", def: readString("rtmp", def:"")) }
        set(val) { saveString("url1", val:val) }
    }
    public var key1: String {
        get { return readString("key1", def: readString("key", def:"")) }
        set(val) { saveString("key1", val:val) }
    }
    
    public var url2: String {
        get { return readString("url2", def: readString("rtmp2", def:"")) }
        set(val) { saveString("url2", val:val) }
    }
    public var key2: String {
        get { return readString("key2", def:"") }
        set(val) { saveString("key2", val:val) }
    }
    
    public var url3: String {
        get { return readString("url3", def: readString("rtmp3", def:"")) }
        set(val) { saveString("url3", val:val) }
    }
    public var key3: String {
        get { return readString("key3", def:"") }
        set(val) { saveString("key3", val:val) }
    }
        
    public var url4: String {
        get { return readString("url4", def: readString("rtmp4", def:"")) }
        set(val) { saveString("url4", val:val) }
    }
    public var key4: String {
        get { return readString("key4", def:"") }
        set(val) { saveString("key4", val:val) }
    }

    //-------
    // param
    //-------
    // 500, 1000, 2000 (kbps)
    public var videoBitrate: Int {
        get { return readInt("videoBitrate", def:1000) }
        set(val) { saveInt("videoBitrate", val:val) }
    }
    // 15, 30 (fps)
    public var videoFramerate: Int {
        get { return readInt("videoFramerate", def:15) }
        set(val) { saveInt("videoFramerate", val:val) }
    }
    // 720, 540 (pixel)
    public var videoHeight: Int {
        get { return readInt("videoHeight", def:540) }
        set(val) { saveInt("videoHeight", val:val) }
    }
    // 100, 200, 300, 400
    public var zoom: Int {
        get { return readInt("zoom", def:100) }
        set(val) { saveInt("zoom", val:val) }
    }
    // 3600 (sec)
    public var publishTimeout: Int {
        get { return readInt("publishTimeout", def:3600) }
        set(val) { saveInt("publishTimeout", val:val) }
    } 
    // 0=False, 1=True
    public var lowimageMode: Int {
        get { return readInt("lowimageMode", def:0) }
        set(val) { saveInt("lowimageMode", val:val) }
    } 
    // 0=False, 1=True
    public var audioMode: Int {
        get { return readInt("audioMode", def:1) }
        set(val) { saveInt("audioMode", val:val) }
    }
    // 0=Back, 1=Front
    public var cameraPosition: Int {
        get { return readInt("cameraPosition", def:0) }
        set(val) { saveInt("cameraPosition", val:val) }
    }
    
    //----------
    // function
    //----------
    func readInt(_ key:String, def:Int) -> Int {
        let s:String! = UserDefaults.standard.string(forKey: key)
        let r:Int! = (s != nil) ? Int(s) : def
        return r
    }
    func readDouble(_ key:String, def:Double) -> Double {
        let s:String! = UserDefaults.standard.string(forKey: key)
        let r:Double! = (s != nil) ? Double(s) : def
        return r
    }
    func readString(_ key:String, def:String) -> String {
        let s:String! = UserDefaults.standard.string(forKey: key)
        let r:String! = (s != nil) ? s : def
        return r
    }
    open func saveInt(_ key:String, val:Int) {
        UserDefaults.standard.set(val, forKey:key)
        let b = UserDefaults.standard.synchronize()
        print("ud.synchronize() \(b) \(val)")
    }
    open func saveDouble(_ key:String, val:Double) {
        UserDefaults.standard.set(val, forKey:key)
        let b = UserDefaults.standard.synchronize()
        print("ud.synchronize() \(b) \(val)")
    }
    open func saveString(_ key:String, val:String) {
        UserDefaults.standard.set(val, forKey:key)
        let b = UserDefaults.standard.synchronize()
        print("ud.synchronize() \(b) \(val)")
    }             
    
    // IPアドレス取得
    func getWiFiAddress() -> String {
        var address : String
        address = "";
        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "" }
        guard let firstAddr = ifaddr else { return "" }
        // For each interface ...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            // Check for IPv4 or IPv6 interface:
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                // Check interface name:
                let name = String(cString: interface.ifa_name)
                if  name == "en0" {
                    // Convert interface address to a human readable string:
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}

//------------------------------------------------------------
// Settings
//------------------------------------------------------------
class SettingsViewController: FormViewController {
    public var mainView:UIViewController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // ツールバー
        let btnDone = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.onDoneClick(_:)))
        let toolbar = UIToolbar(frame: CGRect(
            x: 0, y: 0, width: self.view.bounds.size.width, height: 55)
        )
        toolbar.items = [btnDone]
        self.view.addSubview(toolbar)
        
        let rtmpView: UIViewController = RtmpController()
        let helpView: UIViewController = HelpController()
        let heightView: UIViewController = HeightController()
        let timeoutView: UIViewController = TimeoutController()
        let env = Environment()

        var typeStr:String = "HLS"
        switch env.publishType {
        case env.typeHls:  typeStr = "HLS"
        case env.typeUrl1: typeStr = "URL1"
        case env.typeUrl2: typeStr = "URL2"
        case env.typeUrl3: typeStr = "URL3"
        case env.typeUrl4: typeStr = "URL4"
        default: break
        }
        
        var timeout = "240"
        let t = env.publishTimeout/60
        if (t<=0) { timeout="0" }
        else if (t<=30) { timeout="30" }
        else if (t<=60) { timeout="60" }
        else if (t<=120) { timeout="120" }
        else { timeout="240" }
        
        var size = "1920x1080"
        if (env.videoHeight<=540) {
            size="960x540"
        } else if (env.videoHeight<=720) {
            size="1280x720"
        }
        
        // form
        form
            +++ Section("")
            +++ Section("MODE")
            <<< SegmentedRow<String>("set_type") {
                $0.value = typeStr
                $0.options = ["HLS", "URL1", "URL2", "URL3", "URL4"]
                $0.onChange{ row in
                let v:String = row.value!
                switch v {
                case "HLS":  env.publishType = env.typeHls
                case "URL1": env.publishType = env.typeUrl1
                case "URL2": env.publishType = env.typeUrl2
                case "URL3": env.publishType = env.typeUrl3
                case "URL4": env.publishType = env.typeUrl4
                default: break
                }
                //self.form.rowBy(tag: "set_url")?.title = env.getUrl()
                self.form.rowBy(tag: "set_url")?.reload()
                }.cellSetup { cell, row in
                    //cell.setControlWidth(width:300)
                }
            }
            <<< ButtonRow("set_url") {
                $0.title = "URL"
                $0.cellStyle = .value1
                $0.presentationMode = .show(
                    controllerProvider: ControllerProvider.callback {
                        return rtmpView },
                    onDismiss: nil
                )
                $0.cellUpdate({ (cell, row) in
                    cell.detailTextLabel?.text = env.getUrl()
                })
            }
            +++ Section("")
            <<< ButtonRow("set_height") {
                $0.title = NSLocalizedString("Camera", comment:"")
                $0.cellStyle = .value1
                $0.presentationMode = .show(
                    controllerProvider: ControllerProvider.callback {
                        return heightView },
                    onDismiss: nil
                )
                $0.cellUpdate({ (cell, row) in
                    cell.detailTextLabel?.text = size
                })
            }
            <<< SwitchRow("set_lowimage") {
                $0.title = NSLocalizedString("Auto low-image", comment:"")
                $0.value = (env.lowimageMode==1) ? true : false
                }.onChange{ row in
                    env.lowimageMode = (row.value==true) ? 1 : 0
            }
            <<< ButtonRow("set_timeout") {
                $0.title = NSLocalizedString("Auto stop(min)", comment:"")
                $0.cellStyle = .value1
                $0.presentationMode = .show(
                    controllerProvider: ControllerProvider.callback {
                        return timeoutView },
                    onDismiss: nil
                )
                $0.cellUpdate({ (cell, row) in
                    cell.detailTextLabel?.text = timeout
                })
            }
            +++ Section("")
            <<< ButtonRow("set_help") {
                $0.title = NSLocalizedString("Help", comment:"")
                $0.presentationMode = .show(
                    controllerProvider: ControllerProvider.callback {
                        return helpView },
                    onDismiss: nil
                )
            }
    }
    
    // DoneButton
    @objc func onDoneClick(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }    
    override func viewWillAppear(_ animated: Bool) {
        mainView.viewWillAppear(true)
    }
}

/// Timeout
class TimeoutController : SubFormViewController
{
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let env = Environment()
        var timeout = "240"
        let t = env.publishTimeout/60
        if (t<=0) { timeout="0" }
        else if (t<=30) { timeout="30" }
        else if (t<=60) { timeout="60" }
        else if (t<=120) { timeout="120" }
        else { timeout="240" }
        
        form
            +++ Section("")
            +++ SelectableSection<ListCheckRow<String>>(
                NSLocalizedString("Auto stop(min)", comment:""),
                selectionType: .singleSelection(enableDeselection: false))
        
        let list = ["0", "30", "60", "120", "240"]
        for v in list {
            form.last! <<< ListCheckRow<String>(v){ listRow in
                listRow.title = v
                listRow.selectableValue = v
                listRow.value = (timeout==v) ? v : nil
            }
        }
    }
    
    override func valueHasBeenChanged(for row: BaseRow, oldValue: Any?, newValue: Any?) {
        let env = Environment()
        if newValue != nil {
            if row.section === form[1] {
                switch (row.section as! SelectableSection<ListCheckRow<String>>).selectedRow()?.baseValue as! String {
                case   "0": env.publishTimeout =  0
                case  "30": env.publishTimeout =  30*60
                case  "60": env.publishTimeout =  60*60
                case "120": env.publishTimeout = 120*60
                case "240": env.publishTimeout = 240*60
                default: break
                }
            }
        }
    }
}

/// height
class HeightController : SubFormViewController
{
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let env = Environment()
        var size = "1920x1080"
        if (env.videoHeight<=540) {
            size="960x540"
        } else if(env.videoHeight<=720) {
            size="1280x720"
        }
        
        form
        +++ Section("")
        +++ SelectableSection<ListCheckRow<String>>(
            NSLocalizedString("Camera", comment:""),
            selectionType: .singleSelection(enableDeselection: false))
        
        let list = ["960x540", "1280x720"]
        for v in list {
            form.last! <<< ListCheckRow<String>(v){ listRow in
                listRow.title = v
                listRow.selectableValue = v
                listRow.value = (size==v) ? v : nil
            }
        }
    }
    
    override func valueHasBeenChanged(for row: BaseRow, oldValue: Any?, newValue: Any?) {
        let env = Environment()
        if newValue != nil {
            if row.section === form[1] {
                switch (row.section as! SelectableSection<ListCheckRow<String>>).selectedRow()?.baseValue as! String {
                case "960x540": env.videoHeight = 540
                case "1280x720": env.videoHeight = 720
                case "1920x1080": env.videoHeight = 1080
                default: break
                }
            }
        }
    }
}

/// URL
class RtmpController : SubFormViewController
{
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let env = Environment()
        // form
        form
            +++ Section("")
            +++ Section("URL1")
            <<< TextRow("set_url1"){
                $0.title = "URL1"
                $0.value = env.url1
            }
            <<< PasswordRow("set_key1"){
                $0.title = "KEY1"
                $0.value = env.key1
            }
            +++ Section("URL2")
            <<< TextRow("set_url2"){
                $0.title = "URL2"
                $0.value = env.url2
            }
            <<< PasswordRow("set_key2"){
                $0.title = "KEY2"
                $0.value = env.key2
            }
            +++ Section("URL3")
            <<< TextRow("set_url3"){
                $0.title = "URL3"
                $0.value = env.url3
            }
            <<< PasswordRow("set_key3"){
                $0.title = "KEY3"
                $0.value = env.key3
            }
            +++ Section("URL4")
            <<< TextRow("set_url4"){
                $0.title = "URL4"
                $0.value = env.url4
            }
            <<< PasswordRow("set_key4"){
                $0.title = "KEY4"
                $0.value = env.key4
            }
    }
    
    // DoneButton
    @objc override func onDoneClick(_ sender: UIButton) {
        let env = Environment()
        env.url1 = self.form.rowBy(tag: "set_url1")?.baseValue as! String
        env.url2 = self.form.rowBy(tag: "set_url2")?.baseValue as! String
        env.url3 = self.form.rowBy(tag: "set_url3")?.baseValue as! String
        env.url4 = self.form.rowBy(tag: "set_url4")?.baseValue as! String
        
        env.key1 = self.form.rowBy(tag: "set_key1")?.baseValue as! String
        env.key2 = self.form.rowBy(tag: "set_key2")?.baseValue as! String
        env.key3 = self.form.rowBy(tag: "set_key3")?.baseValue as! String
        env.key4 = self.form.rowBy(tag: "set_key4")?.baseValue as! String
        
        self.dismiss(animated: true, completion: nil)
    }
}

/// ヘルプ
class HelpController : SubFormViewController
{
    override func viewDidLoad() {
        super.viewDidLoad()
        let scroll:UIScrollView = UIScrollView()
        let webView:UIWebView = UIWebView()
        webView.frame = CGRect.init(x:2, y:2, width:view.frame.width-4, height:view.frame.height)
        
        var fileName: String = "help-en"
        let local = NSLocalizedString("local", comment:"")
        if (local=="ja") {
            fileName = "help-ja"
        }
        if let htmlData = Bundle.main.path(forResource: fileName, ofType: "html") {
            webView.loadRequest(URLRequest(url: URL(fileURLWithPath: htmlData)))
        }
        scroll.frame = CGRect.init(x:8, y:60, width:view.frame.width-20, height:view.frame.height-60-16)
        scroll.contentSize = webView.frame.size
        scroll.addSubview(webView)
        self.view.addSubview(scroll)
    }   
}

/// 基本クラス
class SubFormViewController : FormViewController {
    /// ツールバー
    override func viewDidLoad() {
        super.viewDidLoad()
        let btnDone = UIBarButtonItem(barButtonSystemItem: .reply, target: self, action: #selector(self.onDoneClick(_:)))
        let toolbar = UIToolbar(frame: CGRect(
            x: 0, y: 0, width: self.view.bounds.size.width, height: 55)
        )
        toolbar.items = [btnDone]
        self.view.addSubview(toolbar)
    }
    /// 完了ボタン
    @objc open func onDoneClick(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
}
