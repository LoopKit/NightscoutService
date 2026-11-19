//
//  TherapyProfile.swift
//  NightscoutServiceKit
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import NightscoutKit

extension TherapyProfile {
    /// The profile as a Nightscout `store` entry, with glucose values in `unit`.
    func nightscoutProfile(unit: LoopUnit) -> ProfileSet.Profile? {
        guard let correctionRange = glucoseTargetRangeSchedule.schedule(for: unit),
              let sensitivity = insulinSensitivitySchedule.schedule(for: unit)
        else {
            return nil
        }
        return ProfileSet.Profile(
            timezone: basalRateSchedule.timeZone,
            dia: .hours(6),
            sensitivity: sensitivity.items.map { ProfileSet.ScheduleItem(offset: $0.startTime, value: $0.value) },
            carbratio: carbRatioSchedule.items.map { ProfileSet.ScheduleItem(offset: $0.startTime, value: $0.value) },
            basal: basalRateSchedule.items.map { ProfileSet.ScheduleItem(offset: $0.startTime, value: $0.value) },
            targetLow: correctionRange.items.map { ProfileSet.ScheduleItem(offset: $0.startTime, value: $0.value.minValue) },
            targetHigh: correctionRange.items.map { ProfileSet.ScheduleItem(offset: $0.startTime, value: $0.value.maxValue) },
            units: unit.shortLocalizedUnitString(avoidLineBreaking: false))
    }

    /// A profile from the compact values of a `profile-save` command. The start times are checked in the order
    /// given, before any schedule sorts them.
    init(name: String, compactValues values: CompactProfileValues, timeZone: TimeZone) throws {
        guard let unit = LoopUnit.glucoseUnitFromNightscoutUnitString(values.units) else {
            throw RemoteProfileCommandError.malformedValues(LocalizedString("units must be mg/dL or mmol/L", comment: "Remote profile error: unknown units"))
        }

        func entries(_ raw: [[Double]], settingName: String, valueCount: Int) throws -> [(TimeInterval, [Double])] {
            let entries: [(TimeInterval, [Double])] = try raw.map { numbers in
                guard numbers.count == valueCount + 1, numbers.allSatisfy(\.isFinite) else {
                    throw RemoteProfileCommandError.malformedValues(String(format: LocalizedString("%1$@ has a malformed entry", comment: "Remote profile error: malformed entry (1: setting name)"), settingName))
                }
                return (numbers[0], Array(numbers.dropFirst()))
            }
            try TherapyProfileValidator.validateScheduleShape(startTimes: entries.map(\.0), settingName: settingName)
            return entries
        }

        let basal = try entries(values.basal, settingName: LocalizedString("Basal Rates", comment: "Remote profile schedule name: basal rates"), valueCount: 1)
        let carbRatio = try entries(values.carbratio, settingName: LocalizedString("Carb Ratios", comment: "Remote profile schedule name: carb ratios"), valueCount: 1)
        let sensitivity = try entries(values.sens, settingName: LocalizedString("Insulin Sensitivities", comment: "Remote profile schedule name: insulin sensitivities"), valueCount: 1)
        let target = try entries(values.target, settingName: LocalizedString("Correction Range", comment: "Remote profile schedule name: correction range"), valueCount: 2)

        guard let basalSchedule = BasalRateSchedule(dailyItems: basal.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1[0]) }, timeZone: timeZone),
              let carbRatioSchedule = CarbRatioSchedule(unit: .gram, dailyItems: carbRatio.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1[0]) }, timeZone: timeZone),
              let sensitivitySchedule = InsulinSensitivitySchedule(unit: unit, dailyItems: sensitivity.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1[0]) }, timeZone: timeZone),
              let targetSchedule = GlucoseRangeSchedule(unit: unit, dailyItems: target.map { RepeatingScheduleValue(startTime: $0.0, value: DoubleRange(minValue: $0.1[0], maxValue: $0.1[1])) }, timeZone: timeZone)
        else {
            throw RemoteProfileCommandError.malformedValues(LocalizedString("A schedule could not be read", comment: "Remote profile error: schedule not built"))
        }

        self.init(name: name,
                  glucoseTargetRangeSchedule: targetSchedule,
                  carbRatioSchedule: carbRatioSchedule,
                  basalRateSchedule: basalSchedule,
                  insulinSensitivitySchedule: sensitivitySchedule)
    }
}

/// Reasons a remote profile command is refused before the phone looks at its profiles.
enum RemoteProfileCommandError: LocalizedError {
    case malformedValues(String)
    case missingFingerprint
    case missingScheduledSwitchesFingerprint

    var errorDescription: String? {
        switch self {
        case .malformedValues(let reason):
            return reason
        case .missingFingerprint:
            return LocalizedString("The command has no fingerprint of the original profile", comment: "Remote profile error: missing base fingerprint")
        case .missingScheduledSwitchesFingerprint:
            return LocalizedString("The command has no fingerprint of the scheduled switches it replaces", comment: "Remote scheduled switches error: missing base fingerprint")
        }
    }
}
