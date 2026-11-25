import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var ads = AdsManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LS.Space.l) {
                    LSHeader(title: "Settings", subtitle: "Lustra is free. Your photos are processed on this device and never uploaded.")

                    section("Privacy") {
                        if ads.privacyOptionsRequired {
                            row("Ad privacy choices", symbol: "hand.raised") { ads.presentPrivacyOptions() }
                            LSHairline()
                        }
                        link("Privacy policy", symbol: "lock", url: AppLinks.privacyURL)
                        LSHairline()
                        link("Terms of use", symbol: "doc.text", url: AppLinks.termsURL)
                    }

                    section("Help") {
                        link("Support", symbol: "questionmark.circle", url: AppLinks.supportURL)
                        LSHairline()
                        link("Email us", symbol: "envelope", url: AppLinks.mailURL)
                        if let review = AppLinks.writeReviewURL {
                            LSHairline()
                            row("Rate Lustra", symbol: "star") { openURL(review) }
                                .accessibilityIdentifier("settings.rate")
                        }
                    }

                    section("About") {
                        NavigationLink {
                            LicensesView()
                        } label: {
                            LSRow(title: "Open-source licenses", symbol: "text.book.closed")
                        }
                        .accessibilityIdentifier("settings.licences")
                        LSHairline()
                        LSRow(title: "Version", symbol: "info.circle", value: version, showsChevron: false)
                            .accessibilityElement(children: .combine)
                        LSHairline()
                        Text("Hair is found by a model that runs on your device. Photos and saved looks stay on this device. Ads are shown on the Home screen, and one short ad before you save or share.")
                            .font(LS.Font.caption)
                            .foregroundStyle(LS.Palette.mist)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, LS.Space.s)
                    }
                }
                .padding(.horizontal, LS.Space.m)
                .padding(.bottom, LS.Space.xl)
                .readableWidth()
            }
            .apScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(LS.Palette.accent)
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LS.Space.s) {
            LSSectionTitle(text: title)
            VStack(spacing: 0) {
                LSHairline()
                content()
                LSHairline()
            }
        }
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { LSRow(title: title, symbol: symbol) }
            .buttonStyle(.plain)
    }

    private func link(_ title: String, symbol: String, url: URL) -> some View {
        Link(destination: url) { LSRow(title: title, symbol: symbol) }
    }
}

/// The licence notices for everything Lustra is built on, plus the sample photo credits.
struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LS.Space.l) {
                LSHeader(title: "Open-source licenses", subtitle: "Lustra uses the work of others. Thank you.", size: 30)

                notice(
                    title: "Hair detection model",
                    body: "The model that finds hair in your photo is based on the MediaPipe hair segmenter by Google LLC, licensed under the Apache License 2.0, converted to Core ML. It runs on your device.\n\nhttps://ai.google.dev/edge/mediapipe/solutions/vision/image_segmenter"
                )
                notice(
                    title: "Google Mobile Ads SDK and User Messaging Platform",
                    body: "Lustra shows ads with Google's Mobile Ads SDK and asks for your consent with Google's User Messaging Platform. Both are \u{00A9} Google LLC and used under Google's terms."
                )
                if let text = LicenseText.apache {
                    notice(title: "Apache License 2.0", body: text, monospaced: true)
                }
                let credits = SampleLibrary.credits()
                if !credits.isEmpty {
                    notice(
                        title: "Sample photo credits",
                        body: "The sample photos come from Pexels and are used under the Pexels License.\n\n" + credits.joined(separator: "\n")
                    )
                }
            }
            .padding(.horizontal, LS.Space.m)
            .padding(.bottom, LS.Space.xl)
            .readableWidth()
        }
        .apScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func notice(title: String, body: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: LS.Space.s) {
            LSSectionTitle(text: title)
            Text(body)
                .font(monospaced ? .system(.caption2, design: .monospaced) : LS.Font.callout)
                .foregroundStyle(LS.Palette.mist)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

enum LicenseText {
    /// The Apache 2.0 text shipped in the app bundle (Sources/Resources/Licenses/Apache-2.0.txt).
    static var apache: String? {
        guard let url = Bundle.main.url(forResource: "Apache-2.0", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
    }
}
