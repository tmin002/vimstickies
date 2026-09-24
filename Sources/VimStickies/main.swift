import AppKit

@main
enum VimStickiesApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.setActivationPolicy(.regular)
        application.delegate = delegate

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
