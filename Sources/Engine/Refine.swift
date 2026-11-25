import Foundation
import CoreGraphics

/// One brush stroke on the hair matte. Coordinates are fractions of the photo (origin top left), so a stroke means the
/// same thing at preview size and at export size.
struct BrushStroke: Equatable, Codable {
    var points: [CGPoint]
    /// Brush radius as a fraction of the photo's longest side.
    var radius: CGFloat
    /// true paints hair in, false erases hair.
    var addsHair: Bool
    /// 0 (very soft) ... 1 (hard edge).
    var hardness: CGFloat = 0.5
}

enum MatteRefiner {
    /// Replays the strokes on top of a base matte. Order matters, later strokes win.
    static func apply(_ strokes: [BrushStroke], to base: Plane) -> Plane {
        guard !strokes.isEmpty else { return base }
        var plane = base
        let w = plane.width, h = plane.height
        let longSide = Float(max(w, h))
        for stroke in strokes {
            guard !stroke.points.isEmpty else { continue }
            let radius = max(1.5, Float(stroke.radius) * longSide)
            let hardness = Float(min(max(stroke.hardness, 0), 1))
            let spacing = max(1, radius * 0.3)
            // Walk along the polyline and stamp.
            var stamps: [(Float, Float)] = []
            var prev = stroke.points[0]
            stamps.append((Float(prev.x) * Float(w), Float(prev.y) * Float(h)))
            for pt in stroke.points.dropFirst() {
                let ax = Float(prev.x) * Float(w), ay = Float(prev.y) * Float(h)
                let bx = Float(pt.x) * Float(w), by = Float(pt.y) * Float(h)
                let dist = ((bx - ax) * (bx - ax) + (by - ay) * (by - ay)).squareRoot()
                let steps = max(1, Int(dist / spacing))
                for s in 1...steps {
                    let t = Float(s) / Float(steps)
                    stamps.append((ax + (bx - ax) * t, ay + (by - ay) * t))
                }
                prev = pt
            }
            for (cx, cy) in stamps {
                let x0 = max(0, Int(cx - radius)), x1 = min(w - 1, Int(cx + radius) + 1)
                let y0 = max(0, Int(cy - radius)), y1 = min(h - 1, Int(cy + radius) + 1)
                if x1 < x0 || y1 < y0 { continue }
                for y in y0...y1 {
                    for x in x0...x1 {
                        let dx = Float(x) + 0.5 - cx, dy = Float(y) + 0.5 - cy
                        let d = (dx * dx + dy * dy).squareRoot() / radius
                        if d >= 1 { continue }
                        // Falloff: flat inside `hardness`, smooth to zero at the edge.
                        let inner = hardness * 0.9
                        let fall = d <= inner ? 1 : 1 - PlaneOps.smoothstep(inner, 1, d)
                        let i = y * w + x
                        if stroke.addsHair {
                            plane.data[i] = max(plane.data[i], fall)
                        } else {
                            plane.data[i] = plane.data[i] * (1 - fall)
                        }
                    }
                }
            }
        }
        return plane
    }
}

/// Undo and redo for edits made of whole snapshots (look + strokes).
struct EditHistory<State: Equatable> {
    private(set) var past: [State] = []
    private(set) var future: [State] = []
    private(set) var present: State
    let limit: Int

    init(initial: State, limit: Int = 60) {
        present = initial
        self.limit = limit
    }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// Records a new state. Equal states are ignored so a tap that changed nothing does not fill the history.
    mutating func commit(_ new: State) {
        guard new != present else { return }
        past.append(present)
        if past.count > limit { past.removeFirst(past.count - limit) }
        present = new
        future.removeAll()
    }

    private var liveBase: State?

    /// Changes the current state while a slider is being dragged, without adding an undo step.
    /// Call `endLive` when the drag finishes: one undo step covers the whole drag.
    mutating func live(_ new: State) {
        if liveBase == nil { liveBase = present }
        present = new
    }

    mutating func endLive() {
        guard let base = liveBase else { return }
        liveBase = nil
        guard present != base else { return }
        past.append(base)
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    mutating func undo() {
        endLive()
        guard let last = past.popLast() else { return }
        future.append(present)
        present = last
    }

    mutating func redo() {
        endLive()
        guard let next = future.popLast() else { return }
        past.append(present)
        present = next
    }
}
