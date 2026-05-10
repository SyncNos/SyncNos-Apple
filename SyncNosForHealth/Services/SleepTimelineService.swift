import HealthKit
import Foundation

final class SleepTimelineService {
    private let store = HKHealthStore()

    func fetchSleepTimeline(for date: Date) async throws -> SleepDayData {
        try await HealthKitAuthorization.requestAuthorization()

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let windowStart = calendar.date(byAdding: .hour, value: -18, to: dayStart)!
        let windowEnd = calendar.date(byAdding: .hour, value: 18, to: dayStart)!

        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(
            withStart: windowStart,
            end: windowEnd,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }

        let daySamples = samples.filter { sample in
            let endDate = sample.endDate
            return endDate >= dayStart && endDate < dayEnd
        }

        let intervals = daySamples.map { sample -> SleepInterval in
            let stage = mapSleepValue(sample.value)
            return SleepInterval(stage: stage, start: sample.startDate, end: sample.endDate)
        }

        return SleepDayData(date: date, intervals: intervals)
    }

    private func mapSleepValue(_ value: Int) -> SleepStage {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepCore: return .asleepCore
        case .asleepDeep: return .asleepDeep
        case .asleepREM: return .asleepREM
        case .asleepUnspecified: return .asleepUnspecified
        default: return .asleepUnspecified
        }
    }
}
