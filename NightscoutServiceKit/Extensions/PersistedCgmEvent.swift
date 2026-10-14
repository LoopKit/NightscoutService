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
            let note = "SensorID: \(deviceIdentifier)"
            return NightscoutTreatment(timestamp: date, enteredBy: source, notes: note, eventType: .sensorStart)
        case .sensorIssue:
            // Same wording as Trio's CGM notes, so notes from either app read alike.
            guard let state = error?.code ?? error?.message else {
                return nil
            }
            return NightscoutTreatment(timestamp: date, enteredBy: source, notes: "CGM: " + state, eventType: .note)
            // NS does not have a transmitter start type event yet
//        case .transmitterStart:
//            let note = "TransmitterID: \(deviceIdentifier)"
//            return NightscoutTreatment(timestamp: date, enteredBy: source, notes: note, eventType: .transmitterStart)
        default:
            return nil
        }
    }
}
