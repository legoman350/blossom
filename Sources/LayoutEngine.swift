import CoreGraphics
import Foundation

// PURE layout math. No AppKit, no Accessibility: a count, a rect, a style and a gap go in,
// and frames come out. This is the only part of the app that can be unit tested, so keep
// it free of anything that touches live windows.
//
// Coordinate convention: rows are filled in order of increasing y. Pass a rect with a
// top-left origin (Accessibility space) so the first window lands in the top-left cell.

enum LayoutStyle {
    case grid
}

enum LayoutEngine {
    /// Beyond this, cells become useless slivers. Extra windows are left untouched.
    static let maxWindows = 8

    static func frames(count: Int, in area: CGRect, style: LayoutStyle = .grid, gap: CGFloat) -> [CGRect] {
        guard count > 0, area.width > 0, area.height > 0 else { return [] }
        switch style {
        case .grid: return grid(count: count, area: area, gap: max(0, gap))
        }
    }

    /// n=1 fills the area, n=2 splits it into side-by-side halves, and anything larger
    /// uses columns = ceil(sqrt(n)), with as many rows as that needs.
    static func gridShape(count: Int) -> (columns: Int, rows: Int) {
        if count <= 1 { return (1, 1) }
        if count == 2 { return (2, 1) }
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = (count + columns - 1) / columns
        return (columns, rows)
    }

    private static func grid(count: Int, area: CGRect, gap: CGFloat) -> [CGRect] {
        let (columns, rows) = gridShape(count: count)
        // The gap applies around the outside edge too, not only between cells.
        let inner = area.insetBy(dx: gap, dy: gap)
        let rowHeight = (inner.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        guard rowHeight > 0 else { return [] }

        var result: [CGRect] = []
        for row in 0..<rows {
            let inRow = min(columns, count - row * columns)
            // A short last row stretches its cells across the full width instead of
            // leaving an empty hole in the bottom-right corner.
            let cellWidth = (inner.width - gap * CGFloat(inRow - 1)) / CGFloat(inRow)
            guard cellWidth > 0 else { return [] }
            let top = inner.minY + CGFloat(row) * (rowHeight + gap)
            for col in 0..<inRow {
                let left = inner.minX + CGFloat(col) * (cellWidth + gap)
                result.append(snapped(left: left, top: top, right: left + cellWidth, bottom: top + rowHeight))
            }
        }
        return result
    }

    /// Round each edge rather than origin and size separately, so neighboring cells keep
    /// an exact gap between them instead of drifting by a pixel.
    private static func snapped(left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) -> CGRect {
        let l = left.rounded(), t = top.rounded(), r = right.rounded(), b = bottom.rounded()
        return CGRect(x: l, y: t, width: r - l, height: b - t)
    }
}
