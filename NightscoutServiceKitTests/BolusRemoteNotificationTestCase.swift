//
//  BolusRemoteNotificationTestCase.swift
//  NightscoutUploadKitTests
//
//  Created by Bill Gestrich on 2/25/23.
//  Copyright © 2023 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import NightscoutServiceKit

final class BolusRemoteNotificationTestCase: XCTestCase {

    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
    }

    func testParseBolusNotification_ValidPayload_Succeeds() throws {
        
        //Arrange
        let expectedRemoteAddress = "::ffff:11.2.44.155"
        let sentAtDateString = "2023-02-25T20:46:35.778Z"
        let expectedSentAtDate = dateFormatter().date(from: sentAtDateString)!
        let expirationDateString = "2023-02-25T20:51:35.778Z"
        let expectedExpirationDate = dateFormatter().date(from: expirationDateString)!
        let expectedBolusInUnits = 1.1
        let expectedOTP = "123456"
        let expectedKnownThroughId = "63fa73a5c1f2a3b4c5d6e7f8"
        
        let notification: [String: Any] = [
            "remote-address": expectedRemoteAddress,
            "sent-at": sentAtDateString,
            "expiration": expirationDateString,
            "bolus-entry": expectedBolusInUnits,
            "otp": expectedOTP,
            "known-through-id": expectedKnownThroughId
        ]
        
        //Act
        let bolusNotification = try BolusRemoteNotification(dictionary: notification)
        
        //Assert
        XCTAssertEqual(bolusNotification.remoteAddress, expectedRemoteAddress)
        XCTAssertEqual(bolusNotification.sentAt, expectedSentAtDate)
        XCTAssertEqual(bolusNotification.expiration, expectedExpirationDate)
        XCTAssertEqual(bolusNotification.amount, expectedBolusInUnits)
        XCTAssertEqual(bolusNotification.otp, expectedOTP)
        XCTAssertEqual(bolusNotification.knownThroughId, expectedKnownThroughId)
        
        guard case .bolusEntry(let action) = bolusNotification.toRemoteAction() else {
            XCTFail("Unexpected action")
            return
        }
        XCTAssertEqual(action.amountInUnits, expectedBolusInUnits)
        XCTAssertEqual(action.sentAt, expectedSentAtDate)
        XCTAssertEqual(action.knownThroughId, expectedKnownThroughId)
    }
    
    func testParseBolusNotification_WithoutKnownThroughId_Succeeds() throws {
        
        let notification: [String: Any] = [
            "remote-address": "::ffff:11.2.44.155",
            "sent-at": "2023-02-25T20:46:35.778Z",
            "bolus-entry": 1.1,
            "otp": "123456"
        ]
        
        let bolusNotification = try BolusRemoteNotification(dictionary: notification)
        
        XCTAssertNil(bolusNotification.knownThroughId)
        XCTAssertTrue(bolusNotification.sentAtRequired())
    }
    
    
    //MARK: Utils
    
    func dateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions =  [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
    
}
