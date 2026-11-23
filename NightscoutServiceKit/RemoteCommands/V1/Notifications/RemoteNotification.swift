//
//  RemoteNotification.swift
//  NightscoutUploadKit
//
//  Created by Bill Gestrich on 2/25/23.
//  Copyright © 2023 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKit
import OSLog

protocol RemoteNotification: Codable {
    
    var id: String {get}
    var expiration: Date? {get}
    var sentAt: Date? {get}
    var otp: String? {get}
    var remoteAddress: String {get}
    var enteredBy: String? {get}
    var encryptedReturnNotification: String? {get}
    
    func toRemoteAction() -> Action
    func otpValidationRequired() -> Bool
    func getReturnNotificationInfo() -> ReturnNotificationInfo?
    
    static func includedInNotification(_ notification: [String: Any]) -> Bool
}

extension RemoteNotification {
    
    var id: String {
        //There is no unique identifier so we use the sent date when available
        if let sentAt = sentAt {
            return "\(sentAt.timeIntervalSince1970)"
        } else {
            return UUID().uuidString
        }
    }
    
    func getReturnNotificationInfo() -> ReturnNotificationInfo? {
        if encryptedReturnNotification == nil {
            os_log("No encrypted return notification found in remote notification", log: .default, type: .info)
            return nil
        }
        
        guard let encryptedData = encryptedReturnNotification else {
            os_log("encryptedReturnNotification is nil", log: .default, type: .error)
            return nil
        }
        
        guard let otpCode = otp else {
            os_log("OTP code is nil, cannot decrypt return notification info", log: .default, type: .error)
            return nil
        }
        
        guard let messenger = OTPSecureMessenger(otpCode: otpCode) else {
            os_log("Failed to create OTPSecureMessenger with OTP code", log: .default, type: .error)
            return nil
        }
        
        do {
            let returnInfo = try messenger.decrypt(base64EncodedString: encryptedData)
            os_log("Successfully decrypted return notification info for device token: %{public}@", log: .default, type: .info, returnInfo.deviceToken)
            return returnInfo
        } catch {
            os_log("Failed to decrypt return notification info: %{public}@", log: .default, type: .error, error.localizedDescription)
            return nil
        }
    }
    
    init(dictionary: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601DateDecoder)
        self = try jsonDecoder.decode(Self.self, from: data)
    }
}

extension DateFormatter {
    static var iso8601DateDecoder: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ" //Ex: 2022-12-24T21:34:02.090Z
        return formatter
    }()
}

extension Dictionary<String, AnyObject> {
    
    enum RemoteNotificationError: LocalizedError {
        case unhandledNotification([String: AnyObject])
        
        var errorDescription: String? {
            switch self {
            case .unhandledNotification(let notification):
                return String(format: NSLocalizedString("Unhandled Notification: %1$@", comment: "The prefix for the remote unhandled notification error. (1: notification payload)"), notification)
            }
        }
    }
    
    func toRemoteNotification() throws -> RemoteNotification {
        if BolusRemoteNotification.includedInNotification(self) {
            return try BolusRemoteNotification(dictionary: self)
        } else if CarbRemoteNotification.includedInNotification(self) {
            return try CarbRemoteNotification(dictionary: self)
        }  else if OverrideRemoteNotification.includedInNotification(self) {
            return try OverrideRemoteNotification(dictionary: self)
        } else if OverrideCancelRemoteNotification.includedInNotification(self) {
            return try OverrideCancelRemoteNotification(dictionary: self)
        } else if ProfileSwitchRemoteNotification.includedInNotification(self) {
            return try ProfileSwitchRemoteNotification(dictionary: self)
        } else if ProfileSaveRemoteNotification.includedInNotification(self) {
            return try ProfileSaveRemoteNotification(dictionary: self)
        } else if ProfileDeleteRemoteNotification.includedInNotification(self) {
            return try ProfileDeleteRemoteNotification(dictionary: self)
        } else if ScheduledSwitchesSaveRemoteNotification.includedInNotification(self) {
            return try ScheduledSwitchesSaveRemoteNotification(dictionary: self)
        } else {
            throw RemoteNotificationError.unhandledNotification(self)
        }
    }
}
