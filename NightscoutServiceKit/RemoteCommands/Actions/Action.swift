//
//  Action.swift
//  LoopKit
//
//  Created by Bill Gestrich on 12/25/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public enum Action: Codable {
    case temporaryScheduleOverride(OverrideAction)
    case cancelTemporaryOverride(OverrideCancelAction)
    case bolusEntry(BolusAction)
    case carbsEntry(CarbAction)
    case profileSwitch(ProfileSwitchAction)
    case profileSave(ProfileSaveAction)
    case profileDelete(ProfileDeleteAction)
    case scheduledSwitchesSave(ScheduledSwitchesSaveAction)
    
    public var description: String {
        return "\(actionName) \(actionParameterDescription)"
    }
    
    var actionName: String {
        switch self {
        case .carbsEntry:
            return LocalizedString("Carb Entry", comment: "The remote action name for Carb Entry")
        case .bolusEntry:
            return LocalizedString("Bolus Entry", comment: "The remote action name for Bolus Entry")
        case .cancelTemporaryOverride:
            return LocalizedString("Cancel Override", comment: "The remote action name for Cancel Override")
        case .temporaryScheduleOverride:
            return LocalizedString("Override", comment: "The remote action name for Override")
        case .profileSwitch:
            return LocalizedString("Profile Switch", comment: "The remote action name for Profile Switch")
        case .profileSave:
            return LocalizedString("Profile Save", comment: "The remote action name for Profile Save")
        case .profileDelete:
            return LocalizedString("Profile Delete", comment: "The remote action name for Profile Delete")
        case .scheduledSwitchesSave:
            return LocalizedString("Scheduled Switches Save", comment: "The remote action name for saving the scheduled profile switches")
        }
    }
    
    var actionParameterDescription: String {
        switch self {
        case .carbsEntry(let carbAction):
            let amountFormatted = Self.numberFormatter.string(from: carbAction.amountInGrams as NSNumber) ?? ""
            return "\(amountFormatted)" + " " + carbGramAbbreviation
        case .bolusEntry(let bolusAction):
            let amountFormatted = Self.numberFormatter.string(from: bolusAction.amountInUnits as NSNumber) ?? ""
            return "\(amountFormatted)" + " " + bolusUnitAbbreviation
        case .cancelTemporaryOverride:
            return ""
        case .temporaryScheduleOverride(let overrideAction):
            return overrideAction.name
        case .profileSwitch(let action):
            return action.name
        case .profileSave(let action):
            return action.name
        case .profileDelete(let action):
            return action.name
        case .scheduledSwitchesSave:
            return ""
        }
    }
    
    var carbGramAbbreviation: String {
        LocalizedString("g", comment: "The remote action abbreviation for gram units")
    }
    
    var bolusUnitAbbreviation: String {
        LocalizedString("U", comment: "The remote action abbreviation for bolus units")
    }
    
    static var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

extension Action {
    /// The name of the profile a therapy profile command targets; for a rename, the new name. Nil for other commands.
    var therapyProfileName: String? {
        switch self {
        case .profileSwitch(let action):
            return action.name
        case .profileSave(let action):
            return action.name
        case .profileDelete(let action):
            return action.name
        case .temporaryScheduleOverride, .cancelTemporaryOverride, .bolusEntry, .carbsEntry, .scheduledSwitchesSave:
            return nil
        }
    }

    private var therapyProfileOutcome: String? {
        switch self {
        case .profileSwitch:
            return "activated"
        case .profileSave:
            return "saved"
        case .profileDelete:
            return "deleted"
        case .scheduledSwitchesSave:
            return "saved"
        case .temporaryScheduleOverride, .cancelTemporaryOverride, .bolusEntry, .carbsEntry:
            return nil
        }
    }

    /// The reply text for a therapy profile command that succeeded, or nil for other commands.
    var therapyProfileSuccessMessage: String? {
        if case .scheduledSwitchesSave = self {
            return "Scheduled switches saved"
        }
        guard let name = therapyProfileName, let outcome = therapyProfileOutcome else {
            return nil
        }
        return "Profile '\(name)' \(outcome)"
    }

    /// The reply text for a therapy profile command that failed, or nil for other commands.
    func therapyProfileFailureMessage(for error: Error) -> String? {
        if case .scheduledSwitchesSave = self {
            return "Scheduled switches not saved: \(error.localizedDescription)"
        }
        guard let name = therapyProfileName, let outcome = therapyProfileOutcome else {
            return nil
        }
        return "Profile '\(name)' not \(outcome): \(error.localizedDescription)"
    }

    /// The reply's `result` code for a therapy profile command (`activated`, `saved`, `deleted`, `conflict`,
    /// `not_found` or `rejected`), or nil for other commands.
    func therapyProfileResult(failure: Error?) -> String? {
        guard let outcome = therapyProfileOutcome else {
            return nil
        }
        switch failure {
        case nil:
            return outcome
        case TherapyProfileError.conflict?, ScheduledProfileSwitchError.conflict?:
            return "conflict"
        case TherapyProfileError.notFound(_)?:
            return "not_found"
        default:
            return "rejected"
        }
    }
}
