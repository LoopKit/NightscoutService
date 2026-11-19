//
//  TherapyProfileNightscoutTests.swift
//  NightscoutServiceKitTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import NightscoutKit
@testable import NightscoutServiceKit

final class TherapyProfileNightscoutTests: XCTestCase {

    private let timeZone = TimeZone(secondsFromGMT: 3600)!

    private func profile(_ name: String, basal: [(TimeInterval, Double)] = [(0, 0.85), (21600, 1.0)], target: (Double, Double) = (100, 110)) -> TherapyProfile {
        TherapyProfile(name: name,
                       glucoseTargetRangeSchedule: GlucoseRangeSchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: target.0, maxValue: target.1))], timeZone: timeZone)!,
                       carbRatioSchedule: CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 10)], timeZone: timeZone)!,
                       basalRateSchedule: BasalRateSchedule(dailyItems: basal.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1) }, timeZone: timeZone)!,
                       insulinSensitivitySchedule: InsulinSensitivitySchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 50)], timeZone: timeZone)!)
    }

    private func settings(date: Date, active: String?, profiles: [TherapyProfile]) -> StoredSettings {
        let live = profiles.first { $0.name == TherapyProfiles.activeName(active) } ?? profile("Default")
        return StoredSettings(date: date,
                              glucoseTargetRangeSchedule: live.glucoseTargetRangeSchedule,
                              maximumBasalRatePerHour: 3,
                              maximumBolus: 5,
                              suspendThreshold: GlucoseThreshold(unit: .milligramsPerDeciliter, value: 75),
                              basalRateSchedule: live.basalRateSchedule,
                              insulinSensitivitySchedule: live.insulinSensitivitySchedule,
                              carbRatioSchedule: live.carbRatioSchedule,
                              bloodGlucoseUnit: .milligramsPerDeciliter,
                              therapyProfiles: profiles,
                              activeProfileName: active)
    }

    private struct SwitchRecord: Equatable {
        let profile: String
        let date: Date

        init(profile: String, date: Date) {
            self.profile = profile
            self.date = date
        }

        init(_ treatment: ProfileSwitchNightscoutTreatment) {
            self.init(profile: treatment.profile, date: treatment.timestamp)
        }
    }

    private var profiles: [TherapyProfile] {
        [profile("Default"), profile("Sport", basal: [(0, 0.5)], target: (120, 130))]
    }

    // MARK: Profile document

    func testProfileSetFromHistoricalSnapshot() throws {
        let profileSet = try XCTUnwrap(settings(date: Date(), active: "Sport", profiles: profiles).profileSet)
        XCTAssertEqual(profileSet.defaultProfile, "Sport")
        XCTAssertEqual(Set(profileSet.store.keys), ["Default", "Sport"])
        XCTAssertEqual(profileSet.store["Sport"]?.basal.map(\.value), [0.5])
        XCTAssertEqual(profileSet.store["Sport"]?.targetLow.map(\.value), [120])
        XCTAssertEqual(profileSet.store["Default"]?.basal.map(\.value), [0.85, 1.0])

        let earlier = try XCTUnwrap(settings(date: Date(), active: nil, profiles: profiles).profileSet)
        XCTAssertEqual(earlier.defaultProfile, "Default")
        XCTAssertEqual(earlier.store["Default"]?.basal.map(\.value), [0.85, 1.0])
    }

    func testProfileSetWithoutProfilesHasDefaultOnly() throws {
        let profileSet = try XCTUnwrap(settings(date: Date(), active: nil, profiles: []).profileSet)
        XCTAssertEqual(profileSet.defaultProfile, "Default")
        XCTAssertEqual(Array(profileSet.store.keys), ["Default"])
    }

    func testProfileSetHasEditLimits() throws {
        var withPump = settings(date: Date(), active: "Sport", profiles: profiles)
        withPump.pumpSupportedBasalRates = [0, 0.05, 0.1, 3.0, 3.05]
        withPump.pumpMaximumBasalScheduleEntryCount = 24
        let profileSet = try XCTUnwrap(withPump.profileSet)
        let limits = try XCTUnwrap(profileSet.dictionaryRepresentation["profileEditLimits"] as? [String: Any])
        XCTAssertEqual(limits["units"] as? String, "mg/dL")
        XCTAssertEqual(limits["maxBasal"] as? Double, 3)
        XCTAssertEqual(limits["basalRates"] as? [Double], [0, 0.05, 0.1, 3.0])
        XCTAssertEqual(limits["maxSegments"] as? Int, 48)
        XCTAssertEqual(limits["segmentSeconds"] as? Int, 1800)
        XCTAssertEqual(limits["maxBasalSegments"] as? Int, 24)
        XCTAssertNil(limits["basalMinimum"])
        let carbRatio = try XCTUnwrap(limits["carbRatio"] as? [String: Double])
        XCTAssertEqual(carbRatio, ["min": 2, "max": 150, "step": 0.1, "recommendedMin": 4, "recommendedMax": 28])
        let sensitivity = try XCTUnwrap(limits["sensitivity"] as? [String: Double])
        XCTAssertEqual(sensitivity, ["min": 10, "max": 500, "step": 1, "recommendedMin": 16, "recommendedMax": 399])
        let target = try XCTUnwrap(limits["target"] as? [String: Double])
        XCTAssertEqual(target["min"], 87)
        XCTAssertEqual(target["max"], 180)
        XCTAssertEqual(profileSet.defaultProfile, "Sport")

        XCTAssertNil(settings(date: Date(), active: nil, profiles: []).profileSet?.profileEditLimits)
        withPump.maximumBasalRatePerHour = nil
        XCTAssertNil(withPump.profileSet?.profileEditLimits)
    }

    func testChangingAProfileThatIsNotActiveChangesTheUploadedContent() throws {
        let before = try XCTUnwrap(settings(date: Date(), active: nil, profiles: profiles).profileSet)
        let changedProfiles = [profile("Default"), profile("Sport", basal: [(0, 0.55)], target: (120, 130))]
        let after = try XCTUnwrap(settings(date: Date(), active: nil, profiles: changedProfiles).profileSet)
        let unchanged = try XCTUnwrap(settings(date: Date().addingTimeInterval(60), active: nil, profiles: profiles).profileSet)
        XCTAssertEqual(before.store["Default"]?.basal.map(\.value), after.store["Default"]?.basal.map(\.value))
        XCTAssertNotEqual(NightscoutService.profileContent(before), NightscoutService.profileContent(after))
        XCTAssertEqual(NightscoutService.profileContent(before), NightscoutService.profileContent(unchanged))
    }

    // MARK: Profile switches

    private func uploads(_ active: [String?], profiles: [TherapyProfile]? = nil, after lastUploaded: String? = nil) -> (profileSets: [ProfileSet], switches: [ProfileSwitchNightscoutTreatment], lastUploaded: String?) {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let stored = active.enumerated().map { index, name in
            settings(date: start.addingTimeInterval(TimeInterval(index) * 60), active: name, profiles: profiles ?? self.profiles)
        }
        return NightscoutService.profileUploads(for: stored, after: lastUploaded)
    }

    func testProfileSwitchesFromConsecutiveSettings() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let result = uploads([nil, nil, "Sport", "Sport", nil])
        XCTAssertEqual(result.profileSets.map(\.defaultProfile), ["Default", "Sport", "Default"])
        XCTAssertEqual(result.switches.map(SwitchRecord.init), [.init(profile: "Sport", date: start.addingTimeInterval(120)),
                                                                .init(profile: "Default", date: start.addingTimeInterval(240))])
    }

    func testProfileSwitchesAcrossUploadBatches() {
        let first = uploads([nil, "Sport"])
        XCTAssertEqual(first.switches.map(\.profile), ["Sport"])

        let second = uploads([nil, nil], after: first.lastUploaded)
        XCTAssertEqual(second.switches.map(\.profile), ["Default"])
        XCTAssertEqual(second.profileSets.count, 1)

        let unchanged = uploads(["Sport"], after: first.lastUploaded)
        XCTAssertTrue(unchanged.profileSets.isEmpty)
        XCTAssertTrue(unchanged.switches.isEmpty)
    }

    func testFirstProfileSetGivesNoSwitch() {
        let result = uploads(["Sport"])
        XCTAssertEqual(result.profileSets.count, 1)
        XCTAssertTrue(result.switches.isEmpty)
    }

    func testEditingAProfileIsNotASwitch() {
        let first = uploads([nil])
        let edited = [profile("Default"), profile("Sport", basal: [(0, 0.55)], target: (120, 130))]
        let result = uploads([nil], profiles: edited, after: first.lastUploaded)
        XCTAssertEqual(result.profileSets.count, 1)
        XCTAssertTrue(result.switches.isEmpty)
    }

    func testRenamingActiveProfileIsNotASwitch() {
        let first = uploads(["Sport"])
        let renamed = [profile("Default"), profile("Running", basal: [(0, 0.5)], target: (120, 130))]
        let result = uploads(["Running"], profiles: renamed, after: first.lastUploaded)
        XCTAssertEqual(result.profileSets.map(\.defaultProfile), ["Running"])
        XCTAssertTrue(result.switches.isEmpty)
    }

    func testProfileSwitchTreatmentFields() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let stored = [settings(date: start, active: nil, profiles: profiles),
                      settings(date: start.addingTimeInterval(60), active: "Sport", profiles: profiles)]
        let treatment = try XCTUnwrap(NightscoutService.profileUploads(for: stored, after: nil).switches.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: treatment.dictionaryRepresentation)) as? [String: Any])
        XCTAssertEqual(json["eventType"] as? String, "Profile Switch")
        XCTAssertEqual(json["profile"] as? String, "Sport")
        XCTAssertEqual(json["created_at"] as? String, "2023-11-14T22:14:20Z")
        XCTAssertEqual(json["enteredBy"] as? String, "Loop")
        XCTAssertEqual(json["duration"] as? Int, 0)
        XCTAssertEqual(json["syncIdentifier"] as? String, stored[1].syncIdentifier.uuidString)
    }

    // MARK: Commands

    private var compact: [String: Any] {
        ["units": "mg/dL",
         "basal": [[0, 0.85], [21600, 1.0]],
         "carbratio": [[0, 10.0]],
         "sens": [[0, 50.0]],
         "target": [[0, 100.0, 110.0]]]
    }

    private func values(_ overrides: [String: Any] = [:]) throws -> CompactProfileValues {
        let data = try JSONSerialization.data(withJSONObject: compact.merging(overrides) { $1 })
        return try JSONDecoder().decode(CompactProfileValues.self, from: data)
    }

    func testCompactValuesMakeProfile() throws {
        let profile = try TherapyProfile(name: "Sport", compactValues: values(), timeZone: timeZone)
        XCTAssertEqual(profile.fingerprint(unit: .milligramsPerDeciliter), "3e603478d512da04")

        let millimolar = try TherapyProfile(name: "Sport", compactValues: values(["units": "mmol/L", "sens": [[0, 2.8]], "target": [[0, 5.5, 6.1]]]), timeZone: timeZone)
        XCTAssertEqual(millimolar.glucoseTargetRangeSchedule.unit, .millimolesPerLiter)
    }

    func testMalformedCompactValuesAreRejected() throws {
        for overrides: [String: Any] in [
            ["units": "furlongs"],
            ["basal": [[1800, 0.85]]],
            ["basal": [[0, 0.85], [21600, 1.0], [3600, 0.9]]],
            ["basal": [[0, 0.85], [900, 1.0]]],
            ["basal": [] as [Any]],
            ["target": [[0, 100.0]]],
            ["carbratio": [[0, 10.0, 11.0]]],
        ] {
            XCTAssertThrowsError(try TherapyProfile(name: "Sport", compactValues: values(overrides), timeZone: timeZone), "\(overrides)")
        }
        XCTAssertThrowsError(try TherapyProfile(name: "Sport", compactValues: values(["basal": [[0, 0.85], [900, 1.0]]]), timeZone: timeZone)) { error in
            XCTAssertEqual(error.localizedDescription, "Basal Rates has a start time that is not on a half hour")
        }
        XCTAssertThrowsError(try TherapyProfile(name: "Sport", compactValues: values(["target": [[0, 100.0]]]), timeZone: timeZone)) { error in
            XCTAssertEqual(error.localizedDescription, "Correction Range has a malformed entry")
        }
    }

    private func notification(_ fields: [String: Any]) -> [String: AnyObject] {
        var notification: [String: Any] = [
            "remote-address": "LoopFollow",
            "sent-at": "2026-11-07T10:00:00.000Z",
            "expiration": "2026-11-07T10:05:00.000Z",
            "otp": "123456",
        ]
        notification.merge(fields) { $1 }
        return notification as [String: AnyObject]
    }

    func testProfileNotificationsParse() throws {
        let switchNotification = try notification(["profile-switch": "Sport", "profile-switch-fingerprint": "3e603478d512da04"]).toRemoteNotification()
        guard case .profileSwitch(let switchAction) = switchNotification.toRemoteAction() else {
            return XCTFail("Not a profile switch")
        }
        XCTAssertEqual(switchAction.name, "Sport")
        XCTAssertEqual(switchAction.fingerprint, "3e603478d512da04")
        XCTAssertTrue(switchNotification.otpValidationRequired())
        XCTAssertNotNil(switchNotification.expiration)

        let saveNotification = try notification(["profile-save": "Sport", "profile-save-original-name": "Running", "profile-save-base-fingerprint": "abc", "profile-save-values": compact]).toRemoteNotification()
        guard case .profileSave(let saveAction) = saveNotification.toRemoteAction() else {
            return XCTFail("Not a profile save")
        }
        XCTAssertEqual(saveAction.originalName, "Running")
        XCTAssertEqual(saveAction.baseFingerprint, "abc")
        XCTAssertEqual(saveAction.values, try values())

        let deleteNotification = try notification(["profile-delete": "Sport", "profile-delete-fingerprint": "abc"]).toRemoteNotification()
        guard case .profileDelete(let deleteAction) = deleteNotification.toRemoteAction() else {
            return XCTFail("Not a profile delete")
        }
        XCTAssertEqual(deleteAction.name, "Sport")
    }

    func testProfileNotificationsRequireExpirationAndFingerprint() {
        var withoutExpiration = notification(["profile-switch": "Sport", "profile-switch-fingerprint": "abc"])
        withoutExpiration["expiration"] = nil
        XCTAssertThrowsError(try withoutExpiration.toRemoteNotification())
        XCTAssertThrowsError(try notification(["profile-switch": "Sport"]).toRemoteNotification())
        XCTAssertThrowsError(try notification(["profile-delete": "Sport"]).toRemoteNotification())
        XCTAssertThrowsError(try notification(["profile-save": "Sport"]).toRemoteNotification())
    }

    func testReplyMessages() throws {
        let switchAction = Action.profileSwitch(ProfileSwitchAction(name: "Sport", fingerprint: "abc"))
        XCTAssertEqual(RemoteNotificationResponseManager.CommandType(action: switchAction).rawValue, "profile_switch")
        XCTAssertEqual(switchAction.therapyProfileSuccessMessage, "Profile 'Sport' activated")
        XCTAssertEqual(switchAction.therapyProfileFailureMessage(for: TherapyProfileError.noPump), "Profile 'Sport' not activated: No pump is configured, so the basal rates cannot be checked")
        XCTAssertEqual(switchAction.description, "Profile Switch Sport")

        let saveAction = Action.profileSave(ProfileSaveAction(name: "Running", originalName: "Sport", baseFingerprint: "abc", values: try values()))
        XCTAssertEqual(RemoteNotificationResponseManager.CommandType(action: saveAction).rawValue, "profile_save")
        XCTAssertEqual(saveAction.therapyProfileSuccessMessage, "Profile 'Running' saved")
        XCTAssertEqual(saveAction.therapyProfileFailureMessage(for: TherapyProfileError.conflict), "Profile 'Running' not saved: \(TherapyProfileError.conflict.localizedDescription)")

        let deleteAction = Action.profileDelete(ProfileDeleteAction(name: "Sport", fingerprint: "abc"))
        XCTAssertEqual(RemoteNotificationResponseManager.CommandType(action: deleteAction).rawValue, "profile_delete")
        XCTAssertEqual(deleteAction.therapyProfileSuccessMessage, "Profile 'Sport' deleted")
        XCTAssertEqual(deleteAction.therapyProfileFailureMessage(for: TherapyProfileError.cannotDeleteActive), "Profile 'Sport' not deleted: The active profile cannot be deleted")

        let cancelOverride = Action.cancelTemporaryOverride(OverrideCancelAction(remoteAddress: "x"))
        XCTAssertNil(cancelOverride.therapyProfileSuccessMessage)
        XCTAssertNil(cancelOverride.therapyProfileFailureMessage(for: TherapyProfileError.noPump))
        XCTAssertNil(cancelOverride.therapyProfileResult(failure: nil))
    }

    func testReplyResultCodes() throws {
        let switchAction = Action.profileSwitch(ProfileSwitchAction(name: "Sport", fingerprint: "abc"))
        let saveAction = Action.profileSave(ProfileSaveAction(name: "Sport", originalName: nil, baseFingerprint: nil, values: try values()))
        let deleteAction = Action.profileDelete(ProfileDeleteAction(name: "Sport", fingerprint: "abc"))
        XCTAssertEqual(switchAction.therapyProfileResult(failure: nil), "activated")
        XCTAssertEqual(saveAction.therapyProfileResult(failure: nil), "saved")
        XCTAssertEqual(deleteAction.therapyProfileResult(failure: nil), "deleted")
        XCTAssertEqual(switchAction.therapyProfileResult(failure: TherapyProfileError.conflict), "conflict")
        XCTAssertEqual(deleteAction.therapyProfileResult(failure: TherapyProfileError.notFound("Sport")), "not_found")
        XCTAssertEqual(saveAction.therapyProfileResult(failure: TherapyProfileError.duplicateName("Sport")), "rejected")
        XCTAssertEqual(switchAction.therapyProfileResult(failure: TherapyProfileError.noPump), "rejected")
        XCTAssertEqual(switchAction.therapyProfileResult(failure: RemoteProfileCommandError.missingFingerprint), "rejected")
        XCTAssertEqual(switchAction.therapyProfileResult(failure: RemoteCommandValidator.NotificationValidationError.expiredNotification), "rejected")

        let reply = RemoteNotificationResponseManager.payload(commandType: .profileSwitch, success: false, message: "Profile 'Sport' not activated: x", result: "conflict", date: Date(timeIntervalSince1970: 0))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reply)) as? [String: Any])
        XCTAssertEqual(json["result"] as? String, "conflict")
        XCTAssertEqual(json["command_type"] as? String, "profile_switch")
        XCTAssertEqual(json["command_status"] as? String, "failed")
        XCTAssertEqual(((json["aps"] as? [String: Any])?["alert"] as? [String: Any])?["body"] as? String, "Profile 'Sport' not activated: x")

        let bolusReply = RemoteNotificationResponseManager.payload(commandType: .bolus, success: true, message: "ok", result: nil)
        let bolusJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(bolusReply)) as? [String: Any])
        XCTAssertNil(bolusJSON["result"])
    }

    func testRefusedProfileCommandReplyAndNote() throws {
        let action = try notification(["profile-save": "Sport", "profile-save-values": compact]).toRemoteNotification().toRemoteAction()
        XCTAssertEqual(RemoteNotificationResponseManager.CommandType(action: action).rawValue, "profile_save")
        XCTAssertEqual(action.description, "Profile Save Sport")
        XCTAssertEqual(action.therapyProfileFailureMessage(for: RemoteCommandValidator.NotificationValidationError.expiredNotification), "Profile 'Sport' not saved: Expired")
        XCTAssertEqual(action.therapyProfileResult(failure: OTPManager.OTPValidationError.previouslyUsed(otp: "123456")), "rejected")
        XCTAssertEqual(action.therapyProfileResult(failure: OTPManager.OTPValidationError.incorrectOTP(otp: "123456")), "rejected")
    }

    func testSaveOfExistingProfileWithoutBaseFingerprintIsRejected() async throws {
        let service = NightscoutService()
        let remoteNotification = try notification(["profile-save": "Sport", "profile-save-original-name": "Sport", "profile-save-values": compact]).toRemoteNotification()
        let action = remoteNotification.toRemoteAction()
        do {
            try await service.commandSourceV1(RemoteCommandSourceV1(otpManager: service.otpManager), handleAction: action, remoteNotification: remoteNotification)
            XCTFail("Saved without a base fingerprint")
        } catch {
            guard case .missingFingerprint? = error as? RemoteProfileCommandError else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(action.therapyProfileResult(failure: error), "rejected")
        }
    }

    func testProfileSetListsProfileCommandsWithRemoteNotificationsPumpAndMaximumBasalRate() {
        XCTAssertEqual(NightscoutService.remoteProfileCommands, ["profile-switch", "profile-save", "profile-delete", "profile-scheduled-switches-save"])
        var settings = settings(date: Date(), active: nil, profiles: [])
        settings.pumpSupportedBasalRates = [0, 0.05, 0.1]
        XCTAssertNil(settings.profileSet?.remoteCommands, "No device token")
        XCTAssertNil(settings.profileSet?.dictionaryRepresentation["remoteCommands"])
        settings.deviceToken = "token"
        XCTAssertEqual(settings.profileSet?.remoteCommands, NightscoutService.remoteProfileCommands)
        XCTAssertEqual(settings.profileSet?.dictionaryRepresentation["remoteCommands"] as? [String], NightscoutService.remoteProfileCommands)
        settings.maximumBasalRatePerHour = nil
        XCTAssertNil(settings.profileSet?.remoteCommands)
        settings.maximumBasalRatePerHour = 3
        settings.pumpSupportedBasalRates = nil
        XCTAssertNil(settings.profileSet?.remoteCommands)
    }

    // MARK: Scheduled switches

    private let weekend = ScheduledProfileSwitch(id: "w", profileName: "Sport", weekday: 7, time: 25200, paused: true)
    private let school = ScheduledProfileSwitch(id: "s", profileName: "Default", weekday: 2, time: 21600)

    func testProfileSetCarriesScheduledSwitchesAndTheirFingerprint() throws {
        var stored = settings(date: Date(), active: nil, profiles: profiles)
        stored.scheduledSwitches = [weekend, school]
        let json = try XCTUnwrap(stored.profileSet?.dictionaryRepresentation)
        let entries = try XCTUnwrap(json["scheduledSwitches"] as? [[String: Any]])
        XCTAssertEqual(entries.map { $0["profile"] as? String }, ["Sport", "Default"])
        XCTAssertEqual(entries[0]["paused"] as? Bool, true)
        XCTAssertNil(entries[1]["paused"])
        XCTAssertEqual(entries[1]["weekday"] as? Int, 2)
        XCTAssertEqual(entries[1]["time"] as? Int, 21600)
        XCTAssertEqual(json["scheduledSwitchesFingerprint"] as? String, ScheduledProfileSwitches.fingerprint([weekend, school]))

        let none = try XCTUnwrap(settings(date: Date(), active: nil, profiles: profiles).profileSet?.dictionaryRepresentation)
        XCTAssertEqual((none["scheduledSwitches"] as? [Any])?.count, 0)
        XCTAssertEqual(none["scheduledSwitchesFingerprint"] as? String, "e3b0c44298fc1c14")
    }

    func testSettlingScheduledSwitchesDoesNotChangeTheUploadedContent() throws {
        var first = settings(date: Date(timeIntervalSince1970: 1_700_000_000), active: nil, profiles: profiles)
        first.scheduledSwitches = [weekend, school]
        first.scheduledSwitchesSettledAt = Date(timeIntervalSince1970: 1_700_000_000)
        var settled = first
        settled.date = first.date.addingTimeInterval(300)
        settled.syncIdentifier = UUID()
        settled.scheduledSwitchesSettledAt = settled.date
        let result = NightscoutService.profileUploads(for: [first, settled], after: nil)
        XCTAssertEqual(result.profileSets.count, 1)
        XCTAssertTrue(result.switches.isEmpty)
    }

    func testProfileSwitchNotesFollowTheTrigger() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func switchNotes(_ trigger: TherapyProfileSwitchTrigger?) throws -> String? {
            var switched = settings(date: start.addingTimeInterval(60), active: "Sport", profiles: profiles)
            switched.activeProfileSwitchTrigger = trigger
            let result = NightscoutService.profileUploads(for: [settings(date: start, active: nil, profiles: profiles), switched], after: nil)
            XCTAssertEqual(result.switches.count, 1)
            let treatment = try XCTUnwrap(result.switches.first)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: treatment.dictionaryRepresentation)) as? [String: Any])
            return json["notes"] as? String
        }
        XCTAssertEqual(try switchNotes(.scheduled), "Scheduled")
        XCTAssertEqual(try switchNotes(.remote), "Remote")
        XCTAssertNil(try switchNotes(.local))
        XCTAssertNil(try switchNotes(nil))
    }

    func testScheduledSwitchesNotificationParsesAnArray() throws {
        let entries: [[String: Any]] = [
            ["id": "w", "profile": "Sport", "weekday": 7, "time": 25200, "paused": true],
            ["id": "s", "profile": "Default", "weekday": 2, "time": 21600],
        ]
        let remoteNotification = try notification(["profile-scheduled-switches-save": entries, "profile-scheduled-switches-base-fingerprint": "e3b0c44298fc1c14"]).toRemoteNotification()
        guard case .scheduledSwitchesSave(let action) = remoteNotification.toRemoteAction() else {
            return XCTFail("Not a scheduled switches save")
        }
        XCTAssertEqual(action.entries, [weekend, school])
        XCTAssertEqual(action.baseFingerprint, "e3b0c44298fc1c14")
        XCTAssertTrue(remoteNotification.otpValidationRequired())

        let cleared = try notification(["profile-scheduled-switches-save": [Any](), "profile-scheduled-switches-base-fingerprint": "abc"]).toRemoteNotification()
        guard case .scheduledSwitchesSave(let clearAction) = cleared.toRemoteAction() else {
            return XCTFail("Not a scheduled switches save")
        }
        XCTAssertEqual(clearAction.entries, [])

        XCTAssertThrowsError(try notification(["profile-scheduled-switches-save": "[]", "profile-scheduled-switches-base-fingerprint": "abc"]).toRemoteNotification())
        var withoutExpiration = notification(["profile-scheduled-switches-save": entries, "profile-scheduled-switches-base-fingerprint": "abc"])
        withoutExpiration["expiration"] = nil
        XCTAssertThrowsError(try withoutExpiration.toRemoteNotification())
    }

    func testScheduledSwitchesReplyMessagesAndResultCodes() {
        let action = Action.scheduledSwitchesSave(ScheduledSwitchesSaveAction(entries: [school], baseFingerprint: "abc"))
        XCTAssertEqual(RemoteNotificationResponseManager.CommandType(action: action).rawValue, "profile_scheduled_switches_save")
        XCTAssertEqual(action.therapyProfileSuccessMessage, "Scheduled switches saved")
        XCTAssertEqual(action.therapyProfileFailureMessage(for: ScheduledProfileSwitchError.tooMany), "Scheduled switches not saved: \(ScheduledProfileSwitchError.tooMany.localizedDescription)")
        XCTAssertEqual(action.therapyProfileResult(failure: nil), "saved")
        XCTAssertEqual(action.therapyProfileResult(failure: ScheduledProfileSwitchError.conflict), "conflict")
        XCTAssertEqual(action.therapyProfileResult(failure: TherapyProfileError.notFound("Sport")), "not_found")
        XCTAssertEqual(action.therapyProfileResult(failure: ScheduledProfileSwitchError.slotTaken(school)), "rejected")
        XCTAssertEqual(action.therapyProfileResult(failure: RemoteCommandValidator.NotificationValidationError.expiredNotification), "rejected")
    }

    func testScheduledSwitchesSaveWithoutBaseFingerprintIsRejected() async throws {
        let service = NightscoutService()
        let remoteNotification = try notification(["profile-scheduled-switches-save": [[String: Any]]()]).toRemoteNotification()
        let action = remoteNotification.toRemoteAction()
        do {
            try await service.commandSourceV1(RemoteCommandSourceV1(otpManager: service.otpManager), handleAction: action, remoteNotification: remoteNotification)
            XCTFail("Saved without a base fingerprint")
        } catch {
            guard case .missingScheduledSwitchesFingerprint? = error as? RemoteProfileCommandError else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(action.therapyProfileResult(failure: error), "rejected")
        }
    }

    func testRestoreImportsScheduledSwitches() throws {
        var stored = settings(date: Date(), active: "Sport", profiles: profiles)
        stored.scheduledSwitches = [weekend, school]
        let imported = try XCTUnwrap(stored.profileSet?.importedTherapySettings)
        XCTAssertEqual(imported.therapySettings.scheduledSwitches, [weekend, school])
        XCTAssertEqual(imported.skippedScheduledSwitches, [])
    }

    func testRestoreLeavesOutEveryScheduledSwitchWhenAProfileIsNotImported() throws {
        let profileSet = try fixture(Self.loopProfileDocument)
        let switches: [[String: Any]] = [
            ["id": "a", "profile": "Weekend", "weekday": 7, "time": 25200],
            ["id": "b", "profile": "Too Low", "weekday": 1, "time": 25200],
        ]
        let raw = profileSet.dictionaryRepresentation.merging(["scheduledSwitches": switches, "_id": "x"]) { $1 }
        let imported = try XCTUnwrap(ProfileSet(rawValue: raw)?.importedTherapySettings)
        XCTAssertNil(imported.therapySettings.scheduledSwitches)
        XCTAssertEqual(imported.skippedScheduledSwitches.count, 2)
        XCTAssertEqual(imported.skippedScheduledSwitches[1].reason, "The profile Too Low is not imported")
        XCTAssertEqual(imported.therapySettings.therapyProfiles?.map(\.name), ["Default", "School", "Weekend"])
    }

    func testRestoreMapsTrioDefaultInScheduledSwitches() throws {
        let profileSet = try fixture(Self.trioProfileDocument)
        let switches: [[String: Any]] = [["id": "a", "profile": "default", "weekday": 2, "time": 21600]]
        let raw = profileSet.dictionaryRepresentation.merging(["scheduledSwitches": switches, "_id": "x"]) { $1 }
        let imported = try XCTUnwrap(ProfileSet(rawValue: raw)?.importedTherapySettings)
        XCTAssertEqual(imported.therapySettings.scheduledSwitches?.map(\.profileName), ["Default"])
    }

    // MARK: Restore

    func testRestoreReadsActiveProfileAndImportsOthers() throws {
        let profileSet = try XCTUnwrap(settings(date: Date(), active: "Sport", profiles: profiles).profileSet)
        let imported = try XCTUnwrap(profileSet.importedTherapySettings)
        let therapySettings = imported.therapySettings
        XCTAssertEqual(therapySettings.basalRateSchedule?.items.map(\.value), [0.5])
        XCTAssertEqual(therapySettings.activeProfileName, "Sport")
        XCTAssertEqual(therapySettings.therapyProfiles?.map(\.name), ["Default", "Sport"])
        XCTAssertEqual(therapySettings.therapyProfiles?[0].basalRateSchedule.items.map(\.value), [0.85, 1.0])
        XCTAssertEqual(imported.skippedProfiles, [])
    }

    func testRestoreWithDefaultOnlyCarriesNoProfiles() throws {
        let profileSet = try XCTUnwrap(settings(date: Date(), active: nil, profiles: []).profileSet)
        let therapySettings = try XCTUnwrap(profileSet.importedTherapySettings?.therapySettings)
        XCTAssertNil(therapySettings.therapyProfiles)
        XCTAssertNil(therapySettings.activeProfileName)
    }

    private func fixture(_ json: String) throws -> ProfileSet {
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        return try XCTUnwrap(ProfileSet(rawValue: raw))
    }

    func testRestoreKeepsAtMostTheProfileLimit() throws {
        let entry = """
        {"dia": 6, "timezone": "ETC/GMT-1", "units": "mg/dL",
         "basal": [{"time": "00:00", "timeAsSeconds": 0, "value": 1}], "carbratio": [{"time": "00:00", "timeAsSeconds": 0, "value": 10}],
         "sens": [{"time": "00:00", "timeAsSeconds": 0, "value": 45}],
         "target_low": [{"time": "00:00", "timeAsSeconds": 0, "value": 100}], "target_high": [{"time": "00:00", "timeAsSeconds": 0, "value": 110}]}
        """
        let names = (1...24).map { String(format: "P%02d", $0) }
        let store = (["Default"] + names).map { "\"\($0)\": \(entry)" }.joined(separator: ",")
        let json = """
        {"_id": "6720d2c1a1b2c3d4e5f6071a", "defaultProfile": "P24", "startDate": "2026-11-07T12:00:00.000Z",
         "units": "mg/dL", "enteredBy": "Loop", "store": {\(store)}}
        """
        let imported = try XCTUnwrap(try fixture(json).importedTherapySettings)
        let profiles = try XCTUnwrap(imported.therapySettings.therapyProfiles)
        XCTAssertEqual(profiles.count, TherapyProfileValidator.maximumProfileCount)
        XCTAssertTrue(profiles.contains { $0.name == "P24" })
        XCTAssertTrue(profiles.contains(where: \.isDefault))
        XCTAssertEqual(imported.skippedProfiles.map(\.name), ["P19", "P20", "P21", "P22", "P23"])
    }

    func testRestoreRefusesAnActiveProfileWhoseValuesAreOutOfBounds() throws {
        // Saved by the Nightscout profile editor on an mmol/L site: the mg/dL values now claim mmol/L.
        let json = """
        {"_id": "6720d2c1a1b2c3d4e5f60719", "defaultProfile": "Unwell", "startDate": "2026-11-07T12:00:00.000Z",
         "units": "mmol", "enteredBy": "Loop",
         "store": {
           "Default": {"dia": 6, "timezone": "ETC/GMT-1", "startDate": "1970-01-01T00:00:00.000Z",
             "basal": [{"time": "00:00", "timeAsSeconds": 0, "value": 1}], "carbratio": [{"time": "00:00", "timeAsSeconds": 0, "value": 10}],
             "sens": [{"time": "00:00", "timeAsSeconds": 0, "value": 45}],
             "target_low": [{"time": "00:00", "timeAsSeconds": 0, "value": 100}], "target_high": [{"time": "00:00", "timeAsSeconds": 0, "value": 110}]},
           "Unwell": {"dia": 6, "timezone": "ETC/GMT-1", "units": "mmol", "delay": 20,
             "basal": [{"time": "00:00", "timeAsSeconds": 0, "value": 1.25}], "carbratio": [{"time": "00:00", "timeAsSeconds": 0, "value": 9}],
             "sens": [{"time": "00:00", "timeAsSeconds": 0, "value": 40}],
             "target_low": [{"time": "00:00", "timeAsSeconds": 0, "value": 90}], "target_high": [{"time": "00:00", "timeAsSeconds": 0, "value": 100}]}}}
        """
        XCTAssertNil(try fixture(json).importedTherapySettings)
    }

    func testRestoreRefusesAnActiveProfileWithAnUnreadableSchedule() throws {
        // The sensitivities have string values, which are dropped, and the other schedules are out of bounds.
        let json = """
        {"_id": "6720d2c1a1b2c3d4e5f6071b", "defaultProfile": "Unread", "startDate": "2026-11-07T12:00:00.000Z",
         "units": "mmol", "enteredBy": "Loop",
         "store": {
           "Unread": {"dia": 6, "timezone": "ETC/GMT-1", "units": "mmol",
             "basal": [{"time": "00:00", "timeAsSeconds": 0, "value": 1.25}], "carbratio": [{"time": "00:00", "timeAsSeconds": 0, "value": 9}],
             "sens": [{"time": "00:00", "timeAsSeconds": 0, "value": "40"}],
             "target_low": [{"time": "00:00", "timeAsSeconds": 0, "value": 90}], "target_high": [{"time": "00:00", "timeAsSeconds": 0, "value": 100}]}}}
        """
        XCTAssertNil(try fixture(json).importedTherapySettings)
    }

    func testRestoreRefusesAnActiveProfileWhoseTargetStartTimesDiffer() throws {
        let json = """
        {"_id": "6720d2c1a1b2c3d4e5f6071c", "defaultProfile": "Default", "startDate": "2026-11-07T12:00:00.000Z",
         "units": "mg/dL", "enteredBy": "Loop",
         "store": {
           "Default": {"dia": 6, "timezone": "ETC/GMT-1", "units": "mg/dL",
             "basal": [{"time": "00:00", "timeAsSeconds": 0, "value": 1}], "carbratio": [{"time": "00:00", "timeAsSeconds": 0, "value": 10}],
             "sens": [{"time": "00:00", "timeAsSeconds": 0, "value": 45}],
             "target_low": [{"time": "00:00", "timeAsSeconds": 0, "value": 100}, {"time": "06:00", "timeAsSeconds": 21600, "value": 105}],
             "target_high": [{"time": "00:00", "timeAsSeconds": 0, "value": 110}, {"time": "07:00", "timeAsSeconds": 25200, "value": 115}]}}}
        """
        XCTAssertNil(try fixture(json).importedTherapySettings)
    }

    func testRestoreListsAnActiveProfileMissingFromTheDocument() throws {
        let document = Self.loopProfileDocument.replacingOccurrences(of: "\"defaultProfile\": \"School\"", with: "\"defaultProfile\": \"Gone\"")
        XCTAssertNotEqual(document, Self.loopProfileDocument)
        let imported = try XCTUnwrap(try fixture(document).importedTherapySettings)
        XCTAssertEqual(imported.skippedProfiles.first?.name, "Gone")
        XCTAssertNil(imported.therapySettings.activeProfileName)
    }

    func testRestoreFromLoopDocument() throws {
        let imported = try XCTUnwrap(try fixture(Self.loopProfileDocument).importedTherapySettings)
        let therapySettings = imported.therapySettings
        XCTAssertEqual(imported.skippedProfiles, [.init(name: "Too Low", reason: TherapyProfileError.correctionRangeBelowSuspendThreshold.localizedDescription)])
        XCTAssertEqual(therapySettings.activeProfileName, "School")
        XCTAssertEqual(therapySettings.therapyProfiles?.map(\.name), ["Default", "School", "Weekend"])
        XCTAssertEqual(therapySettings.suspendThreshold?.quantity.doubleValue(for: .milligramsPerDeciliter), 90)
        XCTAssertEqual(therapySettings.maximumBasalRatePerHour, 3)
        XCTAssertEqual(therapySettings.maximumBolus, 8)

        let live = try XCTUnwrap(TherapyProfile(name: "School",
                                                glucoseTargetRangeSchedule: therapySettings.glucoseTargetRangeSchedule,
                                                carbRatioSchedule: therapySettings.carbRatioSchedule,
                                                basalRateSchedule: therapySettings.basalRateSchedule,
                                                insulinSensitivitySchedule: therapySettings.insulinSensitivitySchedule))
        let school = try XCTUnwrap(therapySettings.therapyProfiles?.first { $0.name == "School" })
        XCTAssertTrue(live.hasSameValues(as: school))
        XCTAssertEqual(school.basalRateSchedule.items.map(\.value), [0.8, 1.1])
        XCTAssertEqual(school.basalRateSchedule.items.map(\.startTime), [0, 25200])
        let weekend = try XCTUnwrap(therapySettings.therapyProfiles?.first { $0.name == "Weekend" })
        XCTAssertEqual(weekend.insulinSensitivitySchedule.schedule(for: .milligramsPerDeciliter)?.items.map(\.value), [60])
        XCTAssertEqual(weekend.basalRateSchedule.timeZone, TimeZone(secondsFromGMT: 3600))
    }

    func testRestoreWithInvalidActiveNameImportsLiveValuesAsDefault() throws {
        let document = Self.loopProfileDocument.replacingOccurrences(of: "School", with: "Mon.Fri")
        let imported = try XCTUnwrap(try fixture(document).importedTherapySettings)
        let therapySettings = imported.therapySettings
        XCTAssertEqual(imported.skippedProfiles.map(\.name), ["Mon.Fri", "Too Low"])
        XCTAssertEqual(imported.skippedProfiles.first?.reason, TherapyProfileError.invalidNameCharacter(".").localizedDescription + "; its values are imported as the Default profile and replace the stored Default profile")
        XCTAssertNil(therapySettings.activeProfileName)
        XCTAssertEqual(therapySettings.therapyProfiles?.map(\.name), ["Default", "Weekend"])
        XCTAssertEqual(therapySettings.basalRateSchedule?.items.map(\.value), [0.8, 1.1])
        XCTAssertEqual(therapySettings.therapyProfiles?.first?.basalRateSchedule.items.map(\.value), [0.8, 1.1])
    }

    func testRestoreWithInvalidActiveNameAndNoStoredDefaultImportsLiveValuesAsDefault() throws {
        let profileSet = try fixture(Self.loopProfileDocument.replacingOccurrences(of: "School", with: "Mon.Fri"))
        var store = try XCTUnwrap(profileSet.dictionaryRepresentation["store"] as? [String: Any])
        store["Default"] = nil
        let raw = profileSet.dictionaryRepresentation.merging(["store": store, "_id": "x"]) { $1 }
        let imported = try XCTUnwrap(ProfileSet(rawValue: raw)?.importedTherapySettings)
        XCTAssertEqual(imported.skippedProfiles.map(\.name), ["Mon.Fri", "Too Low"])
        XCTAssertEqual(imported.skippedProfiles.first?.reason, TherapyProfileError.invalidNameCharacter(".").localizedDescription + "; its values are imported as the Default profile")
        XCTAssertNil(imported.therapySettings.activeProfileName)
        XCTAssertEqual(imported.therapySettings.therapyProfiles?.map(\.name), ["Default", "Weekend"])
        XCTAssertEqual(imported.therapySettings.therapyProfiles?.first?.basalRateSchedule.items.map(\.value), [0.8, 1.1])
    }

    func testRestoreFromTrioDocument() throws {
        let imported = try XCTUnwrap(try fixture(Self.trioProfileDocument).importedTherapySettings)
        let therapySettings = imported.therapySettings
        XCTAssertEqual(imported.skippedProfiles.map(\.name), ["Off Grid", "Wild"])
        XCTAssertEqual(imported.skippedProfiles.first?.reason, "Basal Rates has a start time that is not on a half hour")
        XCTAssertEqual(therapySettings.therapyProfiles?.map(\.name), ["Default", "Sport"])
        XCTAssertEqual(therapySettings.activeProfileName, "Sport")
        XCTAssertNil(therapySettings.suspendThreshold)
        XCTAssertNil(therapySettings.maximumBasalRatePerHour)
        XCTAssertNil(therapySettings.overridePresets)

        // Values are in mmol/L in the document.
        let mgdl = LoopUnit.milligramsPerDeciliter
        XCTAssertEqual(therapySettings.basalRateSchedule?.items.map(\.value), [0.5, 0.6])
        XCTAssertEqual(therapySettings.glucoseTargetRangeSchedule?.unit, .millimolesPerLiter)
        XCTAssertEqual(therapySettings.glucoseTargetRangeSchedule?.schedule(for: mgdl)?.items.first?.value.minValue ?? 0, 120.7, accuracy: 0.5)
        let defaultProfile = try XCTUnwrap(therapySettings.therapyProfiles?.first)
        XCTAssertEqual(defaultProfile.basalRateSchedule.items.map(\.value), [0.85, 1.0])
        XCTAssertEqual(defaultProfile.insulinSensitivitySchedule.schedule(for: mgdl)?.items.first?.value ?? 0, 50.4, accuracy: 0.5)
        XCTAssertEqual(defaultProfile.carbRatioSchedule.items.map(\.value), [10])
        XCTAssertEqual(defaultProfile.basalRateSchedule.timeZone.identifier, "Europe/Stockholm")
    }

    func testRestoreFromTrioDocumentWithDefaultActive() throws {
        let profileSet = try fixture(Self.trioProfileDocument)
        let raw = profileSet.dictionaryRepresentation.merging(["defaultProfile": "default", "_id": "x"]) { $1 }
        let imported = try XCTUnwrap(ProfileSet(rawValue: raw)?.importedTherapySettings)
        XCTAssertNil(imported.therapySettings.activeProfileName)
        XCTAssertEqual(imported.therapySettings.therapyProfiles?.map(\.name), ["Default", "Sport"])
        XCTAssertEqual(imported.therapySettings.basalRateSchedule?.items.map(\.value), [0.85, 1.0])
    }

    /// A profile document as Loop uploads it: Default, School (active) and Weekend, and a profile whose correction
    /// range is below the glucose safety limit.
    private static let loopProfileDocument = """
    {"_id": "6720d2c1a1b2c3d4e5f60718", "defaultProfile": "School", "startDate": "2026-11-07T12:00:00Z", "mills": "1793966400000",
     "units": "mg/dL", "enteredBy": "Loop", "isAPNSProduction": false, "timeZone": "Europe/Stockholm",
     "loopSettings": {"dosingEnabled": true, "overridePresets": [], "minimumBGGuard": 90, "preMealTargetRange": [80, 90],
                      "maximumBasalRatePerHour": 3, "maximumBolus": 8, "deviceToken": "token", "dosingStrategy": "automaticBolus"},
     "profileEditLimits": {"units": "mg/dL", "maxBasal": 3, "basalRates": [0.05, 0.1], "maxSegments": 48, "segmentSeconds": 1800,
                           "carbRatio": {"min": 2, "max": 150, "step": 0.1, "recommendedMin": 4, "recommendedMax": 28},
                           "sensitivity": {"min": 10, "max": 500, "step": 1}, "target": {"min": 90, "max": 180, "step": 1}},
     "store": {
       "Default": {"dia": 6, "carbs_hr": "0", "delay": "0", "timezone": "ETC/GMT-1", "units": "mg/dL",
                   "basal": [{"time": "00:00", "value": 0.85, "timeAsSeconds": 0}, {"time": "06:00", "value": 1.0, "timeAsSeconds": 21600}],
                   "carbratio": [{"time": "00:00", "value": 10, "timeAsSeconds": 0}],
                   "sens": [{"time": "00:00", "value": 50, "timeAsSeconds": 0}],
                   "target_low": [{"time": "00:00", "value": 100, "timeAsSeconds": 0}],
                   "target_high": [{"time": "00:00", "value": 110, "timeAsSeconds": 0}]},
       "School": {"dia": 6, "carbs_hr": "0", "delay": "0", "timezone": "ETC/GMT-1", "units": "mg/dL",
                  "basal": [{"time": "00:00", "value": 0.8, "timeAsSeconds": 0}, {"time": "07:00", "value": 1.1, "timeAsSeconds": 25200}],
                  "carbratio": [{"time": "00:00", "value": 9, "timeAsSeconds": 0}],
                  "sens": [{"time": "00:00", "value": 45, "timeAsSeconds": 0}],
                  "target_low": [{"time": "00:00", "value": 100, "timeAsSeconds": 0}],
                  "target_high": [{"time": "00:00", "value": 105, "timeAsSeconds": 0}]},
       "Weekend": {"dia": 6, "carbs_hr": "0", "delay": "0", "timezone": "ETC/GMT-1", "units": "mg/dL",
                   "basal": [{"time": "00:00", "value": 0.6, "timeAsSeconds": 0}],
                   "carbratio": [{"time": "00:00", "value": 12, "timeAsSeconds": 0}],
                   "sens": [{"time": "00:00", "value": 60, "timeAsSeconds": 0}],
                   "target_low": [{"time": "00:00", "value": 110, "timeAsSeconds": 0}],
                   "target_high": [{"time": "00:00", "value": 120, "timeAsSeconds": 0}]},
       "Too Low": {"dia": 6, "carbs_hr": "0", "delay": "0", "timezone": "ETC/GMT-1", "units": "mg/dL",
                   "basal": [{"time": "00:00", "value": 0.6, "timeAsSeconds": 0}],
                   "carbratio": [{"time": "00:00", "value": 12, "timeAsSeconds": 0}],
                   "sens": [{"time": "00:00", "value": 60, "timeAsSeconds": 0}],
                   "target_low": [{"time": "00:00", "value": 88, "timeAsSeconds": 0}],
                   "target_high": [{"time": "00:00", "value": 95, "timeAsSeconds": 0}]}
     }}
    """

    /// A profile document as Trio uploads it, in mmol/L: Default under `default`, Sport (active), a profile with a
    /// basal rate starting off the half-hour grid, and one with an insulin sensitivity outside the guardrails.
    private static let trioProfileDocument = """
    {"_id": "6720d2c1a1b2c3d4e5f60719", "defaultProfile": "Sport", "startDate": "2026-11-07T12:00:00.000Z", "mills": 1793966400000,
     "units": "mmol", "enteredBy": "Trio", "bundleIdentifier": "org.nightscout.TEAMID.trio", "deviceToken": "token",
     "isAPNSProduction": false, "teamID": "TEAMID", "expirationDate": "2027-02-01T00:00:00.000Z",
     "overridePresets": [{"name": "Exercise", "duration": 60, "percentage": 80, "target": 7.8}],
     "remoteCommands": ["bolus", "temp_target", "switch_profile", "save_profile", "delete_profile"],
     "profileEditLimits": {"units": "mmol/L", "maxBasal": 2, "basalRates": [0.05, 0.1], "basalMinimum": 0.05,
                           "carbRatio": {"min": 1, "max": 50, "step": 0.1}, "sensitivity": {"min": 0.5, "max": 30, "step": 0.1},
                           "target": {"min": 4, "max": 10, "step": 0.1}, "maxSegments": 48, "segmentSeconds": 1800},
     "store": {
       "default": {"dia": 6, "carbs_hr": 20, "delay": 0, "timezone": "Europe/Stockholm", "units": "mmol",
                   "basal": [{"time": "00:00", "value": 0.85, "timeAsSeconds": 0}, {"time": "06:00", "value": 1.0, "timeAsSeconds": 21600}],
                   "carbratio": [{"time": "00:00", "value": 10, "timeAsSeconds": 0}],
                   "sens": [{"time": "00:00", "value": 2.8, "timeAsSeconds": 0}],
                   "target_low": [{"time": "00:00", "value": 5.6, "timeAsSeconds": 0}],
                   "target_high": [{"time": "00:00", "value": 5.6, "timeAsSeconds": 0}]},
       "Sport": {"dia": 6, "carbs_hr": 16, "delay": 0, "timezone": "Europe/Stockholm", "units": "mmol",
                 "basal": [{"time": "00:00", "value": 0.5, "timeAsSeconds": 0}, {"time": "06:00", "value": 0.6, "timeAsSeconds": 21600}],
                 "carbratio": [{"time": "00:00", "value": 12, "timeAsSeconds": 0}],
                 "sens": [{"time": "00:00", "value": 3.3, "timeAsSeconds": 0}],
                 "target_low": [{"time": "00:00", "value": 6.7, "timeAsSeconds": 0}],
                 "target_high": [{"time": "00:00", "value": 6.7, "timeAsSeconds": 0}]},
       "Off Grid": {"dia": 6, "carbs_hr": 20, "delay": 0, "timezone": "Europe/Stockholm", "units": "mmol",
                    "basal": [{"time": "00:00", "value": 0.85, "timeAsSeconds": 0}, {"time": "00:15", "value": 0.9, "timeAsSeconds": 900}],
                    "carbratio": [{"time": "00:00", "value": 10, "timeAsSeconds": 0}],
                    "sens": [{"time": "00:00", "value": 2.8, "timeAsSeconds": 0}],
                    "target_low": [{"time": "00:00", "value": 5.6, "timeAsSeconds": 0}],
                    "target_high": [{"time": "00:00", "value": 5.6, "timeAsSeconds": 0}]},
       "Wild": {"dia": 6, "carbs_hr": 20, "delay": 0, "timezone": "Europe/Stockholm", "units": "mmol",
                "basal": [{"time": "00:00", "value": 0.85, "timeAsSeconds": 0}],
                "carbratio": [{"time": "00:00", "value": 10, "timeAsSeconds": 0}],
                "sens": [{"time": "00:00", "value": 0.3, "timeAsSeconds": 0}],
                "target_low": [{"time": "00:00", "value": 5.6, "timeAsSeconds": 0}],
                "target_high": [{"time": "00:00", "value": 5.6, "timeAsSeconds": 0}]}
     }}
    """
}
