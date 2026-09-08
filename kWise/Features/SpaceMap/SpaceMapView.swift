// kWise/Features/SpaceMap/SpaceMapView.swift
//
// 空间地图 (v2.0 Phase 4) — DaisyDisk-parity 2D visualization.
//
// Sunburst (Canvas arcs) + slice-diced treemap, both hit-testable and both
// driven by the shared `ScanTreeNode` forest. No Metal, no 3D — the .galaxy
// placeholder this replaces was a dead end per CLAUDE.md §8.1.
import SwiftUI
import DesignSystem

struct SpaceMapView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: SpaceMapViewModel
    @State private var hoveredSegmentID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                Group {
                    switch viewModel.mode {
                    case .sunburst:
                        sunburst(size: side)
                    case .treemap:
                        treemap(size: side)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footerBar
        }
        .background(Color.bgPrimary)
        .onAppear { viewModel.rebuild() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: AppSpacing.md) {
            breadcrumb
            Spacer()
            Picker("视图", selection: Binding(
                get: { viewModel.mode },
                set: { viewModel.setMode($0) }
            )) {
                Text("环形图").tag(SpaceMapViewModel.Mode.sunburst)
                Text("矩形图").tag(SpaceMapViewModel.Mode.treemap)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(AppSpacing.md)
    }

    @ViewBuilder
    private var breadcrumb: some View {
        HStack(spacing: AppSpacing.xs) {
            Button("根目录") { viewModel.popTo(levelID: nil) }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
            ForEach(viewModel.focusPath) { crumb in
                Image(systemName: "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
                Button(crumb.title) { viewModel.popTo(levelID: crumb.id) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    // MARK: - Sunburst

    private func sunburst(size: CGFloat) -> some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let maxRadius = min(canvasSize.width, canvasSize.height) / 2 - 8
            let base = maxRadius * 0.18
            let ringWidth = (maxRadius - base) / 3

            for segment in viewModel.segments {
                let inner = base + CGFloat(segment.depth) * ringWidth
                let outer = inner + ringWidth
                let isSelected = segment.node.state == .checked
                let isHovered = hoveredSegmentID == segment.id

                var path = Path()
                path.addArc(
                    center: center,
                    radius: outer,
                    startAngle: Angle(radians: segment.startAngle - .pi / 2),
                    endAngle: Angle(radians: segment.endAngle - .pi / 2),
                    clockwise: false
                )
                path.addArc(
                    center: center,
                    radius: inner,
                    startAngle: Angle(radians: segment.endAngle - .pi / 2),
                    endAngle: Angle(radians: segment.startAngle - .pi / 2),
                    clockwise: true
                )
                path.closeSubpath()

                context.fill(
                    path,
                    with: .color(color(for: segment, hovered: isHovered).opacity(isSelected ? 1 : 0.9))
                )
                if isHovered {
                    context.stroke(path, with: .color(Color.textPrimary), lineWidth: 1)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let location) = phase {
                hoveredSegmentID = hitTestSunburst(location, canvasSide: size)?.id
            } else {
                hoveredSegmentID = nil
            }
        }
        .onTapGesture { location in
            if let segment = hitTestSunburst(location, canvasSide: size) {
                withAnimation(KFAnimation.easeInOut) {
                    viewModel.tap(segment, modifierHeld: NSEvent.modifierFlags.contains(.command))
                }
            }
        }
    }

    /// Angle→segment hit-test. Canvas angles are measured from 3 o'clock
    /// clockwise; the builder measures from 12 o'clock clockwise, so the
    /// lookup normalizes by −π/2 and wraps negatives.
    private func hitTestSunburst(_ point: CGPoint, canvasSide: CGFloat) -> SpaceSegment? {
        let center = CGPoint(x: canvasSide / 2, y: canvasSide / 2)
        let maxRadius = canvasSide / 2 - 8
        let base = maxRadius * 0.18
        let ringWidth = (maxRadius - base) / 3

        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let radius = (dx * dx + dy * dy).squareRoot()
        guard radius >= base, radius <= maxRadius else { return nil }

        var angle = atan2(dy, dx) + .pi / 2   // 0 at 12 o'clock
        if angle < 0 { angle += 2 * .pi }

        let depth = Int((radius - base) / ringWidth)
        return viewModel.segments.first { segment in
            segment.depth == depth
                && angle >= segment.startAngle && angle < segment.endAngle
        }
    }

    // MARK: - Treemap

    private func treemap(size: CGFloat) -> some View {
        let rects = TreemapSlicer.slice(
            segments: viewModel.segments.filter { $0.depth == 0 },
            in: CGRect(x: 0, y: 0, width: size, height: size)
        )
        return Canvas { context, _ in
            for (segment, rect) in rects {
                var path = Path(rect.insetBy(dx: 1, dy: 1))
                context.fill(path, with: .color(color(for: segment, hovered: hoveredSegmentID == segment.id)))
                path = Path(rect)
                context.stroke(path, with: .color(Color.bgPrimary), lineWidth: 2)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let location) = phase {
                hoveredSegmentID = rects.first { $0.1.contains(location) }?.0.id
            } else {
                hoveredSegmentID = nil
            }
        }
        .onTapGesture { location in
            if let (segment, _) = rects.first(where: { $0.1.contains(location) }) {
                withAnimation(KFAnimation.easeInOut) {
                    viewModel.tap(segment, modifierHeld: NSEvent.modifierFlags.contains(.command))
                }
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: AppSpacing.lg) {
            Label(Self.formatBytes(viewModel.focusedTotalSize), systemImage: "internaldrive")
                .font(AppFont.callout)
                .foregroundStyle(Color.textPrimary)
            Text("点击下钻 · ⌘点击选中待清理")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .padding(AppSpacing.md)
    }

    // MARK: - Colors (token-driven — no raw hex)

    private func color(for segment: SpaceSegment, hovered: Bool) -> Color {
        if segment.node.state == .checked { return .success }
        if segment.isCollapsedBucket { return Color.textSecondary.opacity(0.25) }
        let base: Color
        switch segment.risk {
        case .dangerous, .caution:
            base = .warning
        default:
            base = .brandPrimary
        }
        let depthOpacity = [0.85, 0.65, 0.45][min(segment.depth, 2)]
        return base.opacity(hovered ? min(1, depthOpacity + 0.2) : depthOpacity)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

/// Slice-and-dice treemap layout: alternate horizontal/vertical splits per
/// the largest-remainder order, preserving area ∝ size.
enum TreemapSlicer {
    static func slice(segments: [SpaceSegment], in rect: CGRect) -> [(SpaceSegment, CGRect)] {
        let total = segments.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0, rect.width > 0, rect.height > 0 else { return [] }
        return divide(
            segments.sorted { $0.size > $1.size },
            total: total,
            in: rect,
            horizontal: rect.width >= rect.height
        )
    }

    private static func divide(_ segments: [SpaceSegment],
                               total: Int64,
                               in rect: CGRect,
                               horizontal: Bool) -> [(SpaceSegment, CGRect)] {
        guard let first = segments.first else { return [] }
        if segments.count == 1 {
            return [(first, rect)]
        }
        let firstFraction = Double(first.size) / Double(total)
        let firstLength = horizontal
            ? rect.width * firstFraction
            : rect.height * firstFraction

        let firstRect = horizontal
            ? CGRect(x: rect.minX, y: rect.minY, width: firstLength, height: rect.height)
            : CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstLength)
        let restRect = horizontal
            ? CGRect(x: rect.minX + firstLength, y: rect.minY,
                     width: max(0, rect.width - firstLength), height: rect.height)
            : CGRect(x: rect.minX, y: rect.minY + firstLength,
                     width: rect.width, height: max(0, rect.height - firstLength))

        let restTotal = total - first.size
        var result: [(SpaceSegment, CGRect)] = [(first, firstRect)]
        if restTotal > 0 {
            result += divide(
                Array(segments.dropFirst()),
                total: restTotal,
                in: restRect,
                horizontal: !horizontal
            )
        }
        return result
    }
}

#Preview {
    SpaceMapView(viewModel: SpaceMapViewModel())
        .environmentObject(AppState())
        .frame(width: 800, height: 560)
        .preferredColorScheme(.dark)
}
