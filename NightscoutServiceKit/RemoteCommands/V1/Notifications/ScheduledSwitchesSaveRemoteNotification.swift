//
//  ScheduledSwitchesSaveRemoteNotification.swift
//  NightscoutServiceKit
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Replaces the scheduled profile switches. `expiration` is required: decoding fails without it.
public struct ScheduledSwitchesSaveRemoteNotification: RemoteNotification, Codable {
    static let commandKey = "profile-scheduled-switches-save"

    public let entries: [ScheduledProfileSwitch]
    public let baseFingerprint: String?
    public let remoteAddress: String
    private let expirationDate: Date
    public let sentAt: Date?
    public let otp: String?
    public let enteredBy: String?
    public let encryptedReturnNotification: String?

    public var expiration: Date? { expirationDate }

    enum CodingKeys: String, CodingKey {
        case entries = "profile-scheduled-switches-save"
        case baseFingerprint = "profile-scheduled-switches-base-fingerprint"
        case remoteAddress = "remote-address"
        case expirationDate = "expiration"
        case sentAt = "sent-at"
        case otp = "otp"
        case enteredBy = "entered-by"
        case encryptedReturnNotification = "encrypted_return_notification"
    }

    func toRemoteAction() -> Action {
        .scheduledSwitchesSave(ScheduledSwitchesSaveAction(entries: entries, baseFingerprint: baseFingerprint))
    }

    func otpValidationRequired() -> Bool {
        true
    }

    public static func includedInNotification(_ notification: [String: Any]) -> Bool {
        notification[commandKey] != nil
    }
}
