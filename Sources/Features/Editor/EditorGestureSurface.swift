import SwiftUI
import UIKit

enum EditorBrushPhase { case began, moved, ended, cancelled }

/// An invisible layer under the photo that reads the touches:
/// - pinch to zoom (1x to 4x) and move while pinching,
/// - drag to move the photo when it is zoomed in (two fingers while the brush is on),
/// - double tap to zoom in or back out,
/// - with the brush on, one finger paints: the points arrive as fractions of the photo (origin top left).
struct EditorGestureSurface: UIViewRepresentable {
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize
    /// The photo's rectangle at zoom 1, in this view's coordinates.
    var fitted: CGRect
    var brushMode: Bool
    var onBrush: (EditorBrushPhase, CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let c = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        pinch.delegate = c
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        pan.delegate = c
        let brush = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.brush(_:)))
        brush.minimumNumberOfTouches = 1
        brush.maximumNumberOfTouches = 1
        brush.delegate = c
        let dot = UITapGestureRecognizer(target: c, action: #selector(Coordinator.dot(_:)))
        dot.delegate = c
        let twice = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap(_:)))
        twice.numberOfTapsRequired = 2
        twice.delegate = c

        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(brush)
        view.addGestureRecognizer(dot)
        view.addGestureRecognizer(twice)
        c.pinchRecognizer = pinch
        c.panRecognizer = pan
        c.brushRecognizer = brush
        c.dotRecognizer = dot
        c.doubleRecognizer = twice
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let c = context.coordinator
        c.parent = self
        c.brushRecognizer?.isEnabled = brushMode
        c.dotRecognizer?.isEnabled = brushMode
        c.doubleRecognizer?.isEnabled = !brushMode
        c.panRecognizer?.minimumNumberOfTouches = brushMode ? 2 : 1
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: EditorGestureSurface
        var pinchRecognizer: UIPinchGestureRecognizer?
        var panRecognizer: UIPanGestureRecognizer?
        var brushRecognizer: UIPanGestureRecognizer?
        var dotRecognizer: UITapGestureRecognizer?
        var doubleRecognizer: UITapGestureRecognizer?

        private var pinching = false
        private var startZoom: CGFloat = 1
        /// The point of the photo (at zoom 1) that was under the fingers when the pinch started.
        private var anchorPoint: CGPoint = .zero

        init(_ parent: EditorGestureSurface) {
            self.parent = parent
        }

        // MARK: Geometry

        private func clampAxis(_ o: CGFloat, lo: CGFloat, hi: CGFloat, c: CGFloat, s: CGFloat, z: CGFloat) -> CGFloat {
            let left0 = c + (lo - c) * z
            let right0 = c + (hi - c) * z
            if right0 - left0 <= s {
                return s / 2 - (left0 + right0) / 2
            }
            let maxO = -left0
            let minO = s - right0
            return min(maxO, max(minO, o))
        }

        private func clamp(_ o: CGSize, zoom z: CGFloat, size: CGSize) -> CGSize {
            let r = parent.fitted
            let cx = size.width / 2, cy = size.height / 2
            let x = clampAxis(o.width, lo: r.minX, hi: r.maxX, c: cx, s: size.width, z: z)
            let y = clampAxis(o.height, lo: r.minY, hi: r.maxY, c: cy, s: size.height, z: z)
            return CGSize(width: x, height: y)
        }

        private func fraction(of v: CGPoint, in view: UIView) -> CGPoint {
            let s = view.bounds.size
            let z = max(0.01, parent.zoom)
            let o = parent.offset
            let px = s.width / 2 + (v.x - s.width / 2 - o.width) / z
            let py = s.height / 2 + (v.y - s.height / 2 - o.height) / z
            let r = parent.fitted
            return CGPoint(x: (px - r.minX) / max(1, r.width), y: (py - r.minY) / max(1, r.height))
        }

        private func setTransform(zoom: CGFloat, offset: CGSize, animated: Bool) {
            let apply = {
                self.parent.zoom = zoom
                self.parent.offset = offset
            }
            if animated && !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeOut(duration: 0.2)) { apply() }
            } else {
                apply()
            }
        }

        // MARK: Gestures

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard let view = g.view else { return }
            let size = view.bounds.size
            switch g.state {
            case .began:
                pinching = true
                parent.onBrush(.cancelled, .zero)
                startZoom = parent.zoom
                let a = g.location(in: view)
                let z0 = max(0.01, parent.zoom)
                let o = parent.offset
                anchorPoint = CGPoint(
                    x: size.width / 2 + (a.x - size.width / 2 - o.width) / z0,
                    y: size.height / 2 + (a.y - size.height / 2 - o.height) / z0
                )
            case .changed:
                let a = g.location(in: view)
                let z1 = min(4, max(1, startZoom * g.scale))
                let raw = CGSize(
                    width: a.x - size.width / 2 - (anchorPoint.x - size.width / 2) * z1,
                    height: a.y - size.height / 2 - (anchorPoint.y - size.height / 2) * z1
                )
                setTransform(zoom: z1, offset: clamp(raw, zoom: z1, size: size), animated: false)
            case .ended, .cancelled, .failed:
                pinching = false
                if parent.zoom < 1.03 { setTransform(zoom: 1, offset: .zero, animated: true) }
            default:
                break
            }
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            switch g.state {
            case .changed:
                let t = g.translation(in: view)
                g.setTranslation(.zero, in: view)
                if pinching { return }
                let o = CGSize(width: parent.offset.width + t.x, height: parent.offset.height + t.y)
                parent.offset = clamp(o, zoom: parent.zoom, size: view.bounds.size)
            default:
                break
            }
        }

        @objc func brush(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            let loc = g.location(in: view)
            switch g.state {
            case .began:
                let t = g.translation(in: view)
                let start = CGPoint(x: loc.x - t.x, y: loc.y - t.y)
                parent.onBrush(.began, fraction(of: start, in: view))
                parent.onBrush(.moved, fraction(of: loc, in: view))
            case .changed:
                parent.onBrush(.moved, fraction(of: loc, in: view))
            case .ended:
                parent.onBrush(.moved, fraction(of: loc, in: view))
                parent.onBrush(.ended, .zero)
            case .cancelled, .failed:
                parent.onBrush(.cancelled, .zero)
            default:
                break
            }
        }

        @objc func dot(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let view = g.view else { return }
            let p = fraction(of: g.location(in: view), in: view)
            parent.onBrush(.began, p)
            parent.onBrush(.ended, .zero)
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let view = g.view else { return }
            if parent.zoom > 1.05 {
                setTransform(zoom: 1, offset: .zero, animated: true)
            } else {
                let z: CGFloat = 2.5
                let size = view.bounds.size
                let a = g.location(in: view)
                let raw = CGSize(width: (a.x - size.width / 2) * (1 - z), height: (a.y - size.height / 2) * (1 - z))
                setTransform(zoom: z, offset: clamp(raw, zoom: z, size: size), animated: true)
            }
        }

        // MARK: Delegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            let first = gestureRecognizer === pinchRecognizer || gestureRecognizer === panRecognizer
            let second = other === pinchRecognizer || other === panRecognizer
            return first && second
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === panRecognizer { return parent.zoom > 1.01 }
            return true
        }
    }
}
