import AppKit
import SwiftUI
import Combine

private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class SubtitleWindowController: NSObject, NSWindowDelegate {

    static let shared = SubtitleWindowController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<SubtitlePanelView>?
    private var sizeObserver: AnyCancellable?
    private var screenObserver: AnyCancellable?
    private var isManuallySized = AppSettings.shared.subtitleWindowHeight > 0

    private let minWidth: CGFloat = 300
    private let maxWidth: CGFloat = 900
    private let positionXKey = "subtitleWindowX"
    private let positionYKey = "subtitleWindowY"

    func show() {
        if panel == nil {
            createPanel()
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        guard let panel else { show(); return }
        panel.isVisible ? hide() : show()
    }

    func resetPosition() {
        guard let screen = NSScreen.main else { return }
        let size = panel?.frame.size ?? NSSize(width: 600, height: 80)
        let frame = bottomCenterFrame(size: size, on: screen)
        panel?.setFrame(frame, display: true, animate: true)
        savePosition(frame.origin)
    }

    private func createPanel() {
        let savedHeight = AppSettings.shared.subtitleWindowHeight
        let width = min(maxWidth, max(minWidth, CGFloat(AppSettings.shared.windowWidth)))
        let height = savedHeight > 0 ? max(60, CGFloat(savedHeight)) : 80
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isMovable = true
        panel.minSize = NSSize(width: minWidth, height: 60)
        panel.maxSize = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
        panel.ignoresMouseEvents = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.delegate = self

        let hostingView = DraggableHostingView(rootView: SubtitlePanelView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel

        restorePosition(width: width, height: height)

        // Observe content changes to auto-resize.
        sizeObserver = SpeechRecognizer.shared.$segments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.sizeToFit()
            }

        screenObserver = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.ensureVisibleAndSave()
            }
    }

    private func sizeToFit() {
        guard !isManuallySized, let panel, let hostingView else { return }

        hostingView.layoutSubtreeIfNeeded()

        let targetWidth = min(maxWidth, max(minWidth, hostingView.intrinsicContentSize.width))
        let fitSize = hostingView.fittingSize
        let newHeight = max(60, fitSize.height)

        let currentFrame = panel.frame
        let heightDelta = newHeight - currentFrame.height

        let newFrame = NSRect(
            x: currentFrame.minX,
            y: currentFrame.minY - heightDelta,
            width: targetWidth,
            height: newHeight
        )

        panel.setFrame(newFrame, display: true, animate: true)
    }

    func windowDidMove(_ notification: Notification) {
        ensureVisibleAndSave()
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        isManuallySized = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else { return }
        AppSettings.shared.windowWidth = panel.frame.width
        AppSettings.shared.subtitleWindowHeight = panel.frame.height
        ensureVisibleAndSave()
    }

    private func restorePosition(width: CGFloat, height: CGFloat) {
        guard let panel, let screen = NSScreen.main else { return }
        let defaults = UserDefaults.standard
        let defaultFrame = bottomCenterFrame(size: NSSize(width: width, height: height), on: screen)

        guard defaults.object(forKey: positionXKey) != nil,
              defaults.object(forKey: positionYKey) != nil else {
            panel.setFrame(defaultFrame, display: true)
            return
        }

        let savedFrame = NSRect(
            x: defaults.double(forKey: positionXKey),
            y: defaults.double(forKey: positionYKey),
            width: width,
            height: height
        )
        let frame = isVisible(savedFrame) ? savedFrame : defaultFrame
        panel.setFrame(frame, display: true)
        if frame == defaultFrame {
            savePosition(frame.origin)
        }
    }

    private func ensureVisibleAndSave() {
        guard let panel else { return }
        if !isVisible(panel.frame), let screen = NSScreen.main {
            panel.setFrame(bottomCenterFrame(size: panel.frame.size, on: screen), display: true, animate: true)
        }
        savePosition(panel.frame.origin)
    }

    private func isVisible(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let intersection = screen.visibleFrame.intersection(frame)
            return intersection.width >= min(40, frame.width)
                && intersection.height >= min(40, frame.height)
        }
    }

    private func bottomCenterFrame(size: NSSize, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.minY + 80
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func savePosition(_ origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: positionXKey)
        UserDefaults.standard.set(origin.y, forKey: positionYKey)
    }
}
