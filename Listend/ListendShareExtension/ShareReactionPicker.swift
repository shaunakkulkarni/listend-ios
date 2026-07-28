//
//  ShareReactionPicker.swift
//  ListendShareExtension
//

import SwiftUI

struct ShareReactionPickerSection: View {
    let prompt: ReactionPrompt
    let suggestions: [ReactionTagDefinition]
    @Binding var selection: ReactionSelectionState
    let showMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shareReactionPrompt")

            if !additionalSelections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)

                    ShareReactionFlowLayout(spacing: 8) {
                        ForEach(additionalSelections) { item in
                            ShareReactionSelectionChip(selection: item) {
                                selection.remove(item)
                            }
                        }
                    }
                }
            }

            ShareReactionFlowLayout(spacing: 8) {
                ForEach(suggestions) { tag in
                    ShareReactionTagChip(
                        tag: tag,
                        isSelected: selection.isSelected(tag)
                    ) {
                        selection.toggleCanonical(tag)
                    }
                }

                Button(action: showMore) {
                    Label("More", systemImage: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(
                            SharePalette.surface,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(SharePalette.hairline, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(SharePalette.accent)
                .accessibilityLabel("More reactions")
                .accessibilityHint("Opens all reaction categories and search")
                .accessibilityIdentifier("shareReactionMoreButton")
            }
        }
        .padding(.vertical, 4)
    }

    private var additionalSelections: [ReactionSelection] {
        let suggestionIDs = Set(suggestions.map(\.id))
        return selection.selections.filter { item in
            guard let canonicalID = item.canonicalID else {
                return true
            }

            return !suggestionIDs.contains(canonicalID)
        }
    }
}

struct ShareReactionBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var selection: ReactionSelectionState
    @State private var searchText = ""

    private let catalog: TaxonomyCatalog
    private let searchEngine: ReactionBrowserSearchEngine

    init(
        selection: Binding<ReactionSelectionState>,
        catalog: TaxonomyCatalog = TaxonomyCatalogLoader.shared
    ) {
        _selection = selection
        self.catalog = catalog
        searchEngine = ReactionBrowserSearchEngine(catalog: catalog)
    }

    var body: some View {
        NavigationStack {
            List {
                selectedSection

                if searchPresentation.isBrowsing {
                    categorySections
                } else {
                    searchSections
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(SharePalette.paper)
            .foregroundStyle(SharePalette.ink)
            .tint(SharePalette.accent)
            .navigationTitle("More Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search reactions")
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("shareReactionBrowserDoneButton")
                }
            }
            .accessibilityIdentifier("shareReactionBrowser")
        }
        .presentationDetents([.large])
    }

    private var searchPresentation: ReactionBrowserSearchPresentation {
        searchEngine.presentation(for: searchText)
    }

    @ViewBuilder
    private var selectedSection: some View {
        if !selection.selections.isEmpty {
            Section {
                ForEach(selection.selections) { item in
                    Button {
                        selection.remove(item)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .foregroundStyle(SharePalette.ink)
                                    .fixedSize(horizontal: false, vertical: true)

                                if item.isCustom {
                                    Text("Custom reaction")
                                        .font(.caption)
                                        .foregroundStyle(SharePalette.mutedInk)
                                }
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(SharePalette.accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.displayName)
                    .accessibilityValue("Selected")
                    .accessibilityHint("Double tap to deselect")
                    .accessibilityAddTraits(.isSelected)
                    .accessibilityIdentifier(
                        "shareSelectedReaction-\(shareReactionIdentifier(item.id))"
                    )
                }
            } header: {
                Text("Selected")
                    .accessibilityAddTraits(.isHeader)
            }
            .listRowBackground(SharePalette.paper)
        }
    }

    @ViewBuilder
    private var categorySections: some View {
        if catalog.reactions.tags.isEmpty {
            Section {
                ContentUnavailableView(
                    "Reactions Unavailable",
                    systemImage: "tag",
                    description: Text("Search to keep a reaction in your own words.")
                )
            }
            .listRowBackground(SharePalette.paper)
        } else {
            ForEach(catalog.reactions.categories) { category in
                categorySection(category)
            }
        }
    }

    private func categorySection(_ category: ReactionTagCategoryDefinition) -> some View {
        let tags = catalog.reactions.tags.filter { $0.category == category.id }

        return Section {
            ForEach(tags) { tag in
                ShareReactionBrowserRow(
                    tag: tag,
                    annotation: nil,
                    isSelected: selection.isSelected(tag),
                    accessibilityIdentifier: "shareReactionOption-\(tag.id)"
                ) {
                    selection.toggleCanonical(tag)
                }
            }
        } header: {
            Text(category.displayName)
                .accessibilityAddTraits(.isHeader)
        }
        .listRowBackground(SharePalette.paper)
    }

    @ViewBuilder
    private var searchSections: some View {
        switch searchPresentation.exactMatch {
        case .canonical(let tag):
            Section("Exact match") {
                reactionRow(tag, annotation: "Canonical reaction")
            }
            .listRowBackground(SharePalette.paper)

        case .alias(let alias, let tag):
            Section("Alias match") {
                reactionRow(tag, annotation: "“\(alias)” maps to this canonical reaction")
            }
            .listRowBackground(SharePalette.paper)

        case .ambiguous(let alias, let candidates):
            Section {
                Text(alias.prompt)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shareReactionAmbiguityPrompt")

                ForEach(candidates) { tag in
                    ShareReactionBrowserRow(
                        tag: tag,
                        annotation: "Choice for “\(alias.term)”",
                        isSelected: selection.isSelected(tag),
                        accessibilityIdentifier: "shareReactionAmbiguityOption-\(tag.id)"
                    ) {
                        selection.toggleCanonical(tag)
                    }
                }
            } header: {
                Text("Choose what you mean")
                    .accessibilityAddTraits(.isHeader)
            }
            .listRowBackground(SharePalette.paper)

        case nil:
            if searchPresentation.results.isEmpty {
                Section {
                    ContentUnavailableView.search(
                        text: TagTextNormalizer.displayValue(searchText)
                    )
                }
                .listRowBackground(SharePalette.paper)
            } else {
                Section("Results") {
                    ForEach(searchPresentation.results) { result in
                        reactionRow(
                            result.tag,
                            annotation: annotation(for: result)
                        )
                    }
                }
                .listRowBackground(SharePalette.paper)
            }
        }

        customSection
    }

    private func reactionRow(
        _ tag: ReactionTagDefinition,
        annotation: String
    ) -> some View {
        ShareReactionBrowserRow(
            tag: tag,
            annotation: annotation,
            isSelected: selection.isSelected(tag),
            accessibilityIdentifier: "shareReactionResult-\(tag.id)"
        ) {
            selection.toggleCanonical(tag)
        }
    }

    @ViewBuilder
    private var customSection: some View {
        if let customDisplayValue = searchPresentation.customDisplayValue {
            let validation = ReactionSelectionState.validateCustom(customDisplayValue)

            Section {
                if let displayValue = validation.displayValue {
                    Button {
                        selection.addCustom(displayValue)
                        searchText = ""
                    } label: {
                        Label(
                            "Keep “\(displayValue)” as custom",
                            systemImage: "text.badge.plus"
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityLabel("Keep \(displayValue) as a custom reaction")
                    .accessibilityHint("Adds your exact words to the selected reactions")
                    .accessibilityIdentifier("shareKeepCustomReactionButton")
                } else if let message = validation.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(SharePalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("shareCustomReactionValidationMessage")
                }
            } header: {
                Text("Your words")
                    .accessibilityAddTraits(.isHeader)
            }
            .listRowBackground(SharePalette.paper)
        }
    }

    private func annotation(for result: ReactionTagSearchResult) -> String {
        switch result.matchKind {
        case .displayName:
            return result.matchedText == result.tag.displayName
                ? "Canonical name"
                : "Matched canonical name"
        case .alias:
            return "Matched alias “\(result.matchedText)”"
        case .category:
            return "In \(result.matchedText)"
        case .definition:
            return "Related reaction"
        case .typo:
            return "Closest local match to “\(result.matchedText)”"
        }
    }
}

private struct ShareReactionTagChip: View {
    let tag: ReactionTagDefinition
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }

                Text(tag.displayName)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? SharePalette.accent : SharePalette.ink)
            .background(
                isSelected ? SharePalette.accent.opacity(0.14) : SharePalette.surface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.clear : SharePalette.hairline, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
        .accessibilityIdentifier("shareReactionChip-\(tag.id)")
        .modifier(ShareReactionSelectedAccessibilityModifier(isSelected: isSelected))
    }
}

private struct ShareReactionSelectionChip: View {
    let selection: ReactionSelection
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))

                Text(selection.displayName)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .foregroundStyle(SharePalette.accent)
            .background(
                SharePalette.accent.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selection.displayName)
        .accessibilityValue("Selected")
        .accessibilityHint("Double tap to deselect")
        .accessibilityAddTraits(.isSelected)
        .accessibilityIdentifier(
            "shareSelectedReaction-\(shareReactionIdentifier(selection.id))"
        )
    }
}

private struct ShareReactionBrowserRow: View {
    let tag: ReactionTagDefinition
    let annotation: String?
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tag.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(SharePalette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(annotation ?? tag.definition)
                        .font(.caption)
                        .foregroundStyle(SharePalette.mutedInk)
                        .lineLimit(annotation == nil ? 3 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? SharePalette.accent : SharePalette.mutedInk)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
        .accessibilityIdentifier(accessibilityIdentifier)
        .modifier(ShareReactionSelectedAccessibilityModifier(isSelected: isSelected))
    }

    private var accessibilityLabel: String {
        guard let annotation else {
            return tag.displayName
        }

        return "\(tag.displayName), \(annotation)"
    }
}

private struct ShareReactionSelectedAccessibilityModifier: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.accessibilityAddTraits(.isSelected)
        } else {
            content
        }
    }
}

private func shareReactionIdentifier(_ value: String) -> String {
    TagTextNormalizer.comparisonKey(value)
        .map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        .reduce(into: "") { result, character in
            if character != "-" || result.last != "-" {
                result.append(character)
            }
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

private struct ShareReactionFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maximumWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(
                ProposedViewSize(
                    width: maximumWidth.isFinite ? maximumWidth : nil,
                    height: nil
                )
            )

            if rowWidth > 0, rowWidth + spacing + size.width > maximumWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: bounds.width, height: nil)
            )

            if origin.x > bounds.minX,
               origin.x + size.width > bounds.maxX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: origin,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
