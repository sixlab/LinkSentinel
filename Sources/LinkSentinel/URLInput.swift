import SwiftUI
import AppKit

// NSViewRepresentable gives reliable focus + select-all on every window presentation.
struct URLInput: NSViewRepresentable {
    @Binding var text: String
    let focusToken: UUID
    let isMonitoring: Bool

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "https://www.gstatic.com/generate_204"
        field.font = .systemFont(ofSize: 14)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.delegate = context.coordinator
        field.setAccessibilityLabel("监控链接")
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        // Remain selectable when monitoring so reopening always selects the URL.
        field.isEditable = !isMonitoring
        field.isSelectable = true
        if context.coordinator.lastFocus != focusToken {
            context.coordinator.lastFocus = focusToken
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.selectText(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: URLInput
        var lastFocus: UUID?
        init(_ parent: URLInput) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}
