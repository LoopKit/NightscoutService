//
//  DoseTreatmentTests.swift
//  NightscoutServiceKitTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import NightscoutKit
@testable import NightscoutServiceKit

class DoseTreatmentTests: XCTestCase {
    private func bolusTreatment(_ metadata: DoseMetadata?, automatic: Bool = false) -> [String: Any]? {
        let dose = DoseEntry(type: .bolus, startDate: Date(), value: 1, unit: .units, doseId: UUID(), metadata: metadata, automatic: automatic)
        return dose.treatment(enteredBy: "Loop", withObjectId: nil)?.dictionaryRepresentation
    }

    func testBolusOriginFromMetadata() {
        XCTAssertEqual(bolusTreatment(DoseMetadata(origin: .remote))?["bolusOrigin"] as? String, "remote")
        XCTAssertEqual(bolusTreatment(DoseMetadata(origin: .user, device: .watch))?["bolusOrigin"] as? String, "watch")
        XCTAssertEqual(bolusTreatment(DoseMetadata(origin: .user, device: .phone))?["bolusOrigin"] as? String, "manual")
        XCTAssertEqual(bolusTreatment(DoseMetadata(origin: .user, device: .phone))?["notes"] as? String, "Manual bolus")
    }

    func testNoBolusOriginForAutomaticOrUnknownDoses() {
        XCTAssertNil(bolusTreatment(DoseMetadata(origin: .automatic), automatic: true)?["bolusOrigin"])
        XCTAssertNil(bolusTreatment(DoseMetadata(origin: .unknown))?["bolusOrigin"])
        XCTAssertNil(bolusTreatment(nil)?["bolusOrigin"])
        XCTAssertNil(bolusTreatment(nil)?["notes"])
    }
}
