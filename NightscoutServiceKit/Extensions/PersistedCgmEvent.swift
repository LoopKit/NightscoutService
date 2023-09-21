//
//  PersistedCgmEvent.swift
//  NightscoutServiceKit
//
//  Created by Pete Schwamb on 9/11/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import NightscoutKit

extension PersistedCgmEvent {
    func treatment(enteredBy source: String) -> NightscoutTreatment? {
        switch type {
        case .sensorStart:
            return NightscoutTreatment(timestamp: date, enteredBy: source, eventType: .sensorStart)
        default:
            return nil
        }
    }
}
