//
//  NightscoutService+ConfigurationSharing.swift
//  NightscoutServiceKit
//
//  The site and secret another controller needs to upload for this user. Nothing local to this
//  controller is exported: the object-id cache and the remote-command OTP secret stay here.
//

import Foundation
import LoopKit

extension NightscoutService: DeviceConfigurationSharing {
    public func exportConfiguration() -> SharedDeviceConfiguration {
        var state: [String: Any] = [:]
        state["siteURL"] = siteURL?.absoluteString
        state["apiSecret"] = apiSecret
        return SharedDeviceConfiguration(managerIdentifier: pluginIdentifier, asOf: Date(), state: state)
    }

    public convenience init?(adopting configuration: SharedDeviceConfiguration, localState: [String: Any]?) {
        guard configuration.managerIdentifier == "NightscoutService",
              let siteURL = (configuration.state["siteURL"] as? String).flatMap(URL.init(string:)),
              let apiSecret = configuration.state["apiSecret"] as? String, !apiSecret.isEmpty else {
            return nil
        }
        self.init()
        self.siteURL = siteURL
        self.apiSecret = apiSecret
        self.isOnboarded = true
        self.isConfiguredByAnotherController = true
    }
}
