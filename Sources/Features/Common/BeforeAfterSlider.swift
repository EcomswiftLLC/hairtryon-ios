import SwiftUI
import UIKit

/// Shows two versions of the same photo with a draggable divider: "before" on the left, "after" on the right.
/// Both images must have the same aspect ratio. The view fits the images inside the space it is given.
struct BeforeAfterSlider: View {
    let before: UIImage
    let after: UIImage
    /// 0...1, where the divider sits (fraction of the image width).
    @Binding var position: Double
    var cornerRadius: CGFloat = 18
    var showsLabels: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(before: UIImage, after: UIImage, position: Binding<Double>, cornerRadius: CGFloat = 18, showsLabels: Bool = true) {
        self.before = before
        self.after = after
        self._position = position
        self.cornerRadius = cornerRadius
        self.showsLabels = showsLabels
    }

    var body: some View {
        GeometryReader { geo in
            let fitted = fittedSize(in: geo.size)
            let x = fitted.width * CGFloat(min(max(position, 0), 1))
            ZStack(alignment: .leading) {
                Image(uiImage: after)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                Image(uiImage: before)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: x, height: fitted.height)
                    }
                // Divider line and handle.
                Rectangle()
                    .fill(LS.Palette.paper)
                    .frame(width: 2, height: fitted.height)
                    .offset(x: x - 1)
                    .shadow(color: .black.opacity(0.35), radius: 3)
                handle
                    .offset(x: x - 22, y: 0)
                if showsLabels {
                    label("Before").padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    label("After").padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(LS.Palette.line, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard fitted.width > 0 else { return }
                        position = Double(min(max(value.location.x / fitted.width, 0), 1))
                    }
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Before and after comparison"))
            .accessibilityValue(Text("\(Int((position * 100).rounded())) percent of the photo shows the original"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: position = min(1, position + 0.1)
                case .decrement: position = max(0, position - 0.1)
                @unknown default: break
                }
            }
        }
    }

    private var handle: some View {
        Circle()
            .fill(LS.Palette.paper)
            .frame(width: 44, height: 44)
            .overlay(
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LS.Palette.onAccent)
            )
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(LS.Font.label)
            .foregroundStyle(LS.Palette.paper)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.black.opacity(0.55), in: Capsule())
            .accessibilityHidden(true)
    }

    private func fittedSize(in container: CGSize) -> CGSize {
        let aspect = after.size.width / max(1, after.size.height)
        guard container.width > 0, container.height > 0, aspect > 0 else { return .zero }
        var w = container.width
        var h = w / aspect
        if h > container.height {
            h = container.height
            w = h * aspect
        }
        return CGSize(width: w, height: h)
    }
}
