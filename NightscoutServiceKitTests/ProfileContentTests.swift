//
//  ProfileContentTests.swift
//  NightscoutServiceKitTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import NightscoutKit
@testable import NightscoutServiceKit

class ProfileContentTests: XCTestCase {

    private func profileSet(startDate: Date, sensitivity: Double = 50, deviceToken: String = "token") -> ProfileSet {
        let profile = ProfileSet.Profile(
            timezone: TimeZone(identifier: "America/Chicago")!,
            dia: .hours(6),
            sensitivity: [ProfileSet.ScheduleItem(offset: 0, value: sensitivity)],
            carbratio: [ProfileSet.ScheduleItem(offset: 0, value: 10)],
            basal: [ProfileSet.ScheduleItem(offset: 0, value: 1)],
            targetLow: [ProfileSet.ScheduleItem(offset: 0, value: 100)],
            targetHigh: [ProfileSet.ScheduleItem(offset: 0, value: 110)],
            units: "mg/dL")
        let settings = LoopSettings(
            dosingEnabled: true, overridePresets: [], scheduleOverride: nil, minimumBGGuard: 75,
            preMealTargetRange: nil, maximumBasalRatePerHour: 3, maximumBolus: 5,
            deviceToken: deviceToken, bundleIdentifier: "com.loopkit.Loop", dosingStrategy: "automaticBolus")
        return ProfileSet(
            startDate: startDate, units: "mg/dL", enteredBy: "Loop", defaultProfile: "Default",
            store: ["Default": profile], settings: settings, syncIdentifier: UUID().uuidString,
            isAPNSProduction: false, timeZone: "America/Chicago")
    }

    func testContentIgnoresStartDateAndSyncIdentifier() {
        let first = profileSet(startDate: Date(timeIntervalSince1970: 1_000_000))
        let second = profileSet(startDate: Date(timeIntervalSince1970: 2_000_000))
        XCTAssertNotNil(NightscoutService.profileContent(first))
        XCTAssertEqual(NightscoutService.profileContent(first), NightscoutService.profileContent(second))
    }

    func testContentChangesWithTherapySettings() {
        let date = Date()
        XCTAssertNotEqual(NightscoutService.profileContent(profileSet(startDate: date)),
                          NightscoutService.profileContent(profileSet(startDate: date, sensitivity: 45)))
    }

    func testContentChangesWithDeviceToken() {
        let date = Date()
        XCTAssertNotEqual(NightscoutService.profileContent(profileSet(startDate: date)),
                          NightscoutService.profileContent(profileSet(startDate: date, deviceToken: "new")))
    }
}
