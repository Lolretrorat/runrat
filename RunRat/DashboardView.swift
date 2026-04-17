import SwiftUI

final class DashboardViewModel: ObservableObject {
    @Published var activityName: String = "Idle"
    @Published var currentCPUPercent: Double?
    @Published var cpuUserPercent: Double?
    @Published var cpuSystemPercent: Double?
    @Published var cpuIdlePercent: Double?
    @Published var memoryUsedBytes: UInt64?
    @Published var memoryTotalBytes: UInt64 = 0
    @Published var memoryPressurePercent: Double?
    @Published var appMemoryBytes: UInt64?
    @Published var wiredMemoryBytes: UInt64?
    @Published var compressedMemoryBytes: UInt64?
    @Published var cachedMemoryBytes: UInt64?
    @Published var swapUsedBytes: UInt64?
    @Published var storageUsedBytes: UInt64?
    @Published var storageTotalBytes: UInt64?
    @Published var batteryPercent: Double?
    @Published var isCharging: Bool?
    @Published var batteryCycleCount: Int?
    @Published var batteryHealthPercent: Double?
    @Published var networkDisplayName: String?
    @Published var networkLocalAddress: String?
    @Published var uploadBytesPerSecond: UInt64?
    @Published var downloadBytesPerSecond: UInt64?
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var networkHistory: [Double] = []
}

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let openActivityMonitor: () -> Void
    let quitApp: () -> Void

    private let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private let panelSpacing: CGFloat = 8
    private let contentPadding: CGFloat = 10

    var body: some View {
        mainPanel
        .padding(4)
        .frame(width: 248)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 0.98)))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cpuSection {
                DashboardSection(title: "CPU", icon: "cpu", rows: cpuSection.rows, headline: cpuSection.headline, sparkline: viewModel.cpuHistory, sparklineScale: .bounded(min: 0, max: 100))
            }

            if let memorySection {
                DashboardSection(title: "Memory", icon: "memorychip", rows: memorySection.rows, headline: memorySection.headline, sparkline: viewModel.memoryHistory, sparklineScale: .adaptive(minRange: 4))
            }

            if let storageSection {
                DashboardSection(title: "Storage", icon: "internaldrive", rows: storageSection.rows, headline: storageSection.headline)
            }

            if let batterySection {
                DashboardSection(title: "Battery", icon: "battery.75", rows: batterySection.rows, headline: batterySection.headline)
            }

            if let networkSection {
                DashboardSection(title: "Network", icon: "network", rows: networkSection.rows, headline: networkSection.headline, sparkline: viewModel.networkHistory, sparklineScale: .adaptive(minRange: 1024), showsDivider: false)
            }

            footerActions
                .padding(.top, 8)
        }
        .padding(contentPadding)
        .frame(width: 240, alignment: .topLeading)
        .background(panelBackground)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private var cpuSection: SectionContent? {
        guard let cpu = viewModel.currentCPUPercent else { return nil }
        let rows = [
            MetricRow(label: "Mode", value: viewModel.activityName),
            MetricRow(label: "System", value: String(format: "%.1f%%", viewModel.cpuSystemPercent ?? 0)),
            MetricRow(label: "User", value: String(format: "%.1f%%", viewModel.cpuUserPercent ?? 0)),
            MetricRow(label: "Idle", value: String(format: "%.1f%%", viewModel.cpuIdlePercent ?? 0))
        ]
        return SectionContent(headline: String(format: "%.1f%%", cpu), rows: rows)
    }

    private var memorySection: SectionContent? {
        guard let used = viewModel.memoryUsedBytes else { return nil }
        var rows = [MetricRow(label: "Pressure", value: String(format: "%.1f%%", viewModel.memoryPressurePercent ?? 0))]
        if let appMemory = viewModel.appMemoryBytes {
            rows.append(MetricRow(label: "App Memory", value: format(bytes: appMemory)))
        }
        if let wired = viewModel.wiredMemoryBytes {
            rows.append(MetricRow(label: "Wired", value: format(bytes: wired)))
        }
        if let compressed = viewModel.compressedMemoryBytes {
            rows.append(MetricRow(label: "Compressed", value: format(bytes: compressed)))
        }
        return SectionContent(headline: "\(format(bytes: used)) / \(format(bytes: viewModel.memoryTotalBytes))", rows: rows)
    }

    private var storageSection: SectionContent? {
        guard let used = viewModel.storageUsedBytes, let total = viewModel.storageTotalBytes, total > 0 else { return nil }
        let headline = String(format: "%.1f%% used", (Double(used) / Double(total)) * 100)
        let rows = [MetricRow(label: "Capacity", value: "\(format(bytes: used)) / \(format(bytes: total))")]
        return SectionContent(headline: headline, rows: rows)
    }

    private var batterySection: SectionContent? {
        guard let percentage = viewModel.batteryPercent else { return nil }
        var rows = [MetricRow(label: "Power", value: (viewModel.isCharging ?? false) ? "Charging" : "Battery")]
        if let health = viewModel.batteryHealthPercent {
            rows.append(MetricRow(label: "Max Capacity", value: String(format: "%.1f%%", health)))
        }
        if let cycleCount = viewModel.batteryCycleCount {
            rows.append(MetricRow(label: "Cycle Count", value: "\(cycleCount)"))
        }
        return SectionContent(headline: String(format: "%.1f%%", percentage), rows: rows)
    }

    private var networkSection: SectionContent? {
        guard viewModel.networkDisplayName != nil || viewModel.uploadBytesPerSecond != nil || viewModel.downloadBytesPerSecond != nil else {
            return nil
        }
        var rows: [MetricRow] = []
        if let localAddress = viewModel.networkLocalAddress {
            rows.append(MetricRow(label: "Local IP", value: localAddress))
        }
        if let upload = viewModel.uploadBytesPerSecond {
            rows.append(MetricRow(label: "Upload", value: formatRate(upload)))
        }
        if let download = viewModel.downloadBytesPerSecond {
            rows.append(MetricRow(label: "Download", value: formatRate(download)))
        }
        return SectionContent(headline: viewModel.networkDisplayName ?? "Network", rows: rows)
    }

    private func format(bytes: UInt64) -> String {
        byteCountFormatter.string(fromByteCount: Int64(bytes))
    }

    private func formatRate(_ bytes: UInt64) -> String {
        bytes == 0 ? "0 B/s" : "\(format(bytes: bytes))/s"
    }

    private var footerActions: some View {
        HStack(spacing: 8) {
            FooterButton(title: "Activity Monitor", action: openActivityMonitor)
            FooterButton(title: "Quit", action: quitApp)
        }
    }
}

private struct SectionContent {
    let headline: String
    let rows: [MetricRow]
}

private struct MetricRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct DashboardSection: View {
    let title: String
    let icon: String
    let rows: [MetricRow]
    let headline: String
    var sparkline: [Double] = []
    var sparklineScale: SparklineScale = .adaptive(minRange: 1)
    var showsDivider: Bool = true

    private let verticalSpacing: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(headline)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                    Spacer()
                    Text(row.value)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.84))
                }
            }

            if sparkline.count > 1 {
                SparklineView(values: sparkline, scaleMode: sparklineScale)
                    .frame(height: 16)
                    .padding(.top, 2)
            }

            if showsDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct FooterButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(tileBackground)
        }
        .buttonStyle(.plain)
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private enum SparklineScale {
    case adaptive(minRange: Double)
    case bounded(min: Double, max: Double)
}

private struct SparklineView: View {
    let values: [Double]
    let scaleMode: SparklineScale

    var body: some View {
        GeometryReader { geometry in
            let points = normalisedPoints(in: geometry.size)

            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(Color.white.opacity(0.52), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }
    }

    private func normalisedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let minValue: Double
        let maxValue: Double

        switch scaleMode {
        case let .adaptive(minRange):
            let currentMin = values.min() ?? 0
            let currentMax = values.max() ?? 1
            let currentMid = (currentMin + currentMax) / 2.0
            let halfRange = max((currentMax - currentMin) / 2.0, minRange / 2.0)
            minValue = currentMid - halfRange
            maxValue = currentMid + halfRange
        case let .bounded(min, max):
            minValue = min
            maxValue = max
        }

        let range = max(maxValue - minValue, 1)
        let step = size.width / CGFloat(max(values.count - 1, 1))

        return values.enumerated().map { index, value in
            let x = CGFloat(index) * step
            let clamped = min(max(value, minValue), maxValue)
            let normalised = (clamped - minValue) / range
            let y = size.height - (CGFloat(normalised) * size.height)
            return CGPoint(x: x, y: y)
        }
    }
}
