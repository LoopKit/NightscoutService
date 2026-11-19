//
//  ScheduledSwitchesSaveAction.swift
//  NightscoutServiceKit
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public struct ScheduledSwitchesSaveAction: Codable {

    /// The whole list that replaces the phone's scheduled switches.
    public let entries: [ScheduledProfileSwitch]
    /// The fingerprint of the list the caregiver edited.
    public let baseFingerprint: String?
}
