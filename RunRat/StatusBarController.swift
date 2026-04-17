import AppKit
import SwiftUI

final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 32)
    private let metricsMonitor: SystemMetricsMonitor
    private let renderer = RatIconRenderer()
    private let viewModel = DashboardViewModel()
    private let popover = NSPopover()
    private let animationController = RatAnimationController()
    private var ratView: StatusBarRatView?

    private var currentSnapshot = SystemSnapshot(
        cpu: CPUStats(totalPercent: nil, userPercent: nil, systemPercent: nil, idlePercent: nil, logicalCoreCount: ProcessInfo.processInfo.activeProcessorCount),
        gpu: GPUStats(maximumPercent: nil),
        memory: MemoryStats(usedBytes: nil, totalBytes: ProcessInfo.processInfo.physicalMemory, wiredBytes: nil, compressedBytes: nil, appMemoryBytes: nil, cachedBytes: nil, swapUsedBytes: nil, pressurePercent: nil),
        storage: StorageStats(usedBytes: nil, totalBytes: nil, availableBytes: nil),
        battery: BatteryStats(percentage: nil, isCharging: nil, cycleCount: nil, maximumCapacityPercent: nil),
        network: NetworkStats(displayName: nil, localAddress: nil, uploadBytesPerSecond: nil, downloadBytesPerSecond: nil),
        timestamp: .now
    )
    private var animationPhase = 0
    private var animationTimer: DispatchSourceTimer?
    private var currentAnimationInterval: TimeInterval = 0.50
    private var currentSpeedSource: AnimationSpeedSource = .cpu
    private var currentDisplayLoadPercent: Double = 0
    private var cpuHistory: [Double] = []
    private var memoryHistory: [Double] = []
    private var networkHistory: [Double] = []
    private var eventMonitor: Any?

    init(metricsMonitor: SystemMetricsMonitor) {
        self.metricsMonitor = metricsMonitor
        super.init()

        configurePopover()
        configureStatusItem()
        bindMetrics()
        restartAnimationTimer(interval: currentAnimationInterval)
        publishState()
        updateStatusImage()
    }

    func tearDown() {
        animationTimer?.cancel()
        animationTimer = nil
        removeEventMonitor()
        popover.performClose(nil)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(
                viewModel: viewModel,
                openActivityMonitor: { [weak self] in self?.openActivityMonitor() },
                quitApp: { [weak self] in self?.quitApp() }
            )
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        statusItem.length = renderer.size.width

        button.title = ""
        button.image = nil
        button.imagePosition = .imageOnly
        button.appearsDisabled = false
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let ratView = StatusBarRatView(frame: button.bounds)
        ratView.autoresizingMask = [.width, .height]
        button.addSubview(ratView)
        self.ratView = ratView
        ratView.update(image: renderer.image(for: animationPhase))
    }

    private func bindMetrics() {
        metricsMonitor.onUpdate = { [weak self] snapshot in
            self?.handle(snapshot: snapshot)
        }
    }

    private func handle(snapshot: SystemSnapshot) {
        currentSnapshot = snapshot

        let animationSnapshot = animationController.update(snapshot: snapshot)

        if let cpuPercent = snapshot.cpu.totalPercent {
            appendHistoryValue(cpuPercent, to: &cpuHistory)
        }

        if let used = snapshot.memory.usedBytes, snapshot.memory.totalBytes > 0 {
            let ratio = (Double(used) / Double(snapshot.memory.totalBytes)) * 100
            appendHistoryValue(ratio, to: &memoryHistory)
        } else if let pressure = snapshot.memory.pressurePercent {
            appendHistoryValue(pressure, to: &memoryHistory)
        }

        let networkMagnitude = Double((snapshot.network.uploadBytesPerSecond ?? 0) + (snapshot.network.downloadBytesPerSecond ?? 0))
        appendHistoryValue(networkMagnitude, to: &networkHistory)

        let newInterval = animationSnapshot.frameDuration
        currentSpeedSource = animationSnapshot.effectiveSource
        currentDisplayLoadPercent = animationSnapshot.smoothedLoadPercent

        if abs(newInterval - currentAnimationInterval) >= 0.005 {
            currentAnimationInterval = newInterval
            restartAnimationTimer(interval: newInterval)
        }

        publishState()
        updateStatusImage()
    }

    private func publishState() {
        viewModel.activityName = currentSpeedSource.displayName
        viewModel.currentCPUPercent = currentSnapshot.cpu.totalPercent
        viewModel.cpuUserPercent = currentSnapshot.cpu.userPercent
        viewModel.cpuSystemPercent = currentSnapshot.cpu.systemPercent
        viewModel.cpuIdlePercent = currentSnapshot.cpu.idlePercent
        viewModel.memoryUsedBytes = currentSnapshot.memory.usedBytes
        viewModel.memoryTotalBytes = currentSnapshot.memory.totalBytes
        viewModel.memoryPressurePercent = currentSnapshot.memory.pressurePercent
        viewModel.appMemoryBytes = currentSnapshot.memory.appMemoryBytes
        viewModel.wiredMemoryBytes = currentSnapshot.memory.wiredBytes
        viewModel.compressedMemoryBytes = currentSnapshot.memory.compressedBytes
        viewModel.cachedMemoryBytes = currentSnapshot.memory.cachedBytes
        viewModel.swapUsedBytes = currentSnapshot.memory.swapUsedBytes
        viewModel.storageUsedBytes = currentSnapshot.storage.usedBytes
        viewModel.storageTotalBytes = currentSnapshot.storage.totalBytes
        viewModel.batteryPercent = currentSnapshot.battery.percentage
        viewModel.isCharging = currentSnapshot.battery.isCharging
        viewModel.batteryCycleCount = currentSnapshot.battery.cycleCount
        viewModel.batteryHealthPercent = currentSnapshot.battery.maximumCapacityPercent
        viewModel.networkDisplayName = currentSnapshot.network.displayName
        viewModel.networkLocalAddress = currentSnapshot.network.localAddress
        viewModel.uploadBytesPerSecond = currentSnapshot.network.uploadBytesPerSecond
        viewModel.downloadBytesPerSecond = currentSnapshot.network.downloadBytesPerSecond
        viewModel.cpuHistory = cpuHistory
        viewModel.memoryHistory = memoryHistory
        viewModel.networkHistory = networkHistory
    }

    private func restartAnimationTimer(interval: TimeInterval) {
        animationTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.animationPhase = (self.animationPhase + 1) % max(self.renderer.frameCount, 1)
            self.updateStatusImage()
        }

        animationTimer = timer
        timer.resume()
    }

    private func updateStatusImage() {
        ratView?.update(image: renderer.image(for: animationPhase))
        statusItem.button?.toolTip = "RunRat: \(currentSpeedSource.displayName) \(Int(currentDisplayLoadPercent.rounded()))%"
    }

    private func appendHistoryValue(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 30 {
            history.removeFirst(history.count - 30)
        }
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            removeEventMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            installEventMonitor()
        }
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.popover.performClose(nil)
                self?.removeEventMonitor()
            }
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    @objc
    private func openActivityMonitor() {
        let configuration = NSWorkspace.OpenConfiguration()
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

private final class StatusBarRatView: NSView {
    private var image: NSImage?

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(image: NSImage?) {
        self.image = image
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let image,
              image.size.width > 0,
              image.size.height > 0,
              let context = NSGraphicsContext.current?.cgContext
        else {
            return
        }

        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        let verticalInset: CGFloat = 1.0
        let targetHeight = max(bounds.height - (verticalInset * 2.0), 1.0)
        let scale = targetHeight / image.size.height
        let targetWidth = image.size.width * scale
        let drawRect = CGRect(
            x: round((bounds.width - targetWidth) / 2.0),
            y: round((bounds.height - targetHeight) / 2.0),
            width: targetWidth,
            height: targetHeight
        )

        context.saveGState()
        image.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.setBlendMode(.sourceIn)
        context.setFillColor(NSColor.labelColor.cgColor)
        context.fill(drawRect)
        context.restoreGState()
    }
}

private enum AnimationSpeedSource: Equatable {
    case cpu
    case gpu
    case memory

    var displayName: String {
        switch self {
        case .cpu:
            return "CPU"
        case .gpu:
            return "GPU"
        case .memory:
            return "Memory"
        }
    }

    static func fromDefaults() -> AnimationSpeedSource {
        guard let rawValue = UserDefaults.standard.string(forKey: "RunRatSpeedSource")?.lowercased() else {
            return .cpu
        }

        switch rawValue {
        case "gpu":
            return .gpu
        case "memory":
            return .memory
        default:
            return .cpu
        }
    }
}

private enum FPSMaxLimit: Equatable {
    case fps40
    case fps30
    case fps20
    case fps10

    var rate: Double {
        switch self {
        case .fps40:
            return 1.0
        case .fps30:
            return 0.75
        case .fps20:
            return 0.5
        case .fps10:
            return 0.25
        }
    }

    static func fromDefaults() -> FPSMaxLimit {
        guard let rawValue = UserDefaults.standard.string(forKey: "RunRatFPSMaxLimit")?.lowercased() else {
            return .fps40
        }

        switch rawValue {
        case "30fps", "30":
            return .fps30
        case "20fps", "20":
            return .fps20
        case "10fps", "10":
            return .fps10
        default:
            return .fps40
        }
    }
}

private struct RatAnimationSnapshot {
    let smoothedLoadPercent: Double
    let effectiveSource: AnimationSpeedSource
    let frameDuration: TimeInterval
}

private final class RatAnimationController {
    private(set) var smoothedLoadPercent: Double = 0

    private let sampleWindowSize: Int
    private let fetchCounterSize: Int
    private var fetchCounter: Int
    private var hasGPUReading = false
    private var currentEffectiveSource: AnimationSpeedSource = AnimationSpeedSource.fromDefaults()
    private var currentFrameDuration: TimeInterval = 0.5
    private var cpuSamples: [Double] = []
    private var gpuSamples: [Double] = []
    private var memorySamples: [Double] = []

    init(sampleWindowSize: Int = 5, fetchCounterSize: Int = 5) {
        self.sampleWindowSize = max(sampleWindowSize, 1)
        self.fetchCounterSize = max(fetchCounterSize, 1)
        self.fetchCounter = 0
    }

    func update(snapshot: SystemSnapshot) -> RatAnimationSnapshot {
        let selectedSource = AnimationSpeedSource.fromDefaults()
        let selectedFPSLimit = FPSMaxLimit.fromDefaults()

        append(sample: min(max(snapshot.cpu.totalPercent ?? 0, 0), 100), to: &cpuSamples)
        if let gpuPercent = snapshot.gpu.maximumPercent {
            hasGPUReading = true
            append(sample: min(max(gpuPercent, 0), 100), to: &gpuSamples)
        }

        let memoryLoad: Double
        if let usedBytes = snapshot.memory.usedBytes, snapshot.memory.totalBytes > 0 {
            memoryLoad = min(max((Double(usedBytes) / Double(snapshot.memory.totalBytes)) * 100.0, 0), 100)
        } else {
            memoryLoad = 0
        }
        append(sample: memoryLoad, to: &memorySamples)

        fetchCounter += 1
        if fetchCounter >= fetchCounterSize {
            fetchCounter = 0

            let effectiveSource = resolvedSource(for: selectedSource, gpuLoadAvailable: hasGPUReading)
            smoothedLoadPercent = resolvedLoad(
                for: selectedSource,
                cpuLoad: average(of: cpuSamples),
                gpuLoad: average(of: gpuSamples),
                memoryLoad: average(of: memorySamples),
                gpuLoadAvailable: hasGPUReading
            )
            currentEffectiveSource = effectiveSource
            currentFrameDuration = calculateInterval(for: smoothedLoadPercent, fpsMaxLimit: selectedFPSLimit)
        }

        return RatAnimationSnapshot(
            smoothedLoadPercent: smoothedLoadPercent,
            effectiveSource: currentEffectiveSource,
            frameDuration: currentFrameDuration
        )
    }

    private func append(sample: Double, to samples: inout [Double]) {
        samples.append(sample)
        if samples.count > sampleWindowSize {
            samples.removeFirst(samples.count - sampleWindowSize)
        }
    }

    private func average(of samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    private func resolvedLoad(
        for source: AnimationSpeedSource,
        cpuLoad: Double,
        gpuLoad: Double,
        memoryLoad: Double,
        gpuLoadAvailable: Bool
    ) -> Double {
        switch source {
        case .cpu:
            return cpuLoad
        case .gpu:
            return gpuLoadAvailable ? gpuLoad : cpuLoad
        case .memory:
            return memoryLoad
        }
    }

    private func resolvedSource(for source: AnimationSpeedSource, gpuLoadAvailable: Bool) -> AnimationSpeedSource {
        switch source {
        case .gpu:
            return gpuLoadAvailable ? .gpu : .cpu
        case .cpu, .memory:
            return source
        }
    }

    private func calculateInterval(for loadPercent: Double, fpsMaxLimit: FPSMaxLimit) -> TimeInterval {
        let speed = max(1.0, (loadPercent / 5.0) * fpsMaxLimit.rate)
        return 0.5 / speed
    }
}
