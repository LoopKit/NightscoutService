//
//  ObjectIdCacheTestCase.swift
//  NightscoutServiceKitTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
@testable import NightscoutServiceKit

final class ObjectIdCacheTestCase: XCTestCase {

    private let now = Date()

    /// An ObjectId whose time is `offset` seconds after now
    private func objectId(secondsFromNow offset: Int) -> String {
        String(format: "%08x", Int(now.timeIntervalSince1970) + offset) + "a1b2c3d4e5f6a7b8"
    }

    func testCreationTime_ParsesFirstFourBytes() {
        XCTAssertEqual(ObjectIdCache.creationTime(ofObjectId: "6553f100a1b2c3d4e5f6a7b8"), 1_700_000_000)
    }

    func testCreationTime_InvalidObjectId_IsNil() {
        XCTAssertNil(ObjectIdCache.creationTime(ofObjectId: "NA"))
        XCTAssertNil(ObjectIdCache.creationTime(ofObjectId: "6553f100a1b2c3d4e5f6a7b"))
        XCTAssertNil(ObjectIdCache.creationTime(ofObjectId: "6553f100a1b2c3d4e5f6a7bz"))
    }

    func testAdd_InvalidIdKeepsValidId() {
        var cache = ObjectIdCache()
        let valid = objectId(secondsFromNow: 0)
        cache.add(syncIdentifier: "a", objectId: valid)
        cache.add(syncIdentifier: "a", objectId: "NA")
        cache.add(syncIdentifier: "a", objectId: "")

        XCTAssertEqual(cache.findObjectIdBySyncIdentifier("a"), valid)
    }

    func testAdd_ValidIdReplacesInvalidId() {
        var cache = ObjectIdCache()
        let valid = objectId(secondsFromNow: 0)
        cache.add(syncIdentifier: "a", objectId: "NA")
        cache.add(syncIdentifier: "a", objectId: valid)

        XCTAssertEqual(cache.findObjectIdBySyncIdentifier("a"), valid)
    }
}
