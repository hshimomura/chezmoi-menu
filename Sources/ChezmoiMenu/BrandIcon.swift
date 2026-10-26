import AppKit

@MainActor enum BrandIcon {
    static let application: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "house.fill", accessibilityDescription: "Chezmoi")!
    }()

    static let menuBar: NSImage = {
        let image: NSImage
        if let url = Bundle.main.url(forResource: "MenuBarMark", withExtension: "png"),
           let mark = NSImage(contentsOf: url) {
            image = mark
        } else {
            image = NSImage(systemSymbolName: "house", accessibilityDescription: "Chezmoi")!
        }
        image.size = NSSize(width: 20, height: 20)
        // AppKit uses alpha as a mask and chooses the correct color for the menu bar.
        image.isTemplate = true
        image.accessibilityDescription = "Chezmoi Menu"
        return image
    }()
}
