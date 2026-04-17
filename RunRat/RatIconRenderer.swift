import AppKit

struct RatIconRenderer {
    let size = NSSize(width: 40, height: 18)
    let frameCount = 6

    private let frameNames = [
        "runRat0",
        "runRat1",
        "runRat2",
        "runRat3",
        "runRat4",
        "runRat5",
    ]

    func image(for phase: Int) -> NSImage? {
        let index = phase % frameNames.count
        guard let image = NSImage(named: frameNames[index]) else {
            return nil
        }

        image.isTemplate = true
        return image
    }
}
