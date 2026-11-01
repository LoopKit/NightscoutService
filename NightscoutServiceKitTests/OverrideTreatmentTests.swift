//
//  OverrideTreatmentTests.swift
//  NightscoutServiceKitTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import NightscoutKit
@testable import NightscoutServiceKit

class OverrideTreatmentTests: XCTestCase {
    func testActivityOverrideReasonSeparatesTypeAndSuffix() {
        let activity = ActivityPreset(activityType: .biking, preset: ActivityPreset.ActivityType.biking.completeDefaultPreset)
        let override = TemporaryScheduleOverride(
            context: .activity(activity),
            settings: activity.preset.settings,
            startDate: Date(),
            duration: .finite(.minutes(30)),
            enactTrigger: .local,
            syncIdentifier: UUID()
        )

        let treatment = OverrideTreatment(override: override)

        XCTAssertEqual(treatment.dictionaryRepresentation["reason"] as? String, "Biking Activity")
    }
}
