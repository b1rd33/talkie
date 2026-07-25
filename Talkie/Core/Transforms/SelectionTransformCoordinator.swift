import Foundation
import Observation

protocol SelectionTransforming: Sendable {
    func transform(_ text: String, instruction: String) async throws -> String
}

@MainActor
final class SelectionTarget {
    let originalText: String
    private let replaceHandler: (String) -> Bool

    init(originalText: String, replace: @escaping (String) -> Bool) {
        self.originalText = originalText
        self.replaceHandler = replace
    }

    func replace(with text: String) -> Bool { replaceHandler(text) }
}

struct SelectionTransformPreview: Equatable {
    let original: String
    let transformed: String
    let instruction: String
}

@MainActor
@Observable
final class SelectionTransformCoordinator {
    private(set) var preview: SelectionTransformPreview?
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    private(set) var wasApplied = false
    private var target: SelectionTarget?
    private let transformer: SelectionTransforming

    init(transformer: SelectionTransforming) { self.transformer = transformer }

    func capture(_ target: SelectionTarget?) {
        dismiss()
        guard let target,
              !target.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        self.target = target
    }

    func preview(instruction: String) async {
        guard let target,
              !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await transformer.transform(target.originalText,
                                                         instruction: instruction)
            guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "The transform returned no text."
                return
            }
            preview = SelectionTransformPreview(original: target.originalText,
                                                transformed: result,
                                                instruction: instruction)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func retry() async {
        guard let preview else { return }
        await self.preview(instruction: preview.instruction)
    }

    @discardableResult
    func apply() -> Bool {
        guard let target, let preview else { return false }
        let result = target.replace(with: preview.transformed)
        if result { wasApplied = true }
        return result
    }

    @discardableResult
    func undo() -> Bool {
        guard let target, preview != nil, wasApplied else { return false }
        let result = target.replace(with: target.originalText)
        if result { dismiss() }
        return result
    }

    func dismiss() {
        target = nil
        preview = nil
        errorMessage = nil
        isWorking = false
        wasApplied = false
    }
}
