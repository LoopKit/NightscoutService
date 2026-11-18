//
//  PumpEventTreatmentTests.swift
//  NightscoutServiceKitTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import NightscoutKit
@testable import NightscoutServiceKit

class PumpEventTreatmentTests: XCTestCase {
    private func podChange(_ replacement: ComponentReplacement?) -> PersistedPumpEvent {
        PersistedPumpEvent(date: Date(timeIntervalSince1970: 1_700_000_000),
                           persistedDate: Date(timeIntervalSince1970: 1_700_000_000),
                           dose: nil,
                           isUploaded: false,
                           objectIDURL: URL(string: "x-coredata:///PumpEvent/1")!,
                           raw: Data("Pod Change".utf8),
                           title: "Pod Change (Omnipod DASH)",
                           type: .replaceComponent(componentType: .pump),
                           componentReplacement: replacement)
    }

    func testSiteChangeNotesIncludeTheReason() {
        let json = podChange(ComponentReplacement(reason: .fault, faultCode: "0x5C")).treatment(source: "loop://iPhone")?.dictionaryRepresentation
        XCTAssertEqual(json?["eventType"] as? String, "Site Change")
        XCTAssertEqual(json?["notes"] as? String, "Pod Change (Omnipod DASH), Reason: fault 0x5C")

        XCTAssertEqual(podChange(ComponentReplacement(reason: .userInitiated)).siteChangeNotes, "Pod Change (Omnipod DASH), Reason: changed early")
    }

    func testSiteChangeNotesWithoutAReason() {
        XCTAssertEqual(podChange(nil).siteChangeNotes, "Pod Change (Omnipod DASH)")
    }
}
