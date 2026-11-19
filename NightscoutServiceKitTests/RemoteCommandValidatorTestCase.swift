//
//  RemoteCommandValidatorTestCase.swift
//  NightscoutServiceKitTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
@testable import NightscoutServiceKit

final class RemoteCommandValidatorTestCase: XCTestCase {

    private var testCoordinator: OTPTestCoordinator!
    private var validator: RemoteCommandValidator!
    private var now: Date!

    override func setUpWithError() throws {
        testCoordinator = OTPTestCoordinator()
        let otpManager = testCoordinator.createOTPManager()
        now = testCoordinator.currentOTP().period.startDate
        validator = RemoteCommandValidator(otpManager: otpManager, nowDateSource: { [unowned self] in self.now })
    }

    func testBolus_SentElevenMinutesAgo_Succeeds() throws {
        let notification = try bolusNotification(sentAt: now.addingTimeInterval(-11 * 60), otp: testCoordinator.oldestValidOTP().password)
        XCTAssertNoThrow(try validator.validate(remoteNotification: notification))
    }

    func testBolus_SentTwelveMinutesAgo_Succeeds() throws {
        let notification = try bolusNotification(sentAt: now.addingTimeInterval(-12 * 60), otp: testCoordinator.oldestValidOTP().password)
        XCTAssertNoThrow(try validator.validate(remoteNotification: notification))
    }

    func testBolus_SentThirteenMinutesAgo_Throws() throws {
        let notification = try bolusNotification(sentAt: now.addingTimeInterval(-13 * 60), otp: testCoordinator.currentOTP().password)
        assertValidationError(notification) { error in
            guard case .sentAtOutOfRange = error else { return false }
            return true
        }
    }

    func testBolus_SentTwoMinutesInFuture_Succeeds() throws {
        let notification = try bolusNotification(sentAt: now.addingTimeInterval(2 * 60), otp: testCoordinator.currentOTP().password)
        XCTAssertNoThrow(try validator.validate(remoteNotification: notification))
    }

    func testBolus_SentMoreThanTwoMinutesInFuture_Throws() throws {
        let notification = try bolusNotification(sentAt: now.addingTimeInterval(2 * 60 + 1), otp: testCoordinator.currentOTP().password)
        assertValidationError(notification) { error in
            guard case .sentAtOutOfRange = error else { return false }
            return true
        }
    }

    func testBolus_MissingSentAt_Throws() throws {
        let notification = try bolusNotification(sentAt: nil, otp: testCoordinator.currentOTP().password)
        assertValidationError(notification) { error in
            guard case .missingSentAt = error else { return false }
            return true
        }
    }

    func testCarbs_MissingSentAt_Throws() throws {
        let notification = try CarbRemoteNotification(dictionary: [
            "remote-address": "::ffff:11.2.44.155",
            "carbs-entry": 10.0,
            "otp": testCoordinator.currentOTP().password
        ])
        assertValidationError(notification) { error in
            guard case .missingSentAt = error else { return false }
            return true
        }
    }

    func testBolus_PastExpirationWithinSentAtWindow_Throws() throws {
        let notification = try bolusNotification(sentAt: now.addingTimeInterval(-6 * 60), expiration: now.addingTimeInterval(-60), otp: testCoordinator.currentOTP().password)
        assertValidationError(notification) { error in
            guard case .expiredNotification = error else { return false }
            return true
        }
    }

    func testBolus_WithinExpirationAndSentAtWindow_Succeeds() throws {
        let notification = try bolusNotification(sentAt: now.addingTimeInterval(-11 * 60), expiration: now.addingTimeInterval(60), otp: testCoordinator.oldestValidOTP().password)
        XCTAssertNoThrow(try validator.validate(remoteNotification: notification))
    }

    func testBolus_ExpirationLaterThanSentAtWindow_Throws() throws {
        let notification = try bolusNotification(sentAt: now.addingTimeInterval(-13 * 60), expiration: now.addingTimeInterval(10 * 60), otp: testCoordinator.currentOTP().password)
        assertValidationError(notification) { error in
            guard case .sentAtOutOfRange = error else { return false }
            return true
        }
    }

    func testCarbs_PastExpirationWithinSentAtWindow_Throws() throws {
        let notification = try CarbRemoteNotification(dictionary: [
            "remote-address": "::ffff:11.2.44.155",
            "carbs-entry": 10.0,
            "sent-at": dateString(now.addingTimeInterval(-60)),
            "expiration": dateString(now.addingTimeInterval(-1)),
            "otp": testCoordinator.currentOTP().password
        ])
        assertValidationError(notification) { error in
            guard case .expiredNotification = error else { return false }
            return true
        }
    }

    func testOverride_WithoutSentAtPastExpiration_Throws() throws {
        let notification = try OverrideRemoteNotification(dictionary: [
            "remote-address": "::ffff:11.2.44.155",
            "override-name": "Exercise",
            "expiration": dateString(now.addingTimeInterval(-60)),
            "otp": testCoordinator.currentOTP().password
        ])
        assertValidationError(notification) { error in
            guard case .expiredNotification = error else { return false }
            return true
        }
    }

    func testOverride_OldSentAtWithinExpiration_Succeeds() throws {
        let notification = try OverrideRemoteNotification(dictionary: [
            "remote-address": "::ffff:11.2.44.155",
            "override-name": "Exercise",
            "sent-at": dateString(now.addingTimeInterval(-20 * 60)),
            "expiration": dateString(now.addingTimeInterval(60)),
            "otp": testCoordinator.currentOTP().password
        ])
        XCTAssertNoThrow(try validator.validate(remoteNotification: notification))
    }

    func testOverride_RecentSentAtPastExpiration_Throws() throws {
        let notification = try OverrideRemoteNotification(dictionary: [
            "remote-address": "::ffff:11.2.44.155",
            "override-name": "Exercise",
            "sent-at": dateString(now.addingTimeInterval(-60)),
            "expiration": dateString(now.addingTimeInterval(-1)),
            "otp": testCoordinator.currentOTP().password
        ])
        assertValidationError(notification) { error in
            guard case .expiredNotification = error else { return false }
            return true
        }
    }

    func testSentAtOutOfRange_DescriptionNamesWindow() {
        let description = RemoteCommandValidator.NotificationValidationError.sentAtOutOfRange(now).localizedDescription
        XCTAssertTrue(description.contains("12 minutes before to 2 minutes after"), description)
        XCTAssertTrue(description.contains("The clock on the sending device, or on the Nightscout server for commands sent through Nightscout, may be wrong."), description)
    }

    func testValidationFailureMessages() {
        XCTAssertEqual(NightscoutService.validationFailureMessage(for: OTPManager.OTPValidationError.incorrectOTP(otp: "123456")), "Command failed: The password was not accepted.")
        XCTAssertEqual(NightscoutService.validationFailureMessage(for: RemoteCommandValidator.NotificationValidationError.missingOTP), "Command failed: The password was not accepted.")
        XCTAssertEqual(NightscoutService.validationFailureMessage(for: RemoteCommandValidator.NotificationValidationError.missingSentAt), "Command failed: Missing send time")
        XCTAssertEqual(NightscoutService.validationFailureMessage(for: OTPManager.OTPValidationError.expired(deliveryDate: nil, maxOTPsToAccept: 25)), "Command failed: The password was not accepted.")
    }

    func testValidationFailureMessage_PasswordAlreadyUsed_NoReply() {
        XCTAssertNil(NightscoutService.validationFailureMessage(for: OTPManager.OTPValidationError.previouslyUsed(otp: "123456")))
    }

    func testFailureMessage_RejectionWithoutPrefix() {
        struct Rejection: RemoteCommandRejection {
            var errorDescription: String? { "Kommando avvisat" }
            var replyText: String { "Command rejected: a carb entry of 20 g was recorded that you had not seen." }
        }
        struct OtherError: LocalizedError {
            var errorDescription: String? { "Pump error" }
        }
        XCTAssertEqual(NightscoutService.failureMessage(for: Rejection()), "Command rejected: a carb entry of 20 g was recorded that you had not seen.")
        XCTAssertEqual(NightscoutService.failureMessage(for: OtherError()), "Command failed: Pump error")
    }

    func testCommandSource_ValidationErrorReportedToDelegate() async throws {
        final class Delegate: RemoteCommandSourceV1Delegate {
            var validationErrors: [Error] = []
            var handledActions = 0
            func commandSourceV1(_: RemoteCommandSourceV1, handleAction action: Action, remoteNotification: RemoteNotification) async throws {
                handledActions += 1
            }
            func commandSourceV1(_: RemoteCommandSourceV1, uploadError error: Error, notification: [String: AnyObject]) async throws {}
            func commandSourceV1(_: RemoteCommandSourceV1, validationError error: Error, remoteNotification: RemoteNotification) async {
                validationErrors.append(error)
            }
        }
        let source = RemoteCommandSourceV1(otpManager: testCoordinator.createOTPManager())
        let delegate = Delegate()
        source.delegate = delegate

        let notification: [String: AnyObject] = [
            "remote-address": "::ffff:11.2.44.155" as NSString,
            "bolus-entry": 1.0 as NSNumber,
            "sent-at": dateString(Date().addingTimeInterval(-20 * 60)) as NSString,
            "otp": testCoordinator.currentOTP().password as NSString
        ]
        await source.remoteNotificationWasReceived(notification)

        XCTAssertEqual(delegate.handledActions, 0)
        XCTAssertEqual(delegate.validationErrors.count, 1)
        guard case .sentAtOutOfRange = delegate.validationErrors.first as? RemoteCommandValidator.NotificationValidationError else {
            return XCTFail("Unexpected error \(String(describing: delegate.validationErrors.first))")
        }
    }

    func testOverride_WithoutSentAt_Succeeds() throws {
        let notification = try OverrideRemoteNotification(dictionary: [
            "remote-address": "::ffff:11.2.44.155",
            "override-name": "Exercise",
            "otp": testCoordinator.currentOTP().password
        ])
        XCTAssertNoThrow(try validator.validate(remoteNotification: notification))
    }

    //MARK: Utils

    private func bolusNotification(sentAt: Date?, expiration: Date? = nil, otp: String) throws -> BolusRemoteNotification {
        var dictionary: [String: Any] = [
            "remote-address": "::ffff:11.2.44.155",
            "bolus-entry": 1.0,
            "otp": otp
        ]
        if let sentAt {
            dictionary["sent-at"] = dateString(sentAt)
        }
        if let expiration {
            dictionary["expiration"] = dateString(expiration)
        }
        return try BolusRemoteNotification(dictionary: dictionary)
    }

    private func assertValidationError(_ notification: RemoteNotification, file: StaticString = #filePath, line: UInt = #line, matches: (RemoteCommandValidator.NotificationValidationError) -> Bool) {
        XCTAssertThrowsError(try validator.validate(remoteNotification: notification), file: file, line: line) { error in
            guard let validationError = error as? RemoteCommandValidator.NotificationValidationError, matches(validationError) else {
                XCTFail("Unexpected error \(error)", file: file, line: line)
                return
            }
        }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
