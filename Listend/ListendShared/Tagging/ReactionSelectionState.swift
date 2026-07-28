//
//  ReactionSelectionState.swift
//  ListendShared
//

import Foundation

nonisolated struct ReactionSelection: Identifiable, Equatable, Hashable, Sendable {
    nonisolated enum Kind: Equatable, Hashable, Sendable {
        case canonical(id: String)
        case custom
    }

    let kind: Kind
    let displayName: String

    var id: String {
        switch kind {
        case .canonical(let id):
            return "canonical-\(id)"
        case .custom:
            return "custom-\(TagTextNormalizer.comparisonKey(displayName))"
        }
    }

    var canonicalID: String? {
        guard case .canonical(let id) = kind else {
            return nil
        }

        return id
    }

    var isCustom: Bool {
        if case .custom = kind {
            return true
        }

        return false
    }

    static func canonical(_ tag: ReactionTagDefinition) -> ReactionSelection {
        ReactionSelection(kind: .canonical(id: tag.id), displayName: tag.displayName)
    }

    static func custom(_ displayName: String) -> ReactionSelection {
        ReactionSelection(kind: .custom, displayName: displayName)
    }
}

nonisolated enum ReactionCustomValueValidation: Equatable, Sendable {
    case valid(displayValue: String)
    case empty
    case tooLong(maximum: Int)
    case containsSeparator
    case missingLetters

    var displayValue: String? {
        guard case .valid(let displayValue) = self else {
            return nil
        }

        return displayValue
    }

    var message: String? {
        switch self {
        case .valid:
            return nil
        case .empty:
            return "Enter a reaction to keep it in your own words."
        case .tooLong(let maximum):
            return "Keep custom reactions to \(maximum) characters."
        case .containsSeparator:
            return "Custom reactions cannot contain commas or line breaks."
        case .missingLetters:
            return "Custom reactions need at least one letter."
        }
    }
}

nonisolated struct ReactionSelectionState: Equatable, Sendable {
    static let maximumCustomDisplayLength = 28

    private(set) var selections: [ReactionSelection]

    init(selections: [ReactionSelection] = []) {
        self.selections = []
        for selection in selections {
            appendIfUnique(selection)
        }
    }

    init(persistedDisplayValues: [String], catalog: TaxonomyCatalog) {
        let resolver = LocalReactionTagResolver(catalog: catalog)
        self.selections = []

        for value in persistedDisplayValues {
            if let canonical = resolver.canonicalTag(forPersistedDisplayValue: value) {
                appendIfUnique(.canonical(canonical))
            } else {
                let displayValue = TagTextNormalizer.displayValue(value)
                guard !displayValue.isEmpty else {
                    continue
                }
                appendIfUnique(.custom(displayValue))
            }
        }
    }

    var persistedDisplayValues: [String] {
        selections.map(\.displayName)
    }

    var selectedCanonicalDisplayValues: [String] {
        selections.compactMap { selection in
            selection.canonicalID == nil ? nil : selection.displayName
        }
    }

    var customDisplayValues: [String] {
        selections.compactMap { selection in
            selection.isCustom ? selection.displayName : nil
        }
    }

    var selectedCanonicalIDs: Set<String> {
        Set(selections.compactMap(\.canonicalID))
    }

    func isSelected(_ tag: ReactionTagDefinition) -> Bool {
        selections.contains { $0.canonicalID == tag.id }
    }

    func contains(_ selection: ReactionSelection) -> Bool {
        selections.contains { $0.id == selection.id }
    }

    mutating func toggleCanonical(_ tag: ReactionTagDefinition) {
        if let index = selections.firstIndex(where: { $0.canonicalID == tag.id }) {
            selections.remove(at: index)
            return
        }

        addCanonical(tag)
    }

    mutating func addCanonical(_ tag: ReactionTagDefinition) {
        let selection = ReactionSelection.canonical(tag)
        let comparisonKey = TagTextNormalizer.comparisonKey(selection.displayName)

        if let matchingIndex = selections.firstIndex(where: {
            TagTextNormalizer.comparisonKey($0.displayName) == comparisonKey
        }) {
            selections[matchingIndex] = selection
            return
        }

        selections.append(selection)
    }

    @discardableResult
    mutating func addCustom(_ value: String) -> ReactionCustomValueValidation {
        let validation = Self.validateCustom(value)
        guard let displayValue = validation.displayValue else {
            return validation
        }

        appendIfUnique(.custom(displayValue))
        return validation
    }

    mutating func remove(_ selection: ReactionSelection) {
        selections.removeAll { $0.id == selection.id }
    }

    static func validateCustom(_ value: String) -> ReactionCustomValueValidation {
        let displayValue = TagTextNormalizer.displayValue(value)

        guard !displayValue.isEmpty else {
            return .empty
        }

        guard displayValue.count <= maximumCustomDisplayLength else {
            return .tooLong(maximum: maximumCustomDisplayLength)
        }

        guard !displayValue.contains(","), !displayValue.contains("\n") else {
            return .containsSeparator
        }

        guard displayValue.rangeOfCharacter(from: .letters) != nil else {
            return .missingLetters
        }

        return .valid(displayValue: displayValue)
    }

    private mutating func appendIfUnique(_ selection: ReactionSelection) {
        let key = TagTextNormalizer.comparisonKey(selection.displayName)
        guard !selections.contains(where: {
            TagTextNormalizer.comparisonKey($0.displayName) == key
        }) else {
            return
        }

        selections.append(selection)
    }
}
