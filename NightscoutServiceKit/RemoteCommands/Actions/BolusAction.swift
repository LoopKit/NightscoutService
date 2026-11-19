//
//  BolusAction.swift
//  LoopKit
//
//  Created by Bill Gestrich on 12/25/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

public struct BolusAction: Codable {
    
    public let amountInUnits: Double
    public let sentAt: Date?
    public let knownThroughId: String?
    
    public init(amountInUnits: Double, sentAt: Date? = nil, knownThroughId: String? = nil) {
        self.amountInUnits = amountInUnits
        self.sentAt = sentAt
        self.knownThroughId = knownThroughId
    }
}
