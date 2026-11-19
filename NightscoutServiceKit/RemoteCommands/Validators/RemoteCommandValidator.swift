//
//  RemoteCommandValidator.swift
//  LoopKit
//
//  Created by Bill Gestrich on 2/25/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

struct RemoteCommandValidator {
    
    /// How far `sent-at` may be before the current time
    static let maxSentAtAge = TimeInterval(12 * 60)

    /// How far `sent-at` may be after the current time, for clock differences between the devices
    static let maxSentAtAhead = TimeInterval(2 * 60)
    
    let otpManager: OTPManager
    let nowDateSource: () -> Date
    
    internal init(otpManager: OTPManager, nowDateSource: @escaping () -> Date = {Date()}) {
        self.otpManager = otpManager
        self.nowDateSource = nowDateSource
    }
    
    /// Commands that require `sent-at` are accepted until `expiration` or `maxSentAtAge` after `sent-at`, whichever is earlier
    func validate(remoteNotification: RemoteNotification) throws {
        if remoteNotification.sentAtRequired() {
            try validateSentAt(remoteNotification: remoteNotification)
        }
        try validateExpirationDate(remoteNotification: remoteNotification)
        if remoteNotification.otpValidationRequired() {
            try validateOTP(remoteNotification: remoteNotification)
        }
    }
    
    private func validateSentAt(remoteNotification: RemoteNotification) throws {
        
        guard let sentAt = remoteNotification.sentAt else {
            throw NotificationValidationError.missingSentAt
        }
        
        let age = nowDateSource().timeIntervalSince(sentAt)
        guard age <= Self.maxSentAtAge, age >= -Self.maxSentAtAhead else {
            throw NotificationValidationError.sentAtOutOfRange(sentAt)
        }
    }
    
    private func validateExpirationDate(remoteNotification: RemoteNotification) throws {
        
        guard let expirationDate = remoteNotification.expiration else {
            return //Skip validation if no date included
        }
        
        if nowDateSource() > expirationDate {
            throw NotificationValidationError.expiredNotification
        }
    }
    
    private func validateOTP(remoteNotification: RemoteNotification) throws {
        
        guard let otp = remoteNotification.otp else {
            throw NotificationValidationError.missingOTP
        }
        
        try otpManager.validatePassword(password: otp, deliveryDate: remoteNotification.sentAt)
    }
    
    enum NotificationValidationError: LocalizedError {
        case missingOTP
        case expiredNotification
        case missingSentAt
        case sentAtOutOfRange(Date)
        
        var errorDescription: String? {
            switch  self {
            case .missingOTP:
                return LocalizedString("Missing OTP", comment: "Remote command error description: Missing OTP.")
            case .expiredNotification:
                return LocalizedString("Expired", comment: "Remote command error description: expired.")
            case .missingSentAt:
                return LocalizedString("Missing send time", comment: "Remote command error description: the command has no send time.")
            case .sentAtOutOfRange(let sentAt):
                let dateFormatter = DateFormatter()
                dateFormatter.timeStyle = .short
                return String(format: LocalizedString("Command sent at %1$@ is outside the accepted window of %2$d minutes before to %3$d minutes after the time on this phone. The clock on the sending device, or on the Nightscout server for commands sent through Nightscout, may be wrong.", comment: "Remote command error description: send time too far from now. (1: send time, 2: minutes before now, 3: minutes after now)"), dateFormatter.string(from: sentAt), Int(RemoteCommandValidator.maxSentAtAge / 60), Int(RemoteCommandValidator.maxSentAtAhead / 60))
            }
        }
    }
}
