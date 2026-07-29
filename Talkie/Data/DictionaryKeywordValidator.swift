import Foundation

enum DictionaryKeywordValidationError: LocalizedError, Equatable {
    case forbiddenCharacter

    var errorDescription: String? {
        "Keywords cannot contain <, >, or line breaks."
    }
}

enum DictionaryKeywordValidator {
    static func validate(_ value: String) throws {
        guard !value.contains("<"),
              !value.contains(">"),
              !value.contains("\r"),
              !value.contains("\n") else {
            throw DictionaryKeywordValidationError.forbiddenCharacter
        }
    }
}
