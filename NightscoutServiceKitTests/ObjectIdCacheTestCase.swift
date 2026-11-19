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

    func testKnownTreatments_ComparesFullObjectId() throws {
        var cache = ObjectIdCache()
        let second = String(format: "%08x", Int(now.timeIntervalSince1970) - 60)
        cache.add(syncIdentifier: "lower", objectId: second + "0000000000000001")
        cache.add(syncIdentifier: "equal", objectId: second + "00000000000000ff")
        cache.add(syncIdentifier: "higher", objectId: second + "0000000000000100")

        let known = try XCTUnwrap(cache.knownTreatments(throughObjectId: (second + "00000000000000FF").uppercased(), now: now))

        XCTAssertEqual(known.syncIdentifiers, ["lower", "equal"])
        XCTAssertEqual(known.uploadedSyncIdentifiers, ["lower", "equal", "higher"])
    }

    func testKnownTreatments_IncludesOnlyValidIdsNoLaterThanMarker() throws {
        var cache = ObjectIdCache()
        cache.add(syncIdentifier: "before", objectId: objectId(secondsFromNow: -120))
        cache.add(syncIdentifier: "same-id", objectId: objectId(secondsFromNow: -60))
        cache.add(syncIdentifier: "after", objectId: objectId(secondsFromNow: -59))
        cache.add(syncIdentifier: "no-id", objectId: "NA")

        let known = try XCTUnwrap(cache.knownTreatments(throughObjectId: objectId(secondsFromNow: -60), now: now))

        XCTAssertEqual(known.syncIdentifiers, ["before", "same-id"])
        XCTAssertEqual(known.uploadedSyncIdentifiers, ["before", "same-id", "after"])
        XCTAssertEqual(known.recordedSince, cache.recordingStartDate)
        XCTAssertEqual(known.markerDate, Date(timeIntervalSince1970: TimeInterval(Int(now.timeIntervalSince1970) - 60)))
    }

    func testKnownTreatments_InvalidMarker_IsNil() {
        var cache = ObjectIdCache()
        cache.add(syncIdentifier: "before", objectId: objectId(secondsFromNow: -120))

        XCTAssertNil(cache.knownTreatments(throughObjectId: "not-an-object-id", now: now))
        XCTAssertNil(cache.knownTreatments(throughObjectId: "NA", now: now))
    }

    func testKnownTreatments_MarkerFarInFuture_IsNil() {
        var cache = ObjectIdCache()
        cache.add(syncIdentifier: "before", objectId: objectId(secondsFromNow: -120))

        XCTAssertNotNil(cache.knownTreatments(throughObjectId: objectId(secondsFromNow: 5 * 60), now: now))
        XCTAssertNil(cache.knownTreatments(throughObjectId: objectId(secondsFromNow: 5 * 60 + 1), now: now))
    }

    func testKnownTreatments_NoMappingRecorded_Empty() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let known = try XCTUnwrap(ObjectIdCache(recordingStartDate: start).knownTreatments(throughObjectId: objectId(secondsFromNow: 0), now: now))
        XCTAssertEqual(known.syncIdentifiers, [])
        XCTAssertEqual(known.uploadedSyncIdentifiers, [])
        XCTAssertEqual(known.recordedSince, start)
    }

    func testRecordingStartDate_WithoutStoredDate_IsFirstLaunch() throws {
        let oldMapping = ObjectIDMapping(rawValue: [
            "loopSyncIdentifier": "old",
            "nightscoutObjectId": objectId(secondsFromNow: -3600),
            "createdAt": now.addingTimeInterval(-3600)
        ])
        let before = Date()
        let cache = try XCTUnwrap(ObjectIdCache(rawValue: ["mappings": [try XCTUnwrap(oldMapping).rawValue]]))

        XCTAssertGreaterThanOrEqual(cache.recordingStartDate, before)
        XCTAssertEqual(cache.findObjectIdBySyncIdentifier("old"), objectId(secondsFromNow: -3600))
    }

    func testRecordingStartDate_KeptThroughPurgeAndRawValue() throws {
        var cache = ObjectIdCache()
        cache.add(syncIdentifier: "a", objectId: objectId(secondsFromNow: 0))
        let start = cache.recordingStartDate
        cache.purge(before: Date().addingTimeInterval(60))
        cache.add(syncIdentifier: "b", objectId: objectId(secondsFromNow: 0))

        XCTAssertEqual(cache.recordingStartDate, start)
        XCTAssertEqual(ObjectIdCache(rawValue: cache.rawValue)?.recordingStartDate, start)
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

    private final class MockObjectIdLookup: ObjectIdLookup {
        var objectIds: [String: String] = [:]
        var requested: [String] = []
        var onLookup: (() -> Void)?

        func objectId(forSyncIdentifier syncIdentifier: String) async throws -> String? {
            requested.append(syncIdentifier)
            onLookup?()
            return objectIds[syncIdentifier]
        }
    }

    func testResolveMissingObjectIds_LooksUpOnlyMissingIds() async {
        let service = NightscoutService()
        let lookup = MockObjectIdLookup()
        service.objectIdLookup = lookup
        let resolved = objectId(secondsFromNow: -10)
        let existing = objectId(secondsFromNow: -20)
        lookup.objectIds = ["not-uploaded-id": resolved]
        service.objectIdCache.add(syncIdentifier: "not-uploaded-id", objectId: "NA")
        service.objectIdCache.add(syncIdentifier: "has-id", objectId: existing)

        await service.resolveMissingObjectIds(syncIdentifiers: ["not-uploaded-id", "has-id", "not-in-nightscout"], from: service.siteURL)

        XCTAssertEqual(lookup.requested, ["not-uploaded-id", "not-in-nightscout"])
        XCTAssertEqual(service.objectIdCache.findObjectIdBySyncIdentifier("not-uploaded-id"), resolved)
        XCTAssertEqual(service.objectIdCache.findObjectIdBySyncIdentifier("has-id"), existing)
        XCTAssertNil(service.objectIdCache.findObjectIdBySyncIdentifier("not-in-nightscout"))
    }

    func testResolveMissingObjectIds_Bounded() async {
        let service = NightscoutService()
        let lookup = MockObjectIdLookup()
        service.objectIdLookup = lookup

        await service.resolveMissingObjectIds(syncIdentifiers: (0..<25).map { "missing-\($0)" }, from: service.siteURL)

        XCTAssertEqual(lookup.requested.count, NightscoutService.maxObjectIdLookups)
    }

    func testSiteURLChange_ClearsCache() {
        let service = NightscoutService()
        service.siteURL = URL(string: "https://one.example.com")
        service.objectIdCache.add(syncIdentifier: "a", objectId: objectId(secondsFromNow: 0))

        service.siteURL = URL(string: "https://one.example.com")
        XCTAssertNotNil(service.objectIdCache.findObjectIdBySyncIdentifier("a"))

        let changedAt = Date()
        service.siteURL = URL(string: "https://two.example.com")
        XCTAssertNil(service.objectIdCache.findObjectIdBySyncIdentifier("a"))
        XCTAssertGreaterThanOrEqual(service.objectIdCache.recordingStartDate, changedAt)
    }

    func testCredentialChange_NewUploader() throws {
        let service = NightscoutService()
        service.siteURL = URL(string: "https://one.example.com")
        service.apiSecret = "secret-one"
        let first = try XCTUnwrap(service.uploader)
        XCTAssertTrue(service.uploader === first)

        service.siteURL = URL(string: "https://two.example.com")
        let second = try XCTUnwrap(service.uploader)
        XCTAssertEqual(second.siteURL, URL(string: "https://two.example.com"))

        service.apiSecret = "secret-two"
        XCTAssertFalse(service.uploader === second)

        service.apiSecret = nil
        XCTAssertNil(service.uploader)
    }

    func testObjectIdLookup_RequestBoundedByCreatedAt() throws {
        let lookup = NightscoutObjectIdLookup(siteURL: try XCTUnwrap(URL(string: "https://one.example.com")), apiSecret: "secret")
        let requestTime = Date(timeIntervalSince1970: 1_800_086_400)
        let request = try XCTUnwrap(lookup.request(forSyncIdentifier: "sync-id", now: requestTime))
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/api/v1/treatments.json")
        XCTAssertEqual(items["find[syncIdentifier]"], "sync-id")
        XCTAssertEqual(items["find[created_at][$gte]"], "2027-01-15T08:00:00Z")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "api-secret"))
    }

    func testRemoteCommandContext_FromMarker() throws {
        let service = NightscoutService()
        let sentAt = now.addingTimeInterval(-60)
        service.siteURL = URL(string: "https://one.example.com")
        service.objectIdCache.add(syncIdentifier: "seen", objectId: objectId(secondsFromNow: -120))
        service.objectIdCache.add(syncIdentifier: "not-seen", objectId: objectId(secondsFromNow: -30))

        // Without an API secret treatments are not uploaded, so only the send time is passed
        XCTAssertEqual(service.remoteCommandContext(sentAt: sentAt, knownThroughId: objectId(secondsFromNow: -60)), RemoteCommandContext(sentAt: sentAt))

        service.apiSecret = "secret"
        let context = try XCTUnwrap(service.remoteCommandContext(sentAt: sentAt, knownThroughId: objectId(secondsFromNow: -60)))
        XCTAssertEqual(context.sentAt, sentAt)
        XCTAssertEqual(context.knownTreatments?.syncIdentifiers, ["seen"])
        XCTAssertEqual(context.knownTreatments?.uploadedSyncIdentifiers, ["seen", "not-seen"])
        XCTAssertEqual(context.knownTreatments?.recordedSince, service.objectIdCache.recordingStartDate)

        XCTAssertEqual(service.remoteCommandContext(sentAt: sentAt, knownThroughId: nil), RemoteCommandContext(sentAt: sentAt))
        XCTAssertEqual(service.remoteCommandContext(sentAt: sentAt, knownThroughId: "NA"), RemoteCommandContext(sentAt: sentAt))
        XCTAssertNil(service.remoteCommandContext(sentAt: nil, knownThroughId: objectId(secondsFromNow: -60)))
    }

    func testAddObjectIds_FromCurrentSite_Stored() {
        let service = NightscoutService()
        let site = URL(string: "https://one.example.com")
        service.siteURL = site
        let id = objectId(secondsFromNow: 0)

        XCTAssertTrue(service.addObjectIds([(syncIdentifier: "a", objectId: id)], from: site))
        XCTAssertEqual(service.objectIdCache.findObjectIdBySyncIdentifier("a"), id)
    }

    func testAddObjectIds_FromPreviousSite_NotStored() {
        let service = NightscoutService()
        let oldSite = URL(string: "https://one.example.com")
        service.siteURL = oldSite
        service.siteURL = URL(string: "https://two.example.com")

        XCTAssertFalse(service.addObjectIds([(syncIdentifier: "a", objectId: objectId(secondsFromNow: 0))], from: oldSite))
        XCTAssertNil(service.objectIdCache.findObjectIdBySyncIdentifier("a"))
    }

    func testResolveMissingObjectIds_SiteChangedDuringLookup_NotStored() async {
        let service = NightscoutService()
        let oldSite = URL(string: "https://one.example.com")
        service.siteURL = oldSite
        let lookup = MockObjectIdLookup()
        service.objectIdLookup = lookup
        lookup.objectIds = ["a": objectId(secondsFromNow: 0), "b": objectId(secondsFromNow: 0)]
        lookup.onLookup = { service.siteURL = URL(string: "https://two.example.com") }

        await service.resolveMissingObjectIds(syncIdentifiers: ["a", "b"], from: oldSite)

        XCTAssertNil(service.objectIdCache.findObjectIdBySyncIdentifier("a"))
        XCTAssertNil(service.objectIdCache.findObjectIdBySyncIdentifier("b"))
    }

    func testResolveMissingObjectIds_UploadFromPreviousSite_NotLookedUp() async {
        let service = NightscoutService()
        let oldSite = URL(string: "https://one.example.com")
        service.siteURL = oldSite
        service.siteURL = URL(string: "https://two.example.com")
        let lookup = MockObjectIdLookup()
        service.objectIdLookup = lookup

        await service.resolveMissingObjectIds(syncIdentifiers: ["a"], from: oldSite)

        XCTAssertEqual(lookup.requested, [])
    }
}
