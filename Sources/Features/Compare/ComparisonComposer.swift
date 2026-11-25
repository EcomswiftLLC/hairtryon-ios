import UIKit

/// Builds the shareable colour grid: the original plus eleven colours of this photo, with the colour names under the tiles.
enum ComparisonComposer {
    /// The colours in the exported grid, in reading order after the original.
    static let names: [String] = [
        "Soft black", "Chestnut", "Auburn", "Copper", "Honey", "Golden blonde",
        "Platinum", "Rose gold", "Blush pink", "Lavender", "Midnight blue",
    ]

    static let canvasSize = CGSize(width: 1600, height: 2000)
    static let columns = 4
    static let rows = 3

    /// Renders every tile at preview size on a background queue and composes the grid.
    static func render(session: HairSession, look: HairLook, strokes: [BrushStroke]) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: composeBlocking(session: session, look: look, strokes: strokes))
            }
        }
    }

    static func composeBlocking(session: HairSession, look: HairLook, strokes: [BrushStroke]) -> UIImage? {
        let ctx = session.context(.preview, strokes: strokes)
        var tiles: [(title: String, image: UIImage)] = []
        let original = RGBAImage(width: ctx.width, height: ctx.height, pixels: ctx.planes.rgba)
        if let img = EditorTileCrop.tileImage(from: original, stats: ctx.stats) {
            tiles.append((title: "Original", image: img))
        }
        for name in names {
            guard let shade = HairPalette.shade(named: name) else { continue }
            var l = look
            l.primary = shade.color
            let rendered: RGBAImage = ctx.render(l)
            if let img = EditorTileCrop.tileImage(from: rendered, stats: ctx.stats) {
                tiles.append((title: name, image: img))
            }
        }
        return compose(tiles: tiles)
    }

    private static func serifFont(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    /// Lays the tiles out on a 4:5 dark canvas, four columns by three rows.
    static func compose(tiles: [(title: String, image: UIImage)]) -> UIImage? {
        let size = canvasSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let margin: CGFloat = 72
        let gap: CGFloat = 28
        let headerHeight: CGFloat = 170
        let footerHeight: CGFloat = 120
        let labelHeight: CGFloat = 64
        let cols = CGFloat(columns)
        let rowCount = CGFloat(rows)
        let tileW = (size.width - margin * 2 - gap * (cols - 1)) / cols
        let availableH = size.height - headerHeight - footerHeight - margin
        let tileH = tileW / EditorTileCrop.aspect
        let gridH = rowCount * (tileH + labelHeight) + (rowCount - 1) * gap
        let gridTop = headerHeight + max(0, (availableH - gridH) / 2)

        let paper = UIColor(hex: 0xF3EEE8)
        let mist = UIColor(hex: 0xAFA8B3)
        let accent = UIColor(hex: 0xEDB7A2)

        let centred = NSMutableParagraphStyle()
        centred.alignment = .center

        return renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor(hex: 0x0C0A0F).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // A soft rose glow behind the header.
            let colors = [UIColor(hex: 0xEDB7A2, alpha: 0.16).cgColor, UIColor(hex: 0xEDB7A2, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: size.width / 2, y: 0), startRadius: 0,
                    endCenter: CGPoint(x: size.width / 2, y: 0), endRadius: 900,
                    options: []
                )
            }

            let title = "Which shade suits you?" as NSString
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: serifFont(60, weight: .regular),
                .foregroundColor: paper,
                .paragraphStyle: centred,
                .kern: -0.6,
            ]
            title.draw(in: CGRect(x: margin, y: 64, width: size.width - margin * 2, height: 80), withAttributes: titleAttributes)

            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .medium),
                .foregroundColor: paper,
                .paragraphStyle: centred,
            ]
            let originalLabelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .medium),
                .foregroundColor: mist,
                .paragraphStyle: centred,
            ]

            for (index, tile) in tiles.enumerated() {
                if index >= columns * rows { break }
                let col = CGFloat(index % columns)
                let row = CGFloat(index / columns)
                let x = margin + col * (tileW + gap)
                let y = gridTop + row * (tileH + labelHeight + gap)
                let rect = CGRect(x: x, y: y, width: tileW, height: tileH)
                cg.saveGState()
                UIBezierPath(roundedRect: rect, cornerRadius: 26).addClip()
                tile.image.draw(in: rect)
                cg.restoreGState()
                let border = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 26)
                UIColor.white.withAlphaComponent(0.12).setStroke()
                border.lineWidth = 1
                border.stroke()
                let text = tile.title as NSString
                text.draw(
                    in: CGRect(x: x - 8, y: y + tileH + 14, width: tileW + 16, height: labelHeight - 14),
                    withAttributes: index == 0 ? originalLabelAttributes : labelAttributes
                )
            }

            // Footer: a short rule and the name.
            let footerY = size.height - footerHeight + 28
            accent.withAlphaComponent(0.6).setFill()
            cg.fill(CGRect(x: size.width / 2 - 24, y: footerY, width: 48, height: 2))
            let footer = "Lustra" as NSString
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: serifFont(36, weight: .regular),
                .foregroundColor: mist,
                .paragraphStyle: centred,
                .kern: 4.0,
            ]
            footer.draw(in: CGRect(x: margin, y: footerY + 22, width: size.width - margin * 2, height: 50), withAttributes: footerAttributes)
        }
    }
}
