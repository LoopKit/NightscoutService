//
//  ObjectIdCache.swift
//  NightscoutServiceKit
//
//  Created by Pete Schwamb on 9/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CryptoKit
import Foundation
import LoopKit

public struct ObjectIDMapping: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]
    
    var loopSyncIdentifier: String
    var nightscoutObjectId: String
    var createdAt: Date
    
    public init(loopSyncIdentifier: String, nightscoutObjectId: String) {
        self.loopSyncIdentifier = loopSyncIdentifier
        self.nightscoutObjectId = nightscoutObjectId
        self.createdAt = Date()
    }
    
    public init?(rawValue: RawValue) {
        guard let loopSyncIdentifier = rawValue["loopSyncIdentifier"] as? String,
            let nightscoutObjectId = rawValue["nightscoutObjectId"] as? String,
            let createdAt = rawValue["createdAt"] as? Date
        else {
            return nil
        }
        
        self.loopSyncIdentifier = loopSyncIdentifier
        self.nightscoutObjectId = nightscoutObjectId
        self.createdAt = createdAt
    }
        
    public var rawValue: RawValue {
        return [
            "loopSyncIdentifier": loopSyncIdentifier,
            "nightscoutObjectId": nightscoutObjectId,
            "createdAt": createdAt
        ]
    }

}

public struct ObjectIdCache: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    var storageBySyncIdentifier: [String:ObjectIDMapping]

    /// When this cache started recording objectIds: its creation, or the first launch of a version that stores this date
    private(set) var recordingStartDate: Date

    /// Markers whose time is further than this after now are not plausible
    static let maxMarkerTimeAhead = TimeInterval(5 * 60)

    public init(recordingStartDate: Date = Date()) {
        storageBySyncIdentifier = [:]
        self.recordingStartDate = recordingStartDate
    }
        
    /// A valid objectId is kept when the new one is not valid, as Nightscout answers a repeated upload without `_id`
    mutating func add(syncIdentifier: String, objectId: String) {
        if Self.creationTime(ofObjectId: objectId) == nil,
           let existing = storageBySyncIdentifier[syncIdentifier]?.nightscoutObjectId,
           Self.creationTime(ofObjectId: existing) != nil
        {
            return
        }
        let mapping = ObjectIDMapping(loopSyncIdentifier: syncIdentifier, nightscoutObjectId: objectId)
        storageBySyncIdentifier[syncIdentifier] = mapping
    }
    
    mutating func purge(before date: Date) {
        storageBySyncIdentifier = storageBySyncIdentifier.filter { $0.value.createdAt >= date }
    }
    
    func findObjectIdBySyncIdentifier(_ syncIdentifier: String) -> String? {
        return storageBySyncIdentifier[syncIdentifier]?.nightscoutObjectId
    }
    
    /// The treatments a sender had seen when the newest treatment it had fetched has the given objectId.
    /// An objectId is known when it is not greater than the marker, comparing the lowercase hex strings.
    /// Returns nil when the marker is not a valid ObjectId or its time is more than `maxMarkerTimeAhead` after now.
    func knownTreatments(throughObjectId marker: String, now: Date = Date()) -> RemoteCommandContext.KnownTreatments? {
        guard let markerTime = Self.creationTime(ofObjectId: marker),
              TimeInterval(markerTime) <= now.addingTimeInterval(Self.maxMarkerTimeAhead).timeIntervalSince1970
        else {
            return nil
        }
        let marker = marker.lowercased()
        var known = Set<String>()
        var uploaded = Set<String>()
        for mapping in storageBySyncIdentifier.values {
            guard Self.creationTime(ofObjectId: mapping.nightscoutObjectId) != nil else {
                continue
            }
            uploaded.insert(mapping.loopSyncIdentifier)
            if mapping.nightscoutObjectId.lowercased() <= marker {
                known.insert(mapping.loopSyncIdentifier)
            }
        }
        return RemoteCommandContext.KnownTreatments(
            syncIdentifiers: known,
            uploadedSyncIdentifiers: uploaded,
            recordedSince: recordingStartDate,
            markerDate: Date(timeIntervalSince1970: TimeInterval(markerTime))
        )
    }
    
    /// The creation time, in seconds since 1970, held in the first 4 bytes of a 24 hex digit ObjectId
    static func creationTime(ofObjectId objectId: String) -> UInt32? {
        guard objectId.count == 24, objectId.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            return nil
        }
        return UInt32(objectId.prefix(8), radix: 16)
    }
    
    // RawRepresentable
    public init?(rawValue: RawValue) {
        storageBySyncIdentifier = [:]
        
        guard let rawMappings = rawValue["mappings"] as? [ObjectIDMapping.RawValue] else {
            return nil
        }
        
        for rawMapping in rawMappings {
            if let mapping = ObjectIDMapping(rawValue: rawMapping) {
                storageBySyncIdentifier[mapping.loopSyncIdentifier] = mapping
            }
        }
        
        recordingStartDate = rawValue["recordingStartDate"] as? Date ?? Date()
    }
        
    public var rawValue: RawValue {
        return [
            "mappings": storageBySyncIdentifier.values.map { $0.rawValue },
            "recordingStartDate": recordingStartDate
        ]
    }
}

protocol ObjectIdLookup {
    func objectId(forSyncIdentifier syncIdentifier: String) async throws -> String?
}

/// Finds the objectId of a treatment in Nightscout by its syncIdentifier
struct NightscoutObjectIdLookup: ObjectIdLookup {
    let siteURL: URL
    let apiSecret: String

    /// Treatments are searched among those whose `created_at` is at most this long before now
    static let searchInterval = TimeInterval(24 * 60 * 60)

    func request(forSyncIdentifier syncIdentifier: String, now: Date = Date()) -> URLRequest? {
        guard var components = URLComponents(url: siteURL.appendingPathComponent("api/v1/treatments.json"), resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "find[syncIdentifier]", value: syncIdentifier),
            URLQueryItem(name: "find[created_at][$gte]", value: ISO8601DateFormatter().string(from: now.addingTimeInterval(-Self.searchInterval))),
            URLQueryItem(name: "count", value: "2")
        ]
        guard let url = components.url else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiSecret.isEmpty {
            let digest = Insecure.SHA1.hash(data: Data(apiSecret.utf8))
            request.setValue(digest.map { String(format: "%02x", $0) }.joined(), forHTTPHeaderField: "api-secret")
        }
        return request
    }

    func objectId(forSyncIdentifier syncIdentifier: String) async throws -> String? {
        guard let request = request(forSyncIdentifier: syncIdentifier) else {
            return nil
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let treatments = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }
        return treatments.lazy
            .filter { $0["syncIdentifier"] as? String == syncIdentifier }
            .compactMap { $0["_id"] as? String }
            .first { ObjectIdCache.creationTime(ofObjectId: $0) != nil }
    }
}
