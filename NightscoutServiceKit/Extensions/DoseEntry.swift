//
//  DoseEntry.swift
//  NightscoutServiceKit
//
//  Created by Darin Krauss on 6/20/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit
import NightscoutKit

extension DoseEntry {

    func treatment(enteredBy source: String, withObjectId objectId: String?) -> NightscoutTreatment? {
        let duration = endDate.timeIntervalSince(startDate)

        switch type {
        case .basal:
            return nil
        case .bolus:
            return BolusNightscoutTreatment(
                timestamp: startDate,
                enteredBy: source,
                bolusType: duration >= TimeInterval(minutes: 30) ? .Square : .Normal,
                amount: deliveredUnits ?? programmedUnits,
                programmed: programmedUnits,  // Persisted pump events are always completed
                unabsorbed: 0,  // The pump's reported IOB isn't relevant, nor stored
                duration: duration,
                automatic: automatic ?? false,
                notes: bolusOrigin?.note,
                /* id: objectId, */ /// Specifying _id only works when doing a put (modify); all dose uploads are currently posting so they can be either create or update
                syncIdentifier: syncIdentifier,
                insulinType: insulinType?.brandName,
                bolusOrigin: bolusOrigin?.rawValue
            )
        case .resume:
            return nil
        case .suspend:
            // Nightscout does not have a separate "Suspend" treatment. Record a suspend as a temp basal with a reason of "suspend"
            return TempBasalNightscoutTreatment(
                timestamp: startDate,
                enteredBy: source,
                temp: .Absolute,  // DoseEntry only supports .absolute types
                rate: 0,
                absolute: unitsPerHour,
                duration: endDate.timeIntervalSince(startDate),
                amount: deliveredUnits,
                automatic: automatic ?? true,
                syncIdentifier: syncIdentifier,
                insulinType: nil,
                reason: "suspend"
            )
        case .tempBasal:
            return TempBasalNightscoutTreatment(
                timestamp: startDate,
                enteredBy: source,
                temp: .Absolute,  // DoseEntry only supports .absolute types
                rate: unitsPerHour,
                absolute: unitsPerHour,
                duration: endDate.timeIntervalSince(startDate),
                amount: deliveredUnits,
                automatic: automatic ?? true,
                /* id: objectId, */ /// Specifying _id only works when doing a put (modify); all dose uploads are currently posting so they can be either create or update
                syncIdentifier: syncIdentifier,
                insulinType: insulinType?.brandName
            )
        }
    }

    /// Values shared with Trio's `bolusOrigin`; automatic boluses have none.
    enum BolusOrigin: String {
        case remote
        case watch
        case manual

        var note: String {
            switch self {
            case .remote: return "Remote bolus"
            case .watch: return "Watch bolus"
            case .manual: return "Manual bolus"
            }
        }
    }

    var bolusOrigin: BolusOrigin? {
        switch metadata?.origin {
        case .remote:
            return .remote
        case .user:
            return metadata?.device == .watch ? .watch : .manual
        default:
            return nil
        }
    }
}
