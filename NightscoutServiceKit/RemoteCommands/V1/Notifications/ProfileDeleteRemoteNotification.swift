//
//  ProfileDeleteRemoteNotification.swift
//  NightscoutServiceKit
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Deletes a profile. `expiration` is required: decoding fails without it.
public struct ProfileDeleteRemoteNotification: RemoteNotification, Codable {
    static let commandKey = "profile-delete"

    public let name: String
    public let fingerprint: String
    public let remoteAddress: String
    private let expirationDate: Date
    public let sentAt: Date?
    public let otp: String?
    public let enteredBy: String?
    public let encryptedReturnNotification: String?

    public var expiration: Date? { expirationDate }

    enum CodingKeys: String, CodingKey {
        case name = "profile-delete"
        case fingerprint = "profile-delete-fingerprint"
        case remoteAddress = "remote-address"
        case expirationDate = "expiration"
        case sentAt = "sent-at"
        case otp = "otp"
        case enteredBy = "entered-by"
        case encryptedReturnNotification = "encrypted_return_notification"
    }

    func toRemoteAction() -> Action {
        .profileDelete(ProfileDeleteAction(name: name, fingerprint: fingerprint))
    }

    func otpValidationRequired() -> Bool {
        true
    }

    public static func includedInNotification(_ notification: [String: Any]) -> Bool {
        notification[commandKey] != nil
    }
}
