//
//  ProfileDeleteAction.swift
//  NightscoutServiceKit
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

public struct ProfileDeleteAction: Codable {

    public let name: String
    /// The fingerprint of the profile the caregiver reviewed.
    public let fingerprint: String
}
