//
//  ReactionPickerView.swift
//  Listend
//

import SwiftUI

struct ReactionPickerSection: View {
    let prompt: ReactionPrompt
    let suggestions: [ReactionTagDefinition]
    @Binding var selection: ReactionSelectionState
    let showMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.md) {
            Text(prompt.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reactionPromptText")

            if !additionalSelections.isEmpty {
                VStack(alignment: .leading, spacing: ListendSpacing.sm) {
                    Text("Selected")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)

                    ReactionFlowLayout(spacing: ListendSpacing.sm) {
                        ForEach(additionalSelections) { item in
                            ReactionSelectionChip(selection: item) {
                                selection.remove(item)
                            }
                        }
                    }
                }
            }

            ReactionFlowLayout(spacing: ListendSpacing.sm) {
                ForEach(suggestions) { tag in
                    ReactionTagChip(
                        tag: tag,
                        isSelected: selection.isSelected(tag)
                    ) {
                        selection.toggleCanonical(tag)
                    }
                }

                Button(action: showMore) {
                    Label("See all", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, ListendSpacing.sm)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.listendAccent)
                .accessibilityLabel("More reactions")
                .accessibilityHint("Opens all reaction categories and search")
                .accessibilityIdentifier("reactionMoreButton")
            }

            if suggestions.isEmpty {
                Text("Browse More to add a reaction in your own words.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, ListendSpacing.xs)
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

struct ReactionBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding private var selection: ReactionSelectionState
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var resolutionState: ReactionTagResolutionState = .idle
    @State private var resolutionTask: Task<Void, Never>?

    private let catalog: TaxonomyCatalog
    private let searchEngine: ReactionBrowserSearchEngine
    private let rating: Double?
    private let reviewExcerpt: String
    private let semanticResolver: any ReactionTagResolving

    init(
        selection: Binding<ReactionSelectionState>,
        catalog: TaxonomyCatalog = TaxonomyCatalogLoader.shared,
        rating: Double? = nil,
        reviewExcerpt: String = "",
        semanticResolver: any ReactionTagResolving = LocalReactionTagResolutionProvider()
    ) {
        _selection = selection
        self.catalog = catalog
        searchEngine = ReactionBrowserSearchEngine(catalog: catalog)
        self.rating = rating
        self.reviewExcerpt = reviewExcerpt
        self.semanticResolver = semanticResolver
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
            .accessibilityIdentifier("reactionBrowser")
            .navigationTitle("More Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search reactions")
            )
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.listendPaper)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("reactionBrowserDoneButton")
                }
            }
            .onChange(of: searchText) {
                resetResolution()
            }
        }
        .presentationDetents([.large])
        .onDisappear {
            resolutionTask?.cancel()
        }
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
                        HStack(alignment: .firstTextBaseline, spacing: ListendSpacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if item.isCustom {
                                    Text("Custom reaction")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: ListendSpacing.sm)

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.listendAccent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.displayName)
                    .accessibilityValue("Selected")
                    .accessibilityHint("Double tap to deselect")
                    .accessibilityAddTraits(.isSelected)
                    .accessibilityIdentifier(
                        "selectedReaction-\(ReactionAccessibility.identifierComponent(for: item.id))"
                    )
                }
            } header: {
                Text("Selected")
                    .accessibilityAddTraits(.isHeader)
            }
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
                ReactionBrowserTagRow(
                    tag: tag,
                    annotation: nil,
                    isSelected: selection.isSelected(tag),
                    accessibilityIdentifier: "reactionBrowserOption-\(tag.id)"
                ) {
                    selection.toggleCanonical(tag)
                }
            }
        } header: {
            Text(category.displayName)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var searchSections: some View {
        switch searchPresentation.exactMatch {
        case .canonical(let tag):
            Section("Exact match") {
                ReactionBrowserTagRow(
                    tag: tag,
                    annotation: "Canonical reaction",
                    isSelected: selection.isSelected(tag),
                    accessibilityIdentifier: "reactionResult-\(tag.id)"
                ) {
                    selection.toggleCanonical(tag)
                }
            }

        case .alias(let alias, let tag):
            Section("Alias match") {
                ReactionBrowserTagRow(
                    tag: tag,
                    annotation: "“\(alias)” maps to this canonical reaction",
                    isSelected: selection.isSelected(tag),
                    accessibilityIdentifier: "reactionResult-\(tag.id)"
                ) {
                    selection.toggleCanonical(tag)
                }
            }

        case .ambiguous(let alias, let candidates):
            Section {
                Text(alias.prompt)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reactionAmbiguityPrompt")

                ForEach(candidates) { tag in
                    ReactionBrowserTagRow(
                        tag: tag,
                        annotation: "Choice for “\(alias.term)”",
                        isSelected: selection.isSelected(tag),
                        accessibilityIdentifier: "reactionAmbiguityOption-\(tag.id)"
                    ) {
                        selection.toggleCanonical(tag)
                    }
                }
            } header: {
                Text("Choose what you mean")
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("reactionAmbiguityChoices")
            }

        case nil:
            if searchPresentation.results.isEmpty {
                Section {
                    ContentUnavailableView.search(text: TagTextNormalizer.displayValue(searchText))
                }
            } else {
                Section("Results") {
                    ForEach(searchPresentation.results) { result in
                        ReactionBrowserTagRow(
                            tag: result.tag,
                            annotation: annotation(for: result),
                            isSelected: selection.isSelected(result.tag),
                            accessibilityIdentifier: "reactionResult-\(result.tag.id)"
                        ) {
                            selection.toggleCanonical(result.tag)
                        }
                    }
                }
            }
        }

        semanticResolutionSection
        customSection
    }

    @ViewBuilder
    private var semanticResolutionSection: some View {
        if let customDisplayValue = searchPresentation.customDisplayValue,
           ReactionSelectionState.validateCustom(customDisplayValue).displayValue != nil {
            switch resolutionState {
            case .idle:
                if searchPresentation.allowsSemanticLookup {
                    Section {
                        Button {
                            findClosestReaction(for: customDisplayValue)
                        } label: {
                            Label("Find the closest reaction", systemImage: "sparkle.magnifyingglass")
                        }
                        .accessibilityHint("Uses on-device intelligence after you confirm")
                        .accessibilityIdentifier("findClosestReactionButton")
                    } header: {
                        Text("Need help matching it?")
                            .accessibilityAddTraits(.isHeader)
                    }
                }

            case .resolving(let phrase):
                Section {
                    HStack(spacing: ListendSpacing.sm) {
                        ProgressView()
                        Text("Finding the closest reaction to “\(phrase)”…")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("reactionResolutionProgress")
                }

            case .confirmation(let phrase, let options):
                Section {
                    if options.isEmpty {
                        Text("No close match found. You can keep “\(phrase)” in your own words.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("reactionResolutionNoMatch")
                    } else {
                        ForEach(options) { tag in
                            ReactionBrowserTagRow(
                                tag: tag,
                                annotation: "Closest option for “\(phrase)”",
                                isSelected: selection.isSelected(tag),
                                accessibilityIdentifier: "reactionResolutionOption-\(tag.id)"
                            ) {
                                selection.addCanonical(tag)
                                searchText = ""
                                isSearchPresented = false
                            }
                        }
                    }
                } header: {
                    Text(options.count > 1 ? "Choose the closest reaction" : "Closest reaction")
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("reactionResolutionConfirmation")
                }
            }
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
                        isSearchPresented = false
                    } label: {
                        Label("Keep “\(displayValue)” as custom", systemImage: "text.badge.plus")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityLabel("Keep \(displayValue) as a custom reaction")
                    .accessibilityHint("Adds your exact words to the selected reactions")
                    .accessibilityIdentifier("keepCustomReactionButton")
                } else if let message = validation.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("customReactionValidationMessage")
                }
            } header: {
                Text("Your words")
                    .accessibilityAddTraits(.isHeader)
            }
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

    private func findClosestReaction(for phrase: String) {
        resolutionTask?.cancel()
        resolutionState = .resolving(phrase: phrase)

        let comparisonKey = TagTextNormalizer.comparisonKey(phrase)
        let selectedCanonicalIDs = selection.selectedCanonicalIDs
        resolutionTask = Task { @MainActor in
            let resolution = await ReactionTagResolutionState.resolve(
                phrase: phrase,
                rating: rating,
                selectedCanonicalIDs: selectedCanonicalIDs,
                reviewExcerpt: reviewExcerpt,
                catalog: catalog,
                semanticResolver: semanticResolver
            )

            guard !Task.isCancelled,
                  TagTextNormalizer.comparisonKey(searchText) == comparisonKey else {
                return
            }

            resolutionState = .confirmation(
                for: resolution,
                originalPhrase: phrase
            )
            resolutionTask = nil
        }
    }

    private func resetResolution() {
        resolutionTask?.cancel()
        resolutionTask = nil
        resolutionState = .idle
    }
}

private struct ReactionTagChip: View {
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
            .padding(.horizontal, ListendSpacing.md)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? Color.listendPaper : Color.primary)
            .background(
                isSelected ? Color.listendAccent : Color.listendSurface,
                in: RoundedRectangle(cornerRadius: ListendRadius.chip)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ListendRadius.chip)
                    .stroke(isSelected ? Color.clear : Color.listendHairline, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: ListendRadius.chip))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
        .accessibilityIdentifier("reactionChip-\(tag.id)")
        .modifier(ReactionSelectedAccessibilityModifier(isSelected: isSelected))
    }
}

private struct ReactionSelectionChip: View {
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
            .padding(.horizontal, ListendSpacing.md)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .foregroundStyle(Color.listendPaper)
            .background(
                Color.listendAccent,
                in: RoundedRectangle(cornerRadius: ListendRadius.chip)
            )
            .contentShape(RoundedRectangle(cornerRadius: ListendRadius.chip))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selection.displayName)
        .accessibilityValue("Selected")
        .accessibilityHint("Double tap to deselect")
        .accessibilityAddTraits(.isSelected)
        .accessibilityIdentifier(
            "selectedReaction-\(ReactionAccessibility.identifierComponent(for: selection.id))"
        )
    }
}

private struct ReactionBrowserTagRow: View {
    let tag: ReactionTagDefinition
    let annotation: String?
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: ListendSpacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tag.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let annotation {
                        Text(annotation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(tag.definition)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: ListendSpacing.sm)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.listendAccent : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
        .accessibilityIdentifier(accessibilityIdentifier)
        .modifier(ReactionSelectedAccessibilityModifier(isSelected: isSelected))
    }

    private var accessibilityLabel: String {
        guard let annotation else {
            return tag.displayName
        }

        return "\(tag.displayName), \(annotation)"
    }
}

private struct ReactionSelectedAccessibilityModifier: ViewModifier {
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

private enum ReactionAccessibility {
    nonisolated static func identifierComponent(for value: String) -> String {
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
}

private struct ReactionFlowLayout: Layout {
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
                ProposedViewSize(width: maximumWidth.isFinite ? maximumWidth : nil, height: nil)
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
        return CGSize(width: min(totalWidth, maximumWidth), height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: bounds.width, height: nil)
            )

            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
