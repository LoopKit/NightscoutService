//
//  ProfileSaveAction.swift
//  NightscoutServiceKit
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

public struct ProfileSaveAction: Codable {

    public let name: String
    /// The profile to update; nil creates a profile.
    public let originalName: String?
    /// The fingerprint of the original profile the caregiver edited.
    public let baseFingerprint: String?
    public let values: CompactProfileValues
}

/// The values of a profile in a command: pairs of `[secondsFromMidnight, value]`, target entries
/// `[seconds, low, high]`, glucose values in `units`.
public struct CompactProfileValues: Codable, Equatable {
    public let units: String
    public let basal: [[Double]]
    public let carbratio: [[Double]]
    public let sens: [[Double]]
    public let target: [[Double]]

    public init(units: String, basal: [[Double]], carbratio: [[Double]], sens: [[Double]], target: [[Double]]) {
        self.units = units
        self.basal = basal
        self.carbratio = carbratio
        self.sens = sens
        self.target = target
    }
}
