import RemoteKit
import SwiftUI

/// After every take: what was recorded, and the three answers. Keep is the
/// default (recording again keeps the take too), so it is the quiet word in
/// the corner. Delete is one tap, with Undo after it.
struct TakeCard: View {
    @Bindable var model: AppModel
    let take: Take

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(take.name)
                        .font(.headline)
                        .foregroundStyle(Studio.text1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Format.length(take.lengthSeconds)) from bar \(take.start.bar)")
                        .font(.subheadline)
                        .foregroundStyle(Studio.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("take-detail")
                }
                Spacer()
                Button("Keep") { model.keep() }
                    .buttonStyle(.studioQuiet)
                    .accessibilityHint("Keeps the take and closes this.")
                    .accessibilityIdentifier("keep")
            }
            HStack(spacing: 10) {
                Button { model.delete(take) } label: {
                    Text("Delete").frame(maxWidth: .infinity)
                }
                .buttonStyle(StudioButtonStyle(kind: .destructive, minHeight: 50))
                .accessibilityLabel("Delete \(take.name)")
                .accessibilityHint("You can undo it for five seconds.")
                .accessibilityIdentifier("delete")

                Button { model.goAgain() } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Studio.record).frame(width: 11, height: 11)
                        Text("Go again")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(StudioButtonStyle(minHeight: 50))
                .accessibilityLabel("Go again")
                .accessibilityHint("Records again from bar \(take.start.bar).")
                .accessibilityIdentifier("card-go-again")
            }
        }
        .padding(16)
        .studioCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("take-card")
    }
}

/// Undo after a delete, for five seconds.
struct UndoBanner: View {
    @Bindable var model: AppModel
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.body)
                .foregroundStyle(Studio.text1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Undo") { model.undoDiscard() }
                .buttonStyle(.studio)
                .accessibilityIdentifier("undo-delete")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .studioCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undo-banner")
    }
}

/// What the computer refused, in its words, until dismissed or the next success.
struct ProblemBanner: View {
    @Bindable var model: AppModel
    let text: String

    var body: some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Studio.text1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("problem")
            Spacer()
            Button("OK") { model.clearProblem() }
                .buttonStyle(.studioQuiet)
                .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .studioCard()
        .accessibilityElement(children: .contain)
    }
}
