//
//  StoredSettings.swift
//  NightscoutServiceKit
//
//  Created by Darin Krauss on 10/17/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit
import NightscoutKit

extension AutomaticDosingStrategy {
    var name: String {
        switch self {
        case .automaticBolus:
            return "automaticBolus"
        case .tempBasalOnly:
            return "tempBasalOnly"
        }
    }

    init?(name: String) {
        switch name {
        case "automaticBolus":
            self = .automaticBolus
        case "tempBasalOnly":
            self = .tempBasalOnly
        default:
            return nil
        }
    }
}

extension StoredSettings {

    var loopSettings: NightscoutKit.LoopSettings? {
        guard let bloodGlucoseUnit = bloodGlucoseUnit else {
            return nil
        }

        var nightscoutPreMealTargetRange: ClosedRange<Double>?
        if let preMealTargetRange = preMealTargetRange?.doubleRange(for: bloodGlucoseUnit) {
            nightscoutPreMealTargetRange = ClosedRange(
                uncheckedBounds: (
                    lower: preMealTargetRange.minValue,
                    upper: preMealTargetRange.maxValue))
        }

        return NightscoutKit.LoopSettings(
            dosingEnabled: dosingEnabled,
            overridePresets: overridePresets.map { $0.nsScheduleOverride(for: bloodGlucoseUnit) },
            scheduleOverride: nil,
            minimumBGGuard: suspendThreshold?.quantity.doubleValue(for: bloodGlucoseUnit),
            preMealTargetRange: nightscoutPreMealTargetRange,
            maximumBasalRatePerHour: maximumBasalRatePerHour,
            maximumBolus: maximumBolus,
            deviceToken: deviceToken,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            dosingStrategy: automaticDosingStrategy.name)
    }

    var profile: ProfileSet.Profile? {
        guard let basalRateSchedule = basalRateSchedule,
            let carbRatioSchedule = carbRatioSchedule,
            let glucoseTargetRangeSchedule = glucoseTargetRangeSchedule,
            let insulinSensitivitySchedule = insulinSensitivitySchedule?.schedule(for: glucoseTargetRangeSchedule.unit)
             else
        {
            return nil
        }

        let targetLowItems = glucoseTargetRangeSchedule.items.map { item -> ProfileSet.ScheduleItem in
            return ProfileSet.ScheduleItem(offset: item.startTime, value: item.value.minValue)
        }

        let targetHighItems = glucoseTargetRangeSchedule.items.map { item -> ProfileSet.ScheduleItem in
            return ProfileSet.ScheduleItem(offset: item.startTime, value: item.value.maxValue)
        }

        return ProfileSet.Profile(
            timezone: basalRateSchedule.timeZone,
            dia: .hours(6),
            sensitivity: insulinSensitivitySchedule.items.scheduleItems,
            carbratio: carbRatioSchedule.items.scheduleItems,
            basal: basalRateSchedule.items.scheduleItems,
            targetLow: targetLowItems,
            targetHigh: targetHighItems,
            units: glucoseTargetRangeSchedule.unit.shortLocalizedUnitString(avoidLineBreaking: false))
    }

    var profileSet: ProfileSet? {
        guard let bloodGlucoseUnit = bloodGlucoseUnit, let profile = profile, let loopSettings = loopSettings else {
            return nil
        }

        // One store entry per profile. The active profile's entry is the live settings.
        let unit = glucoseTargetRangeSchedule?.unit ?? bloodGlucoseUnit
        let activeName = TherapyProfiles.activeName(activeProfileName)
        var store: [String: ProfileSet.Profile] = [:]
        for therapyProfile in resolvedTherapyProfiles {
            guard let storeProfile = therapyProfile.nightscoutProfile(unit: unit) else {
                return nil
            }
            store[therapyProfile.name] = storeProfile
        }
        store[activeName] = profile
        let editLimits = therapyProfileValidator?.editLimits(unit: unit)

        return ProfileSet(
            startDate: date,
            units: bloodGlucoseUnit.shortLocalizedUnitString(avoidLineBreaking: false),
            enteredBy: "Loop",
            defaultProfile: activeName,
            store: store,
            settings: loopSettings,
            syncIdentifier: syncIdentifier.uuidString,
            isAPNSProduction: Bundle.main.isAPNSProductionEnvironment,
            timeZone: controllerTimeZone.identifier,
            profileEditLimits: editLimits.map { ProfileEditLimits($0) },
            // Remote profile commands need remote notifications, a pump and a maximum basal rate.
            remoteCommands: deviceToken != nil && editLimits != nil ? NightscoutService.remoteProfileCommands : nil,
            scheduledSwitches: scheduledSwitches.map { ProfileSet.ScheduledSwitch(id: $0.id, profile: $0.profileName, weekday: $0.weekday, time: Int($0.time), paused: $0.paused) },
            scheduledSwitchesFingerprint: ScheduledProfileSwitches.fingerprint(scheduledSwitches))
    }

    /// The note of the Profile Switch treatment for a switch to these settings' active profile.
    var profileSwitchNotes: String? {
        switch activeProfileSwitchTrigger {
        case .scheduled?:
            return "Scheduled"
        case .remote?:
            return "Remote"
        default:
            return nil
        }
    }
}

extension ProfileEditLimits {
    init(_ limits: TherapyProfileEditLimits) {
        func valueLimits(_ value: TherapyProfileEditLimits.ValueLimits) -> ValueLimits {
            ValueLimits(min: value.bounds.lowerBound,
                        max: value.bounds.upperBound,
                        step: value.step,
                        recommendedMin: value.recommended?.lowerBound,
                        recommendedMax: value.recommended?.upperBound)
        }
        self.init(units: limits.unit.shortLocalizedUnitString(avoidLineBreaking: false),
                  maxBasal: limits.maximumBasalRatePerHour,
                  basalRates: limits.basalRates,
                  maxBasalSegments: limits.maximumBasalScheduleEntryCount,
                  carbRatio: valueLimits(limits.carbRatio),
                  sensitivity: valueLimits(limits.sensitivity),
                  target: valueLimits(limits.target),
                  maxSegments: limits.maximumScheduleEntryCount,
                  segmentSeconds: Int(limits.segmentInterval))
    }
}

fileprivate extension Array where Element == RepeatingScheduleValue<Double> {

    var scheduleItems: [ProfileSet.ScheduleItem] {
        return map { item -> ProfileSet.ScheduleItem in
            return ProfileSet.ScheduleItem(offset: item.startTime, value: item.value)
        }
    }

}

extension Bundle {

    // True for production APNS (TestFlight builds), false for sandbox (direct Xcode to device
    // builds). Uploaded to Nightscout so followers target the correct APNS endpoint.
    var isAPNSProductionEnvironment: Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            if url(forResource: "embedded", withExtension: "mobileprovision") != nil {
                return false
            }
            guard let receiptName = appStoreReceiptURL?.lastPathComponent else {
                return false
            }
            return "sandboxReceipt".caseInsensitiveCompare(receiptName) == .orderedSame
        #endif
    }

}

// String conversion methods, adapted from https://stackoverflow.com/questions/40276322/hex-binary-string-conversion-in-swift/40278391#40278391
fileprivate extension Data {
    init?(hexadecimalString: String) {
        self.init(capacity: hexadecimalString.utf16.count / 2)

        // Convert 0 ... 9, a ... f, A ...F to their decimal value,
        // return nil for all other input characters
        func decodeNibble(u: UInt16) -> UInt8? {
            switch u {
            case 0x30 ... 0x39:  // '0'-'9'
                return UInt8(u - 0x30)
            case 0x41 ... 0x46:  // 'A'-'F'
                return UInt8(u - 0x41 + 10)  // 10 since 'A' is 10, not 0
            case 0x61 ... 0x66:  // 'a'-'f'
                return UInt8(u - 0x61 + 10)  // 10 since 'a' is 10, not 0
            default:
                return nil
            }
        }

        var even = true
        var byte: UInt8 = 0
        for c in hexadecimalString.utf16 {
            guard let val = decodeNibble(u: c) else { return nil }
            if even {
                byte = val << 4
            } else {
                byte += val
                self.append(byte)
            }
            even = !even
        }
        guard even else { return nil }
    }
}
