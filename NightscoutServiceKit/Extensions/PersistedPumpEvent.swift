//
//  PersistedPumpEvent.swift
//  NightscoutServiceKit
//
//  Created by Pete Schwamb on 9/23/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

import NightscoutKit

extension PersistedPumpEvent {

    func treatment(source: String) -> NightscoutTreatment? {
        switch type {
        case .replaceComponent(let componentType):
            switch componentType {
            case .infusionSet, .pump:
                return NightscoutTreatment(timestamp: date, enteredBy: source, notes: siteChangeNotes, eventType: .siteChange)
            default:
                return nil
            }
        case .alarm:
            return NightscoutTreatment(timestamp: date, enteredBy: source, notes: title, eventType: .note)
        default:
            return nil
        }
    }

    var siteChangeNotes: String? {
        let reason: String?
        switch componentReplacement?.previous?.reason {
        case .expired:
            reason = "expired"
        case .fault(let code):
            reason = ["fault", code].compactMap { $0 }.joined(separator: " ")
        case .occlusion(let code):
            reason = ["occlusion", code].compactMap { $0 }.joined(separator: " ")
        case .userInitiated:
            reason = "changed early"
        case .unknown, nil:
            reason = nil
        }
        guard let reason else {
            return title
        }
        return [title, "Reason: \(reason)"].compactMap { $0 }.joined(separator: ", ")
    }
}
