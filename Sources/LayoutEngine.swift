import CoreGraphics
import Foundation

// PURE layout math. No AppKit, no Accessibility: items, a rect and a gap go in, and frames
// come out. This is the only part of the app that can be unit tested, so keep it free of
// anything that touches live windows.
//
// Coordinate convention: rows are filled in order of increasing y. Pass a rect with a
// top-left origin (Accessibility space) so the first item lands in the top-left cell.

enum LayoutStyle: String, CaseIterable {
    /// Rows of cells, shape chosen to fit minimum sizes and stay close to 4:3.
    case grid
    /// The first item (the frontmost window) gets a wide left column; the rest stack on
    /// the right.
    case masterStack
    /// Every item side by side in a single row.
    case columns

    var title: String {
        switch self {
        case .grid:        return "Grid"
        case .masterStack: return "Master + Stack"
        case .columns:     return "Columns"
        }
    }
}

/// How tiling treats floating apps' windows.
enum FloatMode: String, CaseIterable {
    /// Leave floating windows where they are and tile the rest into the space beside them.
    case tileAround
    /// Leave floating windows where they are and tile the full screen underneath them.
    case ignore
    /// Tile floating windows like any other window.
    case tileNormally

    var title: String {
        switch self {
        case .tileAround:   return "Tile Around Them"
        case .ignore:       return "Leave Alone (Overlap)"
        case .tileNormally: return "Tile Like Others"
        }
    }
}

/// Where a single window can be snapped on its screen.
enum SnapPosition: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case stretchVertical, maximize, center

    var title: String {
        switch self {
        case .leftHalf:       return "Left Half"
        case .rightHalf:      return "Right Half"
        case .topHalf:        return "Top Half"
        case .bottomHalf:     return "Bottom Half"
        case .topLeft:        return "Top Left"
        case .topRight:       return "Top Right"
        case .bottomLeft:     return "Bottom Left"
        case .bottomRight:    return "Bottom Right"
        case .firstThird:     return "Left Third"
        case .centerThird:    return "Center Third"
        case .lastThird:      return "Right Third"
        case .firstTwoThirds: return "Left Two Thirds"
        case .lastTwoThirds:  return "Right Two Thirds"
        case .stretchVertical: return "Stretch Vertically"
        case .maximize:       return "Maximize"
        case .center:         return "Center"
        }
    }

    /// Top/Bottom Half change only the vertical: the window keeps its left edge and width,
    /// so a left-third window becomes a top-left third. Every other position sets both axes.
    /// Stretch Vertically is the same idea at full height.
    var keepsHorizontal: Bool { self == .topHalf || self == .bottomHalf || self == .stretchVertical }

    /// The fraction of the area covered: (x0, y0, x1, y1), with y increasing downward.
    /// For `keepsHorizontal` positions only y0/y1 apply. `.center` has none; it keeps the
    /// window's size.
    var fractions: (CGFloat, CGFloat, CGFloat, CGFloat)? {
        switch self {
        case .leftHalf:       return (0, 0, 0.5, 1)
        case .rightHalf:      return (0.5, 0, 1, 1)
        case .topHalf:        return (0, 0, 1, 0.5)
        case .bottomHalf:     return (0, 0.5, 1, 1)
        case .topLeft:        return (0, 0, 0.5, 0.5)
        case .topRight:       return (0.5, 0, 1, 0.5)
        case .bottomLeft:     return (0, 0.5, 0.5, 1)
        case .bottomRight:    return (0.5, 0.5, 1, 1)
        case .firstThird:     return (0, 0, 1.0 / 3, 1)
        case .centerThird:    return (1.0 / 3, 0, 2.0 / 3, 1)
        case .lastThird:      return (2.0 / 3, 0, 1, 1)
        case .firstTwoThirds: return (0, 0, 2.0 / 3, 1)
        case .lastTwoThirds:  return (1.0 / 3, 0, 1, 1)
        case .stretchVertical: return (0, 0, 1, 1)  // x is kept from the window
        case .maximize:       return (0, 0, 1, 1)
        case .center:         return nil
        }
    }
}

/// What the layout needs to know about one window.
struct LayoutItem: Equatable {
    /// Smallest cell the window fits in. Zero when unknown.
    var minSize: CGSize = .zero
    /// Set when the window can't be resized: it gets a cell at least this big and is
    /// centered in it at exactly this size.
    var fixedSize: CGSize? = nil
}

enum LayoutEngine {
    /// Beyond this, cells become useless slivers. Extra windows are left untouched.
    static let maxWindows = 8

    /// Cells closest to this width:height ratio win. 4:3 suits most app windows, and it
    /// turns 3 windows on an ultrawide into 3 columns rather than a 2×2 with a hole.
    static let preferredAspect: CGFloat = 4.0 / 3.0

    /// Share of the width the master window gets in `.masterStack`, before minimums.
    static let masterRatio: CGFloat = 0.6

    /// Unconstrained layout: `count` windows with no minimum sizes.
    static func frames(count: Int, in area: CGRect, style: LayoutStyle = .grid, gap: CGFloat) -> [CGRect] {
        frames(for: Array(repeating: LayoutItem(), count: max(0, count)), in: area, style: style, gap: gap)
    }

    /// Dispatches on style. Every style honors minimum and fixed sizes the same way, and
    /// overlaps only as a last resort.
    static func frames(for items: [LayoutItem], in area: CGRect, style: LayoutStyle, gap rawGap: CGFloat) -> [CGRect] {
        switch style {
        case .grid:
            return frames(for: items, in: area, gap: rawGap)
        case .columns:
            let gap = max(0, rawGap)
            let inner = area.insetBy(dx: gap, dy: gap)
            guard !items.isEmpty, !inner.isNull, inner.width > 0, inner.height > 0 else { return [] }
            return layout(items, rows: 1, inner: inner, gap: gap)?.frames ?? []
        case .masterStack:
            let gap = max(0, rawGap)
            let inner = area.insetBy(dx: gap, dy: gap)
            guard !items.isEmpty, !inner.isNull, inner.width > 0, inner.height > 0 else { return [] }
            // One window has nothing to stack; fall back to filling the area.
            guard items.count > 1 else { return frames(for: items, in: area, gap: rawGap) }
            // Too many windows for a single stack column (slivers): use the grid.
            return masterStack(items, inner: inner, gap: gap)?.frames ?? frames(for: items, in: area, gap: rawGap)
        }
    }

    /// Rows of variable-width cells. Every row count from 1 to n is tried, with items
    /// split evenly across rows in order. Each candidate is sized so every item gets at
    /// least its minimum, and the best one wins:
    /// 1. no overflow beats overflow (then the least overflow wins), and
    /// 2. among equals, cells closest to `preferredAspect`.
    /// If nothing fits, the least-overflowing candidate is returned and windows overlap.
    /// That's the last resort, not a crash.
    static func frames(for items: [LayoutItem], in area: CGRect, gap rawGap: CGFloat) -> [CGRect] {
        let gap = max(0, rawGap)
        // The gap applies around the outside edge too, not only between cells.
        let inner = area.insetBy(dx: gap, dy: gap)
        guard !items.isEmpty, !inner.isNull, inner.width > 0, inner.height > 0 else { return [] }

        var best: Candidate?
        for rows in 1...items.count {
            guard let candidate = layout(items, rows: rows, inner: inner, gap: gap) else { continue }
            if best == nil || candidate.isBetter(than: best!) { best = candidate }
        }
        return best?.frames ?? []
    }

    /// The frame for snapping one window. The gap matches tiling: a full gap at the screen
    /// edges and half a gap on each side of an inner edge. So a left half and a right half
    /// sit exactly one gap apart, the same as two tiled cells.
    static func snapFrame(_ position: SnapPosition, in area: CGRect, gap rawGap: CGFloat, window: CGRect) -> CGRect {
        let windowSize = window.size
        let gap = max(0, rawGap)
        let inner = area.insetBy(dx: gap, dy: gap)
        guard !inner.isNull, inner.width > 0, inner.height > 0 else { return area }

        guard let (x0, y0, x1, y1) = position.fractions else {
            // Center: keep the size (shrunk to fit if needed), centered in the area.
            let w = min(windowSize.width, inner.width), h = min(windowSize.height, inner.height)
            let x = inner.midX - w / 2, y = inner.midY - h / 2
            return snapped(left: x, top: y, right: x + w, bottom: y + h)
        }
        let half = gap / 2
        var left = inner.minX + inner.width * x0 + (x0 > 0 ? half : 0)
        var right = inner.minX + inner.width * x1 - (x1 < 1 ? half : 0)
        if position.keepsHorizontal {
            // Keep the window's own left edge and width, pulled back on-screen if it hangs
            // off a side (and narrowed if it's wider than the screen).
            let width = min(window.width, inner.width)
            left = min(max(window.minX, inner.minX), inner.maxX - width)
            right = left + width
        }
        let top = inner.minY + inner.height * y0 + (y0 > 0 ? half : 0)
        let bottom = inner.minY + inner.height * y1 - (y1 < 1 ? half : 0)
        return snapped(left: left, top: top, right: right, bottom: bottom)
    }

    /// Within this many points per edge, a window counts as already "at" a position.
    /// Loose enough for windows that snap their size to a grid (Terminal).
    static let snapMatchTolerance: CGFloat = 12

    /// Is `window` already at `position` (within `snapMatchTolerance` on every edge)?
    static func isAt(_ position: SnapPosition, window: CGRect, area: CGRect, gap: CGFloat) -> Bool {
        let t = snapMatchTolerance
        let target = snapFrame(position, in: area, gap: gap, window: window)
        return abs(target.minX - window.minX) <= t && abs(target.maxX - window.maxX) <= t
            && abs(target.minY - window.minY) <= t && abs(target.maxY - window.maxY) <= t
    }

    /// For a cycling hotkey: the position after the one the window is at now (wrapping),
    /// or the first if it's at none of them. The window's frame is the only state.
    ///
    /// A window can match several positions at once: a top-half window that's already full
    /// height also matches "stretch vertically". The last match counts (cycles list the
    /// general position first), and steps that wouldn't move the window are skipped, so a
    /// cycle never stalls.
    static func nextSnap(in positions: [SnapPosition], window: CGRect, area: CGRect, gap: CGFloat) -> SnapPosition {
        func isAt(_ position: SnapPosition) -> Bool { LayoutEngine.isAt(position, window: window, area: area, gap: gap) }
        let current = positions.indices.last { isAt(positions[$0]) }
        var next = current.map { ($0 + 1) % positions.count } ?? 0
        for _ in positions.indices where isAt(positions[next]) {  // no-op step: skip it
            next = (next + 1) % positions.count
        }
        return positions[next]
    }

    /// Free strips narrower or shorter than this are useless for tiling and are dropped.
    static let minFreeSide: CGFloat = 200

    /// The largest rectangle of `usable` that no obstacle covers (the maximal-rectangles
    /// method from bin packing). Each obstacle splits every free rect it touches into the
    /// strips left of, right of, above and below it. Those strips overlap one another,
    /// which is what lets the largest one be found. Returns `.zero` if nothing useful is left.
    ///
    /// No gap is added around obstacles: the layout already insets its area by the gap, so
    /// tiles end up exactly one gap away from a floating window.
    static func freeArea(in usable: CGRect, avoiding obstacles: [CGRect]) -> CGRect {
        var free = [usable]
        for raw in obstacles {
            let obstacle = raw.intersection(usable)
            guard !obstacle.isNull, obstacle.width > 0, obstacle.height > 0 else { continue }  // off this area

            var next: [CGRect] = []
            for rect in free {
                let overlap = rect.intersection(obstacle)
                guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else {
                    next.append(rect)
                    continue
                }
                if obstacle.minX > rect.minX {
                    next.append(CGRect(x: rect.minX, y: rect.minY, width: obstacle.minX - rect.minX, height: rect.height))
                }
                if obstacle.maxX < rect.maxX {
                    next.append(CGRect(x: obstacle.maxX, y: rect.minY, width: rect.maxX - obstacle.maxX, height: rect.height))
                }
                if obstacle.minY > rect.minY {
                    next.append(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: obstacle.minY - rect.minY))
                }
                if obstacle.maxY < rect.maxY {
                    next.append(CGRect(x: rect.minX, y: obstacle.maxY, width: rect.width, height: rect.maxY - obstacle.maxY))
                }
            }
            let useful = next.filter { $0.width >= minFreeSide && $0.height >= minFreeSide }
            // Drop rects inside another one (and exact duplicates, keeping the first).
            free = useful.enumerated().filter { i, rect in
                !useful.enumerated().contains { j, other in j != i && other.contains(rect) && (other != rect || j < i) }
            }.map(\.element)
        }
        return free.max { $0.width * $0.height < $1.width * $1.height } ?? .zero
    }

    /// Fill Empty Space: the frame that grows a window into the largest empty part of
    /// `area`, the biggest rectangle no other window covers. Inset by the gap on every side,
    /// so it sits one gap from the screen edges and from its neighbors, like a tiled cell.
    /// nil if the other windows leave no useful room.
    static func fillFrame(in area: CGRect, avoiding others: [CGRect], gap rawGap: CGFloat) -> CGRect? {
        let free = freeArea(in: area, avoiding: others)
        let gap = max(0, rawGap)
        let inner = free.insetBy(dx: gap, dy: gap)
        guard free.width > 0, !inner.isNull, inner.width > 0, inner.height > 0 else { return nil }
        return snapped(left: inner.minX, top: inner.minY, right: inner.maxX, bottom: inner.maxY)
    }

    // MARK: Internals

    private struct Candidate {
        var frames: [CGRect]
        var overflow: CGFloat    // total px by which minimums exceed the area
        var aspectError: CGFloat // mean |log(cell aspect / preferred)|

        func isBetter(than other: Candidate) -> Bool {
            if abs(overflow - other.overflow) > 0.5 { return overflow < other.overflow }
            return aspectError < other.aspectError
        }
    }

    private static func layout(_ items: [LayoutItem], rows: Int, inner: CGRect, gap: CGFloat) -> Candidate? {
        let n = items.count
        let minW = items.map { max(0, $0.fixedSize?.width ?? $0.minSize.width) }
        let minH = items.map { max(0, $0.fixedSize?.height ?? $0.minSize.height) }

        // Balanced split in order; earlier rows take the extra item (3 → [2, 1]).
        var rowItems: [Range<Int>] = []
        var start = 0
        for row in 0..<rows {
            let count = n / rows + (row < n % rows ? 1 : 0)
            rowItems.append(start..<(start + count))
            start += count
        }

        let heights = distribute(inner.height - gap * CGFloat(rows - 1),
                                 mins: rowItems.map { r in r.map { minH[$0] }.max() ?? 0 })
        var overflow = max(0, heights.reduce(0, +) + gap * CGFloat(rows - 1) - inner.height)
        var frames = Array(repeating: CGRect.zero, count: n)
        var aspectError: CGFloat = 0

        var top = inner.minY
        for (row, range) in rowItems.enumerated() {
            let height = heights[row]
            let widths = distribute(inner.width - gap * CGFloat(range.count - 1), mins: range.map { minW[$0] })
            overflow += max(0, widths.reduce(0, +) + gap * CGFloat(range.count - 1) - inner.width)

            var left = inner.minX
            for (column, index) in range.enumerated() {
                let width = widths[column]
                guard width > 0, height > 0 else { return nil }  // no room at all for this shape
                let cell = snapped(left: left, top: top, right: left + width, bottom: top + height)
                frames[index] = items[index].fixedSize.map { centered($0, in: cell) } ?? cell
                aspectError += abs(log(width / height) - log(preferredAspect))
                left += width + gap
            }
            top += height + gap
        }
        return Candidate(frames: frames, overflow: overflow, aspectError: aspectError / CGFloat(n))
    }

    /// Master on the left, the rest stacked top to bottom on the right.
    private static func masterStack(_ items: [LayoutItem], inner: CGRect, gap: CGFloat) -> Candidate? {
        let minW = items.map { max(0, $0.fixedSize?.width ?? $0.minSize.width) }
        let minH = items.map { max(0, $0.fixedSize?.height ?? $0.minSize.height) }
        let stack = 1..<items.count
        let available = inner.width - gap

        // Widths: the master starts at its ratio share, but never below its own minimum,
        // and gives back width if the stack column needs it.
        let stackMinW = stack.map { minW[$0] }.max() ?? 0
        var masterW = max(minW[0], available * masterRatio)
        var stackW = available - masterW
        if stackW < stackMinW {
            stackW = stackMinW
            masterW = max(minW[0], available - stackW)  // may overflow if both minimums are large
        }
        let heights = distribute(inner.height - gap * CGFloat(stack.count - 1), mins: stack.map { minH[$0] })
        guard masterW > 0, stackW > 0, heights.allSatisfy({ $0 >= 60 }) else { return nil }

        var frames = Array(repeating: CGRect.zero, count: items.count)
        let masterCell = snapped(left: inner.minX, top: inner.minY,
                                 right: inner.minX + masterW, bottom: inner.maxY)
        frames[0] = items[0].fixedSize.map { centered($0, in: masterCell) } ?? masterCell

        let stackLeft = inner.minX + masterW + gap
        var top = inner.minY
        for (row, index) in stack.enumerated() {
            let cell = snapped(left: stackLeft, top: top, right: stackLeft + stackW, bottom: top + heights[row])
            frames[index] = items[index].fixedSize.map { centered($0, in: cell) } ?? cell
            top += heights[row] + gap
        }
        let overflow = max(0, masterW + gap + stackW - inner.width)
            + max(0, heights.reduce(0, +) + gap * CGFloat(stack.count - 1) - inner.height)
            + max(0, minH[0] - inner.height)
        return Candidate(frames: frames, overflow: overflow, aspectError: 0)
    }

    /// Splits `total` so every share is at least its minimum and the rest is as even as
    /// possible ("water filling"): shares are max(min, level), with the level chosen so the
    /// shares add up to `total`. If the minimums alone exceed `total`, returns the minimums
    /// (the caller counts that as overflow).
    static func distribute(_ total: CGFloat, mins: [CGFloat]) -> [CGFloat] {
        guard !mins.isEmpty else { return [] }
        if mins.reduce(0, +) >= total { return mins }
        var remaining = total
        var flexible = CGFloat(mins.count)
        // Largest minimums first: any that sit above the even share keep their minimum and
        // drop out, raising the share for the rest.
        for m in mins.sorted(by: >) {
            if m > remaining / flexible {
                remaining -= m
                flexible -= 1
            } else {
                break
            }
        }
        let level = remaining / flexible
        return mins.map { max($0, level) }
    }

    private static func centered(_ size: CGSize, in cell: CGRect) -> CGRect {
        let x = cell.midX - size.width / 2, y = cell.midY - size.height / 2
        return snapped(left: x, top: y, right: x + size.width, bottom: y + size.height)
    }

    /// Round each edge rather than origin and size separately, so neighboring cells keep
    /// an exact gap between them instead of drifting by a pixel.
    private static func snapped(left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) -> CGRect {
        let l = left.rounded(), t = top.rounded(), r = right.rounded(), b = bottom.rounded()
        return CGRect(x: l, y: t, width: r - l, height: b - t)
    }
}
