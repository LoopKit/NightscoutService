//
//  BolusRemoteNotification.swift
//  NightscoutUploadKit
//
//  Created by Bill Gestrich on 2/25/23.
//  Copyright © 2023 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKit

public struct BolusRemoteNotification: RemoteNotification, Codable {

    public let amount: Double
    public let remoteAddress: String
    public let expiration: Date?
    public let sentAt: Date?
    public let otp: String?
    public let enteredBy: String?
    public let encryptedReturnNotification: String?
    /// Nightscout `_id` of the newest treatment the sender had seen
    public let knownThroughId: String?
    
    enum CodingKeys: String, CodingKey {
        case remoteAddress = "remote-address"
        case amount = "bolus-entry"
        case expiration = "expiration"
        case sentAt = "sent-at"
        case otp = "otp"
        case enteredBy = "entered-by"
        case encryptedReturnNotification = "encrypted_return_notification"
        case knownThroughId = "known-through-id"
    }
    
    func toRemoteAction() -> Action {
        return .bolusEntry(BolusAction(amountInUnits: amount, sentAt: sentAt, knownThroughId: knownThroughId))
    }
    
    func otpValidationRequired() -> Bool {
        return true
    }
    
    func sentAtRequired() -> Bool {
        return true
    }
    
    public static func includedInNotification(_ notification: [String: Any]) -> Bool {
        return notification["bolus-entry"] != nil
    }
}
