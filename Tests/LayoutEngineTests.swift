import CoreGraphics
import Foundation

// Plain assert-style runner rather than XCTest, because the Command Line Tools don't
// reliably ship XCTest. Run with `./build.sh test`.

@main
struct LayoutEngineTests {
    static var failures = 0

    static func check(_ condition: Bool, _ message: @autoclosure () -> String, line: Int = #line) {
        if !condition {
            failures += 1
            print("FAIL (line \(line)): \(message())")
        }
    }

    static func noOverlaps(_ frames: [CGRect]) -> Bool {
        for i in frames.indices {
            for j in frames.indices where j > i {
                let o = frames[i].intersection(frames[j])
                if !o.isNull && o.width > 0 && o.height > 0 { return false }
            }
        }
        return true
    }

    static func main() {
        let area = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let gap: CGFloat = 8
        let inner = area.insetBy(dx: gap, dy: gap)

        check(LayoutEngine.frames(count: 0, in: area, gap: gap).isEmpty, "n=0 should produce no frames")

        let one = LayoutEngine.frames(count: 1, in: area, gap: gap)
        check(one == [inner], "n=1 should fill the inset area, got \(one)")

        let two = LayoutEngine.frames(count: 2, in: area, gap: gap)
        check(two.count == 2, "n=2 count")
        if two.count == 2 {
            check(two[0].minY == inner.minY && two[1].minY == inner.minY, "n=2 halves share a top edge")
            check(two[0].height == inner.height && two[1].height == inner.height, "n=2 halves are full height")
            check(two[1].minX - two[0].maxX == gap, "n=2 halves are separated by exactly the gap")
            check(abs(two[0].width - two[1].width) <= 1, "n=2 halves have equal width")
        }

        // On a typical laptop screen, unconstrained layouts keep the familiar shapes.
        let rowCounts: [Int: Int] = [3: 2, 4: 2, 5: 2, 6: 2]
        for (n, expectedRows) in rowCounts {
            let rows = Set(LayoutEngine.frames(count: n, in: area, gap: gap).map(\.minY)).count
            check(rows == expectedRows, "n=\(n) on 1440×875: \(rows) rows, expected \(expectedRows)")
        }

        // Ultrawide: 3 windows become one row of 3 columns, not a 2×2 with a stretched row.
        let wide = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let wide3 = LayoutEngine.frames(count: 3, in: wide, gap: gap)
        check(Set(wide3.map(\.minY)).count == 1, "3 windows on an ultrawide should form one row: \(wide3)")

        // distribute(): water filling.
        check(LayoutEngine.distribute(300, mins: [0, 0, 0]) == [100, 100, 100], "even split")
        check(LayoutEngine.distribute(300, mins: [200, 0, 0]) == [200, 50, 50], "big minimum keeps its share")
        check(LayoutEngine.distribute(300, mins: [200, 200]) == [200, 200], "overflow returns the minimums")

        // A stubborn window gets at least its minimum, and nothing overlaps.
        do {
            var items = Array(repeating: LayoutItem(), count: 4)
            items[0].minSize = CGSize(width: 900, height: 300)
            let frames = LayoutEngine.frames(for: items, in: area, gap: gap)
            check(frames.count == 4, "min-size: 4 frames")
            check(frames[0].width >= 900, "min-size: window 0 got \(frames[0].width) wide, needs 900")
            check(noOverlaps(frames), "min-size: cells overlap \(frames)")
            check(frames.allSatisfy { inner.contains($0) }, "min-size: a cell escapes the area")
        }

        // Fixed-size window: centered in a cell at exactly its size, no overlap.
        do {
            var items = Array(repeating: LayoutItem(), count: 3)
            let fixed = CGSize(width: 230, height: 400)
            items[1].fixedSize = fixed
            let frames = LayoutEngine.frames(for: items, in: area, gap: gap)
            check(frames.count == 3, "fixed: 3 frames")
            check(frames[1].size == fixed, "fixed: size changed to \(frames[1].size)")
            check(noOverlaps(frames), "fixed: cells overlap \(frames)")
        }

        // Infeasible: minimums can't all fit. Still n frames with positive sizes, no crash.
        do {
            let items = Array(repeating: LayoutItem(minSize: CGSize(width: 1000, height: 700)), count: 4)
            let frames = LayoutEngine.frames(for: items, in: area, gap: gap)
            check(frames.count == 4, "infeasible: got \(frames.count) frames")
            check(frames.allSatisfy { $0.width >= 1000 && $0.height >= 700 }, "infeasible: minimums not honored")
        }

        let areas = [
            area,
            CGRect(x: -1920, y: 0, width: 1919, height: 1053),   // secondary display left of primary
            CGRect(x: 0, y: 0, width: 301, height: 203),         // tiny, odd dimensions
        ]
        for a in areas {
            let inset = a.insetBy(dx: gap, dy: gap)
            for n in 1...LayoutEngine.maxWindows {
                let frames = LayoutEngine.frames(count: n, in: a, gap: gap)
                check(frames.count == n, "n=\(n) in \(a): got \(frames.count) frames")
                for f in frames {
                    check(f.width > 0 && f.height > 0, "n=\(n): empty cell \(f)")
                    check(inset.contains(f), "n=\(n): cell \(f) escapes \(inset)")
                    check(f == f.integral, "n=\(n): cell \(f) is not pixel-aligned")
                }
                for i in frames.indices {
                    for j in frames.indices where j > i {
                        let overlap = frames[i].intersection(frames[j])
                        check(overlap.isNull || overlap.width <= 0 || overlap.height <= 0,
                              "n=\(n): cells \(frames[i]) and \(frames[j]) overlap")
                    }
                }
                // Every row spans the full width, including a short last row.
                let rows = Dictionary(grouping: frames, by: { $0.minY })
                for (_, row) in rows {
                    check(row.map(\.minX).min() == inset.minX, "n=\(n): row doesn't start at left edge")
                    check(row.map(\.maxX).max() == inset.maxX, "n=\(n): row doesn't reach right edge")
                }
                // Rows fill the full height, top first.
                check(frames.first?.minY == inset.minY, "n=\(n): first cell not at top")
                check(frames.map(\.maxY).max() == inset.maxY, "n=\(n): grid doesn't reach bottom")
            }
        }

        // Every style keeps the basic invariants for 1...8 unconstrained windows.
        for style in LayoutStyle.allCases {
            for n in 1...LayoutEngine.maxWindows {
                let frames = LayoutEngine.frames(count: n, in: area, style: style, gap: gap)
                check(frames.count == n, "\(style) n=\(n): \(frames.count) frames")
                check(frames.allSatisfy { inner.contains($0) && $0.width > 0 && $0.height > 0 },
                      "\(style) n=\(n): a cell escapes or is empty")
                check(noOverlaps(frames), "\(style) n=\(n): overlap")
            }
            check(LayoutEngine.frames(count: 1, in: area, style: style, gap: gap) == [inner], "\(style) n=1 fills")
        }

        // Master + stack: master on the left at ~60%, the stack shares one column on the right.
        do {
            let frames = LayoutEngine.frames(count: 4, in: area, style: .masterStack, gap: gap)
            let master = frames[0], stack = Array(frames.dropFirst())
            check(master.minX == inner.minX && master.height == inner.height, "master: full-height left column")
            check(abs(master.width - (inner.width - gap) * LayoutEngine.masterRatio) <= 1, "master: ~60% width, got \(master.width)")
            check(Set(stack.map(\.minX)).count == 1 && stack.allSatisfy { $0.maxX == inner.maxX }, "stack: one right column")
            check(stack.first?.minY == inner.minY && stack.last?.maxY == inner.maxY, "stack: spans full height")
        }

        // Master + stack honors minimums: a wide stack window takes width from the master.
        do {
            var items = Array(repeating: LayoutItem(), count: 3)
            items[2].minSize = CGSize(width: 700, height: 0)
            let frames = LayoutEngine.frames(for: items, in: area, style: .masterStack, gap: gap)
            check(frames[2].width >= 700, "stack min: got \(frames[2].width)")
            check(noOverlaps(frames), "stack min: overlap")
        }

        // Master + stack with too many windows for one column falls back to the grid
        // rather than producing slivers.
        do {
            let short = CGRect(x: 0, y: 0, width: 1440, height: 400)
            let frames = LayoutEngine.frames(count: 8, in: short, style: .masterStack, gap: gap)
            check(frames.count == 8 && frames.allSatisfy { $0.height >= 60 }, "stack fallback: slivers \(frames)")
        }

        // Columns: one row, equal widths.
        do {
            let frames = LayoutEngine.frames(count: 4, in: area, style: .columns, gap: gap)
            check(Set(frames.map(\.minY)).count == 1, "columns: single row")
            check((frames.map(\.width).max() ?? 0) - (frames.map(\.width).min() ?? 0) <= 1, "columns: equal widths")
        }

        // freeArea: tiling around floating windows.
        do {
            let usable = CGRect(x: 0, y: 25, width: 1440, height: 875)
            check(LayoutEngine.freeArea(in: usable, avoiding: []) == usable, "free: no obstacles → whole area")

            // Docked on the right: the left part remains.
            let right = CGRect(x: 1040, y: 25, width: 400, height: 875)
            check(LayoutEngine.freeArea(in: usable, avoiding: [right]) == CGRect(x: 0, y: 25, width: 1040, height: 875),
                  "free: right-docked float")

            // Small float in the bottom-right corner: the strip beside it (1140×875) beats
            // the strip above it (1440×575).
            let corner = CGRect(x: 1140, y: 600, width: 300, height: 300)
            check(LayoutEngine.freeArea(in: usable, avoiding: [corner]) == CGRect(x: 0, y: 25, width: 1140, height: 875),
                  "free: corner float → \(LayoutEngine.freeArea(in: usable, avoiding: [corner]))")

            // Floats on both edges: the middle column.
            let left = CGRect(x: 0, y: 25, width: 300, height: 875)
            check(LayoutEngine.freeArea(in: usable, avoiding: [left, right]) == CGRect(x: 300, y: 25, width: 740, height: 875),
                  "free: two edge floats → middle")

            // A float on another display doesn't count.
            check(LayoutEngine.freeArea(in: usable, avoiding: [CGRect(x: 2000, y: 0, width: 500, height: 500)]) == usable,
                  "free: off-area obstacle ignored")

            // A float in the middle leaves only strips too small to use, so the result
            // falls below Tiler's 40% threshold and the caller tiles full screen instead.
            let middle = CGRect(x: 300, y: 150, width: 840, height: 600)
            let free = LayoutEngine.freeArea(in: usable, avoiding: [middle])
            check(free.width * free.height < 0.4 * usable.width * usable.height, "free: mid-screen float → too small (\(free))")

            // Everything covered → zero.
            check(LayoutEngine.freeArea(in: usable, avoiding: [usable]) == .zero, "free: fully covered → zero")

            // Fill Empty Space: the free area, one gap in from everything around it.
            check(LayoutEngine.fillFrame(in: usable, avoiding: [right], gap: 8) == CGRect(x: 8, y: 33, width: 1024, height: 859),
                  "fill: left of a right-docked window → \(String(describing: LayoutEngine.fillFrame(in: usable, avoiding: [right], gap: 8)))")
            check(LayoutEngine.fillFrame(in: usable, avoiding: [], gap: 8) == usable.insetBy(dx: 8, dy: 8), "fill: empty screen → maximize")
            check(LayoutEngine.fillFrame(in: usable, avoiding: [usable], gap: 8) == nil, "fill: no room → nil")
        }

        // Snap positions.
        do {
            let size = CGSize(width: 600, height: 400)
            let current = CGRect(x: 300, y: 200, width: size.width, height: size.height)
            func snap(_ p: SnapPosition, from window: CGRect? = nil) -> CGRect {
                LayoutEngine.snapFrame(p, in: area, gap: gap, window: window ?? current)
            }

            check(snap(.maximize) == inner, "snap: maximize fills the inset area")
            let left = snap(.leftHalf), right = snap(.rightHalf)
            check(left.minX == inner.minX && right.maxX == inner.maxX, "snap: halves reach the edges")
            check(right.minX - left.maxX == gap, "snap: halves one gap apart, got \(right.minX - left.maxX)")
            check(left.height == inner.height && abs(left.width - right.width) <= 1, "snap: halves equal and full height")
            // Top/bottom halves keep the window's x and width; only the vertical changes.
            let top = snap(.topHalf), bottom = snap(.bottomHalf)
            check(top.minX == current.minX && top.width == current.width, "snap: top half keeps x/width, got \(top)")
            check(bottom.minX == current.minX && bottom.width == current.width, "snap: bottom half keeps x/width")
            check(top.minY == inner.minY && bottom.maxY == inner.maxY, "snap: top/bottom reach the edges")
            check(bottom.minY - top.maxY == gap, "snap: top/bottom one gap apart")
            // A left-third window snapped to the top becomes the top-left third.
            let third = snap(.firstThird)
            check(snap(.topHalf, from: third).minX == third.minX && snap(.topHalf, from: third).width == third.width,
                  "snap: left third + top half = top-left third")
            // Hanging off the right edge: pulled back inside, width kept.
            let offRight = snap(.topHalf, from: CGRect(x: 1300, y: 100, width: 600, height: 400))
            check(offRight.maxX == inner.maxX && offRight.width == 600, "snap: off-screen window pulled inside (\(offRight))")
            // Wider than the screen: narrowed to fit.
            check(snap(.bottomHalf, from: CGRect(x: -100, y: 0, width: 3000, height: 400)).width == inner.width,
                  "snap: too-wide window narrowed to the screen")

            let corners = [snap(.topLeft), snap(.topRight), snap(.bottomLeft), snap(.bottomRight)]
            check(noOverlaps(corners), "snap: corners overlap")
            check(corners[0].minX == inner.minX && corners[0].minY == inner.minY, "snap: top-left in the corner")
            check(corners[3].maxX == inner.maxX && corners[3].maxY == inner.maxY, "snap: bottom-right in the corner")

            let thirds = [snap(.firstThird), snap(.centerThird), snap(.lastThird)]
            check(noOverlaps(thirds), "snap: thirds overlap")
            check(thirds[1].minX - thirds[0].maxX == gap && thirds[2].minX - thirds[1].maxX == gap, "snap: thirds one gap apart")
            check(snap(.firstTwoThirds).maxX == thirds[1].maxX, "snap: left two-thirds ends where the center third does")
            check(snap(.lastTwoThirds).minX == thirds[1].minX, "snap: right two-thirds starts where the center third does")

            // Stretch vertically: x and width kept, full height.
            let stretched = snap(.stretchVertical)
            check(stretched.minX == current.minX && stretched.width == current.width, "snap: stretch keeps x/width")
            check(stretched.minY == inner.minY && stretched.maxY == inner.maxY, "snap: stretch is full height")

            // Cycling thirds: none → first → center → last → first.
            let cycle: [SnapPosition] = [.firstThird, .centerThird, .lastThird]
            func next(_ w: CGRect) -> SnapPosition { LayoutEngine.nextSnap(in: cycle, window: w, area: area, gap: gap) }
            check(next(current) == .firstThird, "cycle: from elsewhere starts at the first third")
            check(next(snap(.firstThird)) == .centerThird, "cycle: first → center")
            check(next(snap(.centerThird)) == .lastThird, "cycle: center → last")
            check(next(snap(.lastThird)) == .firstThird, "cycle: last wraps to first")
            // A few points off (Terminal's grid snapping) still counts as being there.
            check(next(snap(.centerThird).insetBy(dx: 4, dy: 3)) == .lastThird, "cycle: tolerance")
            // Top half → full height → top half, keeping the window's x and width.
            let vertical: [SnapPosition] = [.topHalf, .stretchVertical]
            func nextV(_ w: CGRect) -> SnapPosition { LayoutEngine.nextSnap(in: vertical, window: w, area: area, gap: gap) }
            check(nextV(current) == .topHalf, "cycle: top key starts at top half")
            check(nextV(snap(.topHalf)) == .stretchVertical, "cycle: top half → full height")
            check(nextV(snap(.stretchVertical)) == .topHalf, "cycle: full height → top half")
            check(LayoutEngine.nextSnap(in: [.bottomHalf, .stretchVertical], window: snap(.bottomHalf), area: area, gap: gap)
                  == .stretchVertical, "cycle: bottom half → full height")

            // Center: keep size first, then two thirds, half, two thirds… never stalls on
            // "already centered".
            let centerCycle: [SnapPosition] = [.center, .centerTwoThirds, .centerHalf]
            func nextC(_ w: CGRect) -> SnapPosition { LayoutEngine.nextSnap(in: centerCycle, window: w, area: area, gap: gap) }
            check(nextC(current) == .center, "center cycle: off-center window → center at its size")
            check(nextC(snap(.center)) == .centerTwoThirds, "center cycle: centered → two thirds")
            check(nextC(snap(.centerTwoThirds)) == .centerHalf, "center cycle: two thirds → half")
            check(nextC(snap(.centerHalf)) == .centerTwoThirds, "center cycle: half → two thirds (skips no-op center)")
            let twoThirdsC = snap(.centerTwoThirds)
            check(abs(twoThirdsC.midX - inner.midX) <= 1 && abs(twoThirdsC.midY - inner.midY) <= 1, "center two thirds is centered")
            check(abs(twoThirdsC.width - inner.width * 2 / 3) <= gap + 1, "center two thirds ~2/3 wide")
            let halfC = snap(.centerHalf)
            check(abs(halfC.midX - inner.midX) <= 1 && halfC.minY == inner.minY && halfC.maxY == inner.maxY, "center half: centered, full height")

            let pair: [SnapPosition] = [.firstTwoThirds, .lastTwoThirds]
            check(LayoutEngine.nextSnap(in: pair, window: snap(.firstTwoThirds), area: area, gap: gap) == .lastTwoThirds,
                  "cycle: two thirds toggles")

            let centered = snap(.center)
            check(centered.size == size, "snap: center keeps size")
            check(abs(centered.midX - inner.midX) <= 1 && abs(centered.midY - inner.midY) <= 1, "snap: center is centered")
            let huge = LayoutEngine.snapFrame(.center, in: area, gap: gap, window: CGRect(x: 0, y: 0, width: 5000, height: 5000))
            check(huge == inner, "snap: oversized window centered is clamped to the area")
        }

        // A gap larger than the area leaves no room: produce nothing rather than negative sizes.
        check(LayoutEngine.frames(count: 4, in: CGRect(x: 0, y: 0, width: 20, height: 20), gap: 30).isEmpty,
              "oversized gap should produce no frames")

        if failures == 0 {
            print("LayoutEngine: all tests passed")
            exit(0)
        } else {
            print("LayoutEngine: \(failures) failure(s)")
            exit(1)
        }
    }
}
