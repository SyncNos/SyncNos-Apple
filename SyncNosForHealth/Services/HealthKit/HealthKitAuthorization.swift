import HealthKit

enum HealthKitAuthorization {
    static let store = HKHealthStore()

    static var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    static func requestAuthorization() async throws {
        guard isHealthDataAvailable else { return }

        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        try await store.requestAuthorization(toShare: [], read: [sleepType])
    }
}
