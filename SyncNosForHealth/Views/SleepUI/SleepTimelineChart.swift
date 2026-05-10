import SwiftUI

struct SleepTimelineChart: View {
    let data: SleepDayData

    private var timeRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: data.date)
        let rangeStart = calendar.date(byAdding: .hour, value: -6, to: dayStart)!
        let rangeEnd = calendar.date(byAdding: .hour, value: 12, to: dayStart)!
        return rangeStart...rangeEnd
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Timeline")
                .font(.headline)

            Canvas { context, size in
                let range = timeRange
                let totalSeconds = range.upperBound.timeIntervalSince(range.lowerBound)

                for interval in data.intervals {
                    let startFrac = max(0, interval.start.timeIntervalSince(range.lowerBound) / totalSeconds)
                    let endFrac = min(1, interval.end.timeIntervalSince(range.lowerBound) / totalSeconds)

                    guard endFrac > startFrac else { continue }

                    let rect = CGRect(
                        x: startFrac * size.width,
                        y: 0,
                        width: (endFrac - startFrac) * size.width,
                        height: size.height
                    )

                    context.fill(
                        Path(rect),
                        with: .color(colorForStage(interval.stage))
                    )
                }
            }
            .frame(height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Text(formatHour(timeRange.lowerBound))
                Spacer()
                Text(formatHour(timeRange.upperBound))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach([SleepStage.asleepCore, .asleepDeep, .asleepREM, .awake, .inBed], id: \.self) { stage in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForStage(stage))
                            .frame(width: 8, height: 8)
                        Text(stage.displayName)
                            .font(.caption2)
                    }
                }
            }

            Text("Total sleep: \(data.totalSleepMinutes) min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func colorForStage(_ stage: SleepStage) -> Color {
        switch stage {
        case .asleepCore: return .blue
        case .asleepDeep: return .indigo
        case .asleepREM: return .purple
        case .asleepUnspecified: return .cyan
        case .awake: return .orange
        case .inBed: return .gray.opacity(0.3)
        }
    }

    private func formatHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
