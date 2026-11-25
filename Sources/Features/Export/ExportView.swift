import SwiftUI
import UIKit

/// What the editor hands to the export screen.
struct ExportPayload: Identifiable {
    enum Kind { case single, comparison }

    let id = UUID()
    var kind: Kind = .single
    /// Shown on the export screen and used as the saved file name.
    var title: String
    /// The original photo (any size up to about 1600 px) for the before/after slider.
    var before: UIImage
    /// Renders the finished result at full quality. Called once, after the screen opens.
    var makeAfter: () async -> UIImage?
}

/// Placeholder until the real export screen (result, before/after, rewarded ad, save, share) is written.
struct ExportView: View {
    let payload: ExportPayload
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Export").apDisplay()
            Button("Close") { dismiss() }.buttonStyle(.apSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .apScreen()
    }
}
