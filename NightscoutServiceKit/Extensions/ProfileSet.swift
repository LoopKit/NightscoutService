//
//  ProfileSet.swift
//  NightscoutServiceKit
//
//  Created by Pete Schwamb on 2/21/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import NightscoutKit

extension LoopUnit {
    static func glucoseUnitFromNightscoutUnitString(_ unitString: String) -> LoopUnit? {
        // Some versions of Loop incorrectly uploaded units with
        // special characters to avoid line breaking.
        if unitString == LoopUnit.millimolesPerLiter.shortLocalizedUnitString() ||
            unitString == LoopUnit.millimolesPerLiter.shortLocalizedUnitString(avoidLineBreaking: false) ||
            unitString == "mmol/L" || unitString == "mmol"
        {
            return .millimolesPerLiter
        }

        if unitString == LoopUnit.milligramsPerDeciliter.shortLocalizedUnitString() ||
            unitString == LoopUnit.milligramsPerDeciliter.shortLocalizedUnitString(avoidLineBreaking: false) ||
            unitString == "mg/dL" || unitString == "mg/dl"
        {
            return .milligramsPerDeciliter
        }

        return nil
    }
}

/// Therapy settings read from a Nightscout profile set.
public struct ImportedTherapySettings {
    /// A store profile that was left out, and why.
    public struct SkippedProfile: Equatable {
        public let name: String
        public let reason: String

        public init(name: String, reason: String) {
            self.name = name
            self.reason = reason
        }
    }

    public let therapySettings: TherapySettings
    /// When the profile set was saved.
    public let date: Date
    /// Store profiles not in `therapySettings.therapyProfiles`.
    public let skippedProfiles: [SkippedProfile]
    /// Scheduled switches not in `therapySettings.scheduledSwitches`, named by their description.
    public let skippedScheduledSwitches: [SkippedProfile]

    public init(therapySettings: TherapySettings, date: Date, skippedProfiles: [SkippedProfile], skippedScheduledSwitches: [SkippedProfile] = []) {
        self.therapySettings = therapySettings
        self.date = date
        self.skippedProfiles = skippedProfiles
        self.skippedScheduledSwitches = skippedScheduledSwitches
    }
}

extension ProfileSet {
    /// Some uploaders, such as Trio, store the Default profile under this key.
    static let lowercaseDefaultProfileKey = "default"

    /// The live schedules are the active profile's (`defaultProfile`, as Default when its name is invalid), and every
    /// store profile that passes the checks that need no pump is a therapy profile.
    var importedTherapySettings: ImportedTherapySettings? {
        guard let settingsGlucoseUnit = LoopUnit.glucoseUnitFromNightscoutUnitString(units) else {
            return nil
        }

        var namedStore: [String: Profile] = [:]
        for (key, profile) in store {
            namedStore[profileName(forStoreKey: key)] = profile
        }
        let requestedActiveName = profileName(forStoreKey: defaultProfile)
        let liveName = namedStore[requestedActiveName] != nil ? requestedActiveName : TherapyProfile.defaultName
        guard let profile = namedStore[liveName] else {
            return nil
        }

        var activeName = liveName
        var skippedProfiles: [ImportedTherapySettings.SkippedProfile] = []
        if liveName != requestedActiveName, !requestedActiveName.isEmpty {
            skippedProfiles.append(.init(name: requestedActiveName, reason: LocalizedString("The active profile is not in the profile document, so the Default profile's values are imported as the therapy settings", comment: "Nightscout profile import: the document names an active profile it does not contain")))
        }
        do {
            try TherapyProfileValidator.validateName(liveName, isDefault: liveName == TherapyProfile.defaultName, existingNames: [])
        } catch {
            activeName = TherapyProfile.defaultName
            let reason = namedStore[activeName] != nil
                ? LocalizedString("%1$@; its values are imported as the Default profile and replace the stored Default profile", comment: "Nightscout profile import: the active profile's name is invalid and a Default profile is stored (1: why the name is invalid)")
                : LocalizedString("%1$@; its values are imported as the Default profile", comment: "Nightscout profile import: the active profile's name is invalid (1: why the name is invalid)")
            skippedProfiles.append(.init(name: liveName, reason: String(format: reason, error.localizedDescription)))
        }

        // If units are specified on the schedule, prefer those over the units specified on the ProfileSet
        let scheduleGlucoseUnit: LoopUnit
        if let profileUnitString = profile.units, let profileUnit = LoopUnit.glucoseUnitFromNightscoutUnitString(profileUnitString)
        {
            scheduleGlucoseUnit = profileUnit
        } else {
            scheduleGlucoseUnit = settingsGlucoseUnit
        }

        guard profile.targetLow.map(\.offset) == profile.targetHigh.map(\.offset) else {
            return nil
        }
        let targetItems: [RepeatingScheduleValue<DoubleRange>] = zip(profile.targetLow, profile.targetHigh).map { (low,high) in
            return RepeatingScheduleValue(startTime: low.offset, value: DoubleRange(minValue: low.value, maxValue: high.value))
        }

        let targetRangeSchedule = GlucoseRangeSchedule(unit: scheduleGlucoseUnit, dailyItems: targetItems, timeZone: profile.timeZone)

        let correctionRangeOverrides: CorrectionRangeOverrides?
        if let range = settings?.preMealTargetRange {
            correctionRangeOverrides = CorrectionRangeOverrides(
                preMeal: GlucoseRange(minValue: range.lowerBound, maxValue: range.upperBound, unit: settingsGlucoseUnit)
            )
        } else {
            correctionRangeOverrides = nil
        }

        let basalSchedule = BasalRateSchedule(
            dailyItems: profile.basal.map { RepeatingScheduleValue(startTime: $0.offset, value: $0.value) },
            timeZone: profile.timeZone)

        let sensitivitySchedule = InsulinSensitivitySchedule(
            unit: scheduleGlucoseUnit,
            dailyItems: profile.sensitivity.map { RepeatingScheduleValue(startTime: $0.offset, value: $0.value) },
            timeZone: profile.timeZone)

        let carbSchedule = CarbRatioSchedule(
            unit: .gram,
            dailyItems: profile.carbratio.map { RepeatingScheduleValue(startTime: $0.offset, value: $0.value) },
            timeZone: profile.timeZone)

        let suspendThreshold = settings?.minimumBGGuard.map { GlucoseThreshold(unit: settingsGlucoseUnit, value: $0) }

        // The active profile becomes the live settings, so it passes the same checks as every other profile or
        // nothing is imported. A schedule that can not be built fails them.
        guard let activeProfile = TherapyProfile(name: activeName,
                                                 glucoseTargetRangeSchedule: targetRangeSchedule,
                                                 carbRatioSchedule: carbSchedule,
                                                 basalRateSchedule: basalSchedule,
                                                 insulinSensitivitySchedule: sensitivitySchedule),
              (try? TherapyProfileValidator.validateValues(of: activeProfile, suspendThreshold: suspendThreshold)) != nil
        else {
            return nil
        }
        var profiles = [activeProfile]
        let names = namedStore.keys.sorted { lhs, rhs in
            if (lhs == TherapyProfile.defaultName) != (rhs == TherapyProfile.defaultName) {
                return lhs == TherapyProfile.defaultName
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        for name in names where name != activeName && name != liveName {
            guard let entry = namedStore[name] else { continue }
            // Default is always kept, so it counts against the limit even when it is not stored.
            let reserved = profiles.contains(where: \.isDefault) || name == TherapyProfile.defaultName ? 0 : 1
            guard profiles.count + reserved < TherapyProfileValidator.maximumProfileCount else {
                skippedProfiles.append(.init(name: name, reason: String(format: LocalizedString("Loop keeps at most %1$d profiles", comment: "Nightscout profile import: profile left out because of the profile limit (1: maximum number of profiles)"), TherapyProfileValidator.maximumProfileCount)))
                continue
            }
            do {
                try TherapyProfileValidator.validateName(name, isDefault: name == TherapyProfile.defaultName, existingNames: profiles.map(\.name))
                let storedProfile = try TherapyProfile(name: name, nightscoutProfile: entry, defaultUnit: settingsGlucoseUnit)
                try TherapyProfileValidator.validateValues(of: storedProfile, suspendThreshold: suspendThreshold)
                profiles.append(storedProfile)
            } catch {
                skippedProfiles.append(.init(name: name, reason: error.localizedDescription))
            }
        }
        let therapyProfiles = TherapyProfiles.resolved(profiles, live: activeProfile)
        let (scheduledSwitches, skippedScheduledSwitches) = importedScheduledSwitches(profileNames: therapyProfiles.map(\.name))

        let therapySettings = TherapySettings(
            glucoseTargetRangeSchedule: targetRangeSchedule,
            correctionRangeOverrides: correctionRangeOverrides,
            overridePresets: settings?.overridePresets.compactMap { $0.loopOverride(for: settingsGlucoseUnit) },
            maximumBasalRatePerHour: settings?.maximumBasalRatePerHour,
            maximumBolus: settings?.maximumBolus,
            suspendThreshold: suspendThreshold,
            insulinSensitivitySchedule: sensitivitySchedule,
            carbRatioSchedule: carbSchedule,
            basalRateSchedule: basalSchedule,
            defaultRapidActingModel: nil, // Not stored in NS yet
            therapyProfiles: therapyProfiles.count > 1 ? therapyProfiles : nil,
            activeProfileName: activeName == TherapyProfile.defaultName ? nil : activeName,
            scheduledSwitches: scheduledSwitches)

        return ImportedTherapySettings(therapySettings: therapySettings, date: startDate, skippedProfiles: skippedProfiles, skippedScheduledSwitches: skippedScheduledSwitches)
    }

    /// The scheduled switches, all of them or none: a week with some starts left out would keep profiles active at
    /// times the document does not.
    private func importedScheduledSwitches(profileNames: [String]) -> (entries: [ScheduledProfileSwitch]?, skipped: [ImportedTherapySettings.SkippedProfile]) {
        guard let documentSwitches = scheduledSwitches, !documentSwitches.isEmpty else {
            return (nil, [])
        }
        let entries = documentSwitches.map {
            ScheduledProfileSwitch(id: $0.id, profileName: profileName(forStoreKey: $0.profile), weekday: $0.weekday, time: TimeInterval($0.time), paused: $0.paused)
        }
        let missingNames = Set(entries.map(\.profileName)).subtracting(profileNames)
        if !missingNames.isEmpty {
            return (nil, entries.map { entry in
                let reason = missingNames.contains(entry.profileName)
                    ? String(format: LocalizedString("The profile %1$@ is not imported", comment: "Nightscout profile import: a scheduled switch to a profile that is left out (1: profile name)"), entry.profileName)
                    : LocalizedString("Scheduled switches are imported only when every profile they start is imported", comment: "Nightscout profile import: a scheduled switch left out because another one is")
                return .init(name: entry.localizedDescription, reason: reason)
            })
        }
        do {
            try ScheduledProfileSwitches.validate(entries, profileNames: profileNames)
            return (entries, [])
        } catch {
            return (nil, entries.map { .init(name: $0.localizedDescription, reason: error.localizedDescription) })
        }
    }

    private func profileName(forStoreKey key: String) -> String {
        guard key == Self.lowercaseDefaultProfileKey, store[TherapyProfile.defaultName] == nil else {
            return key
        }
        return TherapyProfile.defaultName
    }
}

extension TherapyProfile {
    /// A profile from a Nightscout `store` entry, with glucose values in the entry's units or else `defaultUnit`.
    init(name: String, nightscoutProfile profile: ProfileSet.Profile, defaultUnit: LoopUnit) throws {
        let unit = profile.units.flatMap { LoopUnit.glucoseUnitFromNightscoutUnitString($0) } ?? defaultUnit
        guard profile.targetLow.map(\.offset) == profile.targetHigh.map(\.offset) else {
            throw TherapyProfileError.invalidSchedule(LocalizedString("The correction range has different start times for its lower and upper values", comment: "Nightscout profile import error: target low and high start times differ"))
        }
        try TherapyProfileValidator.validateScheduleShape(startTimes: profile.basal.map(\.offset), settingName: LocalizedString("Basal Rates", comment: "Nightscout profile import schedule name: basal rates"))
        try TherapyProfileValidator.validateScheduleShape(startTimes: profile.carbratio.map(\.offset), settingName: LocalizedString("Carb Ratios", comment: "Nightscout profile import schedule name: carb ratios"))
        try TherapyProfileValidator.validateScheduleShape(startTimes: profile.sensitivity.map(\.offset), settingName: LocalizedString("Insulin Sensitivities", comment: "Nightscout profile import schedule name: insulin sensitivities"))
        try TherapyProfileValidator.validateScheduleShape(startTimes: profile.targetLow.map(\.offset), settingName: LocalizedString("Correction Range", comment: "Nightscout profile import schedule name: correction range"))
        guard let targets = GlucoseRangeSchedule(unit: unit,
                                                 dailyItems: zip(profile.targetLow, profile.targetHigh).map { RepeatingScheduleValue(startTime: $0.offset, value: DoubleRange(minValue: $0.value, maxValue: $1.value)) },
                                                 timeZone: profile.timeZone),
              let carbRatios = CarbRatioSchedule(unit: .gram, dailyItems: profile.carbratio.map { RepeatingScheduleValue(startTime: $0.offset, value: $0.value) }, timeZone: profile.timeZone),
              let basalRates = BasalRateSchedule(dailyItems: profile.basal.map { RepeatingScheduleValue(startTime: $0.offset, value: $0.value) }, timeZone: profile.timeZone),
              let sensitivities = InsulinSensitivitySchedule(unit: unit, dailyItems: profile.sensitivity.map { RepeatingScheduleValue(startTime: $0.offset, value: $0.value) }, timeZone: profile.timeZone)
        else {
            throw TherapyProfileError.invalidSchedule(LocalizedString("A schedule could not be read", comment: "Nightscout profile import error: schedule not built"))
        }
        self.init(name: name,
                  glucoseTargetRangeSchedule: targets,
                  carbRatioSchedule: carbRatios,
                  basalRateSchedule: basalRates,
                  insulinSensitivitySchedule: sensitivities)
    }
}

extension NightscoutKit.TemporaryScheduleOverride  {

    func loopOverride(for unit: LoopUnit) -> LoopKit.TemporaryPreset? {
        guard let name = name,
            let symbol = symbol
        else {
            return nil
        }

        let target: DoubleRange?
        if let lowerBound = targetRange?.lowerBound,
           let upperBound = targetRange?.upperBound
        {
            target = DoubleRange(minValue: lowerBound, maxValue: upperBound)
        } else {
            target = nil
        }

        let temporaryOverrideSettings = TemporaryPresetSettings(
            unit: unit,
            targetRange: target,
            insulinNeedsScaleFactor: insulinNeedsScaleFactor)

        let loopDuration: LoopKit.TemporaryScheduleOverride.Duration

        if duration == 0 {
            loopDuration = .indefinite
        } else {
            loopDuration = .finite(duration)
        }

        return TemporaryPreset(
            symbol: .emoji(symbol),
            name: name,
            settings: temporaryOverrideSettings,
            duration: loopDuration)
    }
}
