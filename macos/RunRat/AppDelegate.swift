import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var metricsMonitor: SystemMetricsMonitor?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let metricsMonitor = SystemMetricsMonitor()
        let statusBarController = StatusBarController(metricsMonitor: metricsMonitor)

        self.metricsMonitor = metricsMonitor
        self.statusBarController = statusBarController

        metricsMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.tearDown()
        metricsMonitor?.stop()
    }
}
