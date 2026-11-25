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

        let shapes: [Int: (Int, Int)] = [1: (1, 1), 2: (2, 1), 3: (2, 2), 4: (2, 2), 5: (3, 2),
                                         6: (3, 2), 7: (3, 3), 8: (3, 3), 9: (3, 3), 10: (4, 3)]
        for (n, expected) in shapes {
            let shape = LayoutEngine.gridShape(count: n)
            check(shape == expected, "gridShape(\(n)) = \(shape), expected \(expected)")
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
