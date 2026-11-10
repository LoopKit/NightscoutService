//
//  UIDevice+watchOS.swift
//  NightscoutServiceKit
//
//  watchOS has no UIDevice. The uploader names itself "loop://<device name>" and reports battery
//  through UIDevice.current; on the watch those come from WKInterfaceDevice.
//

#if os(watchOS)
import WatchKit

struct UIDevice {
    static var current: WKInterfaceDevice { WKInterfaceDevice.current() }
}
#endif
