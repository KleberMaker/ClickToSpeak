import AppKit
import SwiftUI

@MainActor
final class PanelState: ObservableObject {
    @Published var title = ""
    @Published var listening = false
    @Published var history = Array(repeating: 0.0, count: 23)
    @Published var actionTitle = "Terminer"
    var action: () -> Void = {}

    func push(_ level: Double) {
        history = Array(history.dropFirst()) + [level]
    }
}

private struct PanelContent: View {
    @ObservedObject var state: PanelState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(state.title).font(.system(.body, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if state.listening {
                    if reduceMotion {
                        ProgressView(value: state.history.last ?? 0)
                            .progressViewStyle(.linear).frame(width: 105)
                            .accessibilityLabel("Niveau du microphone")
                    } else {
                        Canvas { context, size in
                            for (index, value) in state.history.enumerated() {
                                let height = CGFloat(max(2, value * Double(size.height)))
                                let bar = CGRect(x: CGFloat(index) * 5, y: (size.height - height) / 2,
                                                 width: 3, height: height)
                                context.fill(Path(roundedRect: bar, cornerRadius: 1.5), with: .color(.accentColor))
                            }
                        }.frame(width: 115, height: 18)
                            .accessibilityLabel("Niveau du microphone")
                            .accessibilityValue("\(Int((state.history.last ?? 0) * 100)) pour cent")
                    }
                }
            }
            Spacer(minLength: 0)
            Button(state.actionTitle) { state.action() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPanel {
    let state = PanelState()
    private lazy var panel: NSPanel = {
        let panel = PassivePanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                                 backing: .buffered, defer: false)
        panel.title = "ClickToSpeak"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PanelContent(state: state))
        return panel
    }()

    func show(_ title: String, near axBounds: CGRect?, listening: Bool = false,
              button: String = "Terminer", action: @escaping () -> Void) {
        state.title = title
        state.listening = listening
        state.actionTitle = button
        state.action = action
        if !listening { state.history = Array(repeating: 0, count: 23) }
        let mouse = NSEvent.mouseLocation
        let rect: CGRect
        if let axBounds, let primary = NSScreen.screens.first {
            rect = CGRect(x: axBounds.minX, y: primary.frame.maxY - axBounds.maxY,
                          width: axBounds.width, height: axBounds.height)
        } else { rect = CGRect(origin: mouse, size: .zero) }
        let screen = NSScreen.screens.first { $0.frame.intersects(rect.insetBy(dx: -1, dy: -1)) }
            ?? NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let width = min(visible.width, title.count > 36 ? 380 : 284)
        let height: CGFloat = title.count > 65 ? 88 : 64
        let x = min(max(visible.minX, rect.minX), visible.maxX - width)
        let below = rect.minY - height - 8
        let y = min(max(visible.minY, below >= visible.minY ? below : rect.maxY + 8), visible.maxY - height)
        panel.setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil); state.action = {}; state.listening = false }
}
