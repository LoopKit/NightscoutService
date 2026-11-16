//
//  WorkoutTreatmentTests.swift
//  NightscoutServiceKitTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
import NightscoutKit
@testable import NightscoutServiceKit

class WorkoutTreatmentTests: XCTestCase {
    private func workout(_ activityType: HKWorkoutActivityType, distance: Double? = nil, energy: Double? = nil, heartRate: Double? = nil) -> StoredWorkout {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return StoredWorkout(uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(.minutes(42)), duration: .minutes(40), activityType: activityType, totalEnergyBurned: energy, totalDistance: distance, averageHeartRate: heartRate, source: .init(bundleIdentifier: "com.apple.health", name: "Workout", operatingSystemVersion: "27.0"))
    }

    func testWorkoutBecomesExerciseTreatment() {
        let running = workout(.running, distance: 5_234, energy: 412.4, heartRate: 147.6)
        let json = running.treatment(enteredBy: "loop://iPhone").dictionaryRepresentation

        XCTAssertEqual(json["eventType"] as? String, "Exercise")
        XCTAssertEqual(json["duration"] as? Double, 40)
        XCTAssertEqual(json["timestamp"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(json["notes"] as? String, "Running, 5.23 km, 412 kcal, avg HR 148")
        XCTAssertEqual(json["_id"] as? String, running.uuid.uuidString)
        XCTAssertEqual(json["syncIdentifier"] as? String, running.uuid.uuidString)
    }

    func testNotesLeaveOutMissingValues() {
        XCTAssertEqual(workout(.yoga).notes, "Yoga")
        XCTAssertEqual(workout(.other).notes, "Workout")
    }
}
