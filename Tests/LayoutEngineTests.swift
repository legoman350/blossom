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
