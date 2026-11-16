//
//  StoredWorkout.swift
//  NightscoutServiceKit
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import NightscoutKit

extension StoredWorkout {
    func treatment(enteredBy: String) -> ExerciseNightscoutTreatment {
        ExerciseNightscoutTreatment(timestamp: startDate, enteredBy: enteredBy, duration: duration, notes: notes, id: uuid.uuidString, syncIdentifier: uuid.uuidString)
    }

    var notes: String {
        var parts = [activityName]
        if let totalDistance, totalDistance > 0 {
            parts.append(String(format: "%.2f km", totalDistance / 1000))
        }
        if let totalEnergyBurned, totalEnergyBurned > 0 {
            parts.append(String(format: "%.0f kcal", totalEnergyBurned))
        }
        if let averageHeartRate {
            parts.append(String(format: "avg HR %.0f", averageHeartRate))
        }
        return parts.joined(separator: ", ")
    }

    private var activityName: String {
        switch activityType {
        case .americanFootball: "American Football"
        case .archery: "Archery"
        case .australianFootball: "Australian Football"
        case .badminton: "Badminton"
        case .barre: "Barre"
        case .baseball: "Baseball"
        case .basketball: "Basketball"
        case .bowling: "Bowling"
        case .boxing: "Boxing"
        case .climbing: "Climbing"
        case .coreTraining: "Core Training"
        case .cricket: "Cricket"
        case .crossCountrySkiing: "Cross Country Skiing"
        case .crossTraining: "Cross Training"
        case .curling: "Curling"
        case .cycling: "Cycling"
        case .downhillSkiing: "Downhill Skiing"
        case .elliptical: "Elliptical"
        case .equestrianSports: "Equestrian Sports"
        case .fencing: "Fencing"
        case .fishing: "Fishing"
        case .flexibility: "Flexibility"
        case .functionalStrengthTraining: "Functional Strength Training"
        case .golf: "Golf"
        case .gymnastics: "Gymnastics"
        case .handball: "Handball"
        case .handCycling: "Hand Cycling"
        case .highIntensityIntervalTraining: "High Intensity Interval Training"
        case .hiking: "Hiking"
        case .hockey: "Hockey"
        case .hunting: "Hunting"
        case .jumpRope: "Jump Rope"
        case .kickboxing: "Kickboxing"
        case .lacrosse: "Lacrosse"
        case .martialArts: "Martial Arts"
        case .mindAndBody: "Mind and Body"
        case .mixedCardio: "Mixed Cardio"
        case .paddleSports: "Paddle Sports"
        case .pilates: "Pilates"
        case .play: "Play"
        case .preparationAndRecovery: "Preparation and Recovery"
        case .racquetball: "Racquetball"
        case .rowing: "Rowing"
        case .rugby: "Rugby"
        case .running: "Running"
        case .sailing: "Sailing"
        case .skatingSports: "Skating"
        case .snowboarding: "Snowboarding"
        case .snowSports: "Snow Sports"
        case .soccer: "Soccer"
        case .softball: "Softball"
        case .squash: "Squash"
        case .stairClimbing: "Stair Climbing"
        case .stairs: "Stairs"
        case .stepTraining: "Step Training"
        case .surfingSports: "Surfing"
        case .swimming: "Swimming"
        case .tableTennis: "Table Tennis"
        case .taiChi: "Tai Chi"
        case .tennis: "Tennis"
        case .trackAndField: "Track and Field"
        case .traditionalStrengthTraining: "Strength Training"
        case .volleyball: "Volleyball"
        case .walking: "Walking"
        case .waterFitness: "Water Fitness"
        case .waterPolo: "Water Polo"
        case .waterSports: "Water Sports"
        case .wheelchairRunPace: "Wheelchair Run Pace"
        case .wheelchairWalkPace: "Wheelchair Walk Pace"
        case .wrestling: "Wrestling"
        case .yoga: "Yoga"
        default: "Workout"
        }
    }
}
