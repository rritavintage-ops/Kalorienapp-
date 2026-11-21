import SwiftData
import SwiftUI
import UIKit

struct ScanFlowView: View {
    let image: UIImage
    let day: Date
    var onSaved: () -> Void = {}

    @Environment(\.mealScanner) private var scanner
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model: ScanFlowModel
    @State private var editingDraft: FoodDraft?

    init(image: UIImage, initialMeal: MealType, day: Date, onSaved: @escaping () -> Void = {}) {
        self.image = image
        self.day = day
        self.onSaved = onSaved
        _model = State(initialValue: ScanFlowModel(mealType: initialMeal))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .analyzing:
                    AnalyzingView(image: image)
                case .review:
                    ScanReviewView(model: model, image: image, editingDraft: $editingDraft, onSave: save)
                case .notFood(let message):
                    ScanMessageView(
                        image: image,
                        symbol: "questionmark.circle",
                        title: "No food found",
                        message: message ?? String(localized: "We couldn't spot any food in this photo. Try again with the whole plate in view, or add it manually."),
                        retry: { Task { await analyze() } },
                        manual: { startManual() }
                    )
                case .failed(let message):
                    ScanMessageView(
                        image: image,
                        symbol: "exclamationmark.triangle",
                        title: "Analysis failed",
                        message: message,
                        retry: { Task { await analyze() } },
                        manual: { startManual() }
                    )
                }
            }
            .animation(.snappy, value: model.phase)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .background(Theme.background)
        }
        .task {
            await analyze()
        }
        .sheet(item: $editingDraft) { draft in
            DraftEditorSheet(draft: draft) { updated in
                model.upsert(updated)
            }
        }
        .interactiveDismissDisabled(model.phase == .review && !model.drafts.isEmpty)
    }

    private var navigationTitle: LocalizedStringKey {
        switch model.phase {
        case .analyzing: return "Analyzing"
        case .review: return "Review meal"
        case .notFood, .failed: return "Scan"
        }
    }

    private func analyze() async {
        await model.analyze(image: image, scanner: scanner)
    }

    private func startManual() {
        model.startManualReview()
        editingDraft = FoodDraft.empty()
    }

    private func save() {
        let date = LogDate.entryDate(forDay: day)
        let thumbnail = ImageProcessor.thumbnailJPEG(from: image)
        for draft in model.drafts where draft.isValid {
            modelContext.insert(FoodEntry(draft: draft, mealType: model.mealType, date: date, source: .scan, photoData: thumbnail))
        }
        try? modelContext.save()
        onSaved()
        dismiss()
    }
}

// MARK: - Analyzing

private struct AnalyzingView: View {
    let image: UIImage
    @State private var sweep = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [Theme.accent.opacity(0), Theme.accent.opacity(0.55), Theme.accent.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 90)
                        .offset(y: sweep ? proxy.size.height - 45 : -45)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                }
                .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Analyzing your meal…")
                        .font(.title3.weight(.semibold))
                }
                Text("Identifying foods and estimating portions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("scan.analyzing")
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
    }
}

// MARK: - Review

private struct ScanReviewView: View {
    @Bindable var model: ScanFlowModel
    let image: UIImage
    @Binding var editingDraft: FoodDraft?
    let onSave: () -> Void

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.mealName ?? String(localized: "Your meal"))
                            .font(.headline)
                            .lineLimit(2)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Format.kcal(model.totals.calories))
                                .font(.system(.title, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: model.totals.calories))
                                .accessibilityIdentifier("scan.totalCalories")
                            Text("kcal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .animation(.snappy, value: model.totals.calories)
                        MacroSummaryText(nutrients: model.totals)
                    }
                }
                .padding(.vertical, 4)

                MealPicker(selection: $model.mealType)
            }

            Section {
                ForEach(model.drafts) { draft in
                    Button {
                        editingDraft = draft
                    } label: {
                        DraftRow(draft: draft)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scan.item.\(draft.trimmedName)")
                    .swipeActions {
                        Button(role: .destructive) {
                            withAnimation { model.remove(draft) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                Button {
                    editingDraft = FoodDraft.empty()
                } label: {
                    Label("Add item", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityIdentifier("scan.addItem")
            } header: {
                Text("Detected foods")
            } footer: {
                Text(footerText)
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Button(action: onSave) {
                Text("Add to \(model.mealType.name)")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canSave)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
            .accessibilityIdentifier("scan.save")
        }
    }

    private var footerText: String {
        var parts: [String] = []
        if let notes = model.notes, !notes.isEmpty {
            parts.append(notes)
        }
        parts.append(String(localized: "AI estimates can be off. Tap an item to correct the food or portion."))
        return parts.joined(separator: "\n\n")
    }
}

private struct DraftRow: View {
    let draft: FoodDraft

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(draft.trimmedName.isEmpty ? String(localized: "Unnamed food") : draft.trimmedName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if let confidence = draft.confidence, confidence == .low {
                        Text("Unsure")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.over.opacity(0.15)))
                            .foregroundStyle(Theme.over)
                    }
                }
                HStack(spacing: 6) {
                    Text(portionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MacroSummaryText(nutrients: draft.totals)
                }
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Format.kcal(draft.totals.calories))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text("kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var portionText: String {
        let grams = "\(Format.grams(draft.grams)) g"
        if let portion = draft.portionDescription {
            return "\(portion) · \(grams)"
        }
        return grams
    }
}

/// Edits one scanned item in its own sheet.
private struct DraftEditorSheet: View {
    @State private var draft: FoodDraft
    let onSave: (FoodDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    init(draft: FoodDraft, onSave: @escaping (FoodDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            FoodDraftForm(draft: $draft)
                .navigationTitle(draft.trimmedName.isEmpty ? "Add item" : "Edit item")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onSave(draft)
                            dismiss()
                        }
                        .disabled(!draft.isValid)
                        .accessibilityIdentifier("editor.save")
                    }
                }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Errors

private struct ScanMessageView: View {
    let image: UIImage
    let symbol: String
    let title: LocalizedStringKey
    let message: String
    let retry: () -> Void
    let manual: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .opacity(0.85)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityIdentifier("scan.message")
            VStack(spacing: 12) {
                Button("Try again", action: retry)
                    .buttonStyle(PrimaryButtonStyle())
                Button("Add manually", action: manual)
                    .font(.headline)
                    .accessibilityIdentifier("scan.manual")
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
