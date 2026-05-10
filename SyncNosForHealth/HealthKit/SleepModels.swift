import Foundation

enum SleepStage: String, CaseIterable {
    case inBed
    case awake
    case asleepCore
    case asleepDeep
    case asleepREM
    case asleepUnspecified

    var displayName: String {
        switch self {
        case .inBed: return "In Bed"
        case .awake: return "Awake"
        case .asleepCore: return "Core"
        case .asleepDeep: return "Deep"
        case .asleepREM: return "REM"
        case .asleepUnspecified: return "Asleep"
        }
    }

    var isAsleep: Bool {
        switch self {
        case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return true
        case .inBed, .awake:
            return false
        }
    }
}

struct SleepInterval: Identifiable {
    let id = UUID()
    let stage: SleepStage
    let start: Date
    let end: Date
}

struct SleepDayData {
    let date: Date
    let intervals: [SleepInterval]

    var totalSleepMinutes: Int {
        let asleepIntervals = intervals.filter { $0.stage.isAsleep }
        let merged = mergeIntervals(asleepIntervals)
        let totalSeconds = merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        return Int(totalSeconds / 60)
    }

    private func mergeIntervals(_ intervals: [SleepInterval]) -> [(start: Date, end: Date)] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = (last.start, max(last.end, interval.end))
            } else {
                merged.append((start: interval.start, end: interval.end))
            }
        }
        return merged
    }
}
