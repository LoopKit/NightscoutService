//
//  ProfileSaveRemoteNotification.swift
//  NightscoutServiceKit
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Creates or updates a profile. `expiration` is required: decoding fails without it.
public struct ProfileSaveRemoteNotification: RemoteNotification, Codable {
    static let commandKey = "profile-save"

    public let name: String
    public let originalName: String?
    public let baseFingerprint: String?
    public let values: CompactProfileValues
    public let remoteAddress: String
    private let expirationDate: Date
    public let sentAt: Date?
    public let otp: String?
    public let enteredBy: String?
    public let encryptedReturnNotification: String?

    public var expiration: Date? { expirationDate }

    enum CodingKeys: String, CodingKey {
        case name = "profile-save"
        case originalName = "profile-save-original-name"
        case baseFingerprint = "profile-save-base-fingerprint"
        case values = "profile-save-values"
        case remoteAddress = "remote-address"
        case expirationDate = "expiration"
        case sentAt = "sent-at"
        case otp = "otp"
        case enteredBy = "entered-by"
        case encryptedReturnNotification = "encrypted_return_notification"
    }

    func toRemoteAction() -> Action {
        .profileSave(ProfileSaveAction(name: name, originalName: originalName, baseFingerprint: baseFingerprint, values: values))
    }

    func otpValidationRequired() -> Bool {
        true
    }

    public static func includedInNotification(_ notification: [String: Any]) -> Bool {
        notification[commandKey] != nil
    }
}
