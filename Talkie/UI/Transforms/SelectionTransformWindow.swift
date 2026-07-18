import AppKit
import SwiftUI

@MainActor
final class SelectionTransformWindow {
    private var window: NSWindow?
    func show(coordinator: SelectionTransformCoordinator, history: HistoryStore?) {
        let window = self.window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Transform Selection"
        window.contentView = NSHostingView(rootView: SelectionTransformView(coordinator: coordinator, history: history))
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

struct SelectionTransformView: View {
    @Bindable var coordinator: SelectionTransformCoordinator
    let history: HistoryStore?
    @State private var instruction = "Make this clearer and more concise"
    @State private var presetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Transform Selection").font(.title2.bold())
            Text("Selected text stays in memory only for this preview/apply/undo flow.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Transformation instruction", text: $instruction)
                Button("Preview") { Task { await coordinator.preview(instruction: instruction) } }
                    .disabled(coordinator.isWorking || instruction.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let presets = history?.allTransformPresets(), !presets.isEmpty {
                ScrollView(.horizontal) { HStack { ForEach(presets) { preset in
                    Button(preset.name) {
                        instruction = preset.instruction
                        Task { await coordinator.preview(instruction: preset.instruction) }
                    }
                } } }
            }
            if coordinator.isWorking { ProgressView("Transforming…") }
            if let error = coordinator.errorMessage { Text(error).foregroundStyle(.red) }
            if let preview = coordinator.preview {
                HSplitView {
                    previewPane("Original", preview.original, color: .red)
                    previewPane("Result", preview.transformed, color: .green)
                }
                HStack {
                    Button("Retry") { Task { await coordinator.retry() } }
                    Button("Undo") { _ = coordinator.undo() }
                        .disabled(!coordinator.wasApplied)
                    Spacer()
                    Button("Apply") { _ = coordinator.apply() }.buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView("Choose a transform", systemImage: "wand.and.stars",
                                       description: Text("Preview before anything is changed."))
            }
            Divider()
            HStack {
                TextField("Preset name", text: $presetName).frame(width: 150)
                Button("Save current instruction") {
                    history?.addTransformPreset(name: presetName, instruction: instruction)
                    presetName = ""
                }.disabled(presetName.isEmpty || instruction.isEmpty)
            }
        }.padding(20).frame(minWidth: 620, minHeight: 420)
    }

    private func previewPane(_ title: String, _ text: String, color: Color) -> some View {
        VStack(alignment: .leading) {
            Label(title, systemImage: title == "Original" ? "minus.circle" : "plus.circle")
                .foregroundStyle(color).font(.headline)
            ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .padding(10).background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }.padding(4)
    }
}
