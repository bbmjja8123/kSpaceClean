// kWise/Features/Anatomy/CompositionRing.swift
//
// hero 迷你比例环（feature sprint Task 9）：compositionBar 的图形升级 ——
// SwiftUI Canvas 环形分段（2π 守恒，top-N 之外的份额折叠为「其他」），
// 分段可点 → 下钻对应组。
//
// 设计要点：
// - 纯折叠数学在 `RingFold`（无色、无视图依赖，可直接单测）；
// - 「其他」分段用 `RingSliceModel.isOther` 哨兵判别，不伪造 GroupKind
//   （brief 修正：`id` 仅为满足 Identifiable，语义判断一律先看 isOther）；
// - 命中区用与 Canvas 完全同几何的环形带 Shape（不是整块扇形——避免圆心
//   附近大片误触），分段点击 → onSelect(kind)；
// - 入场缩放动画经 AccessibilitySettings.reduceMotionAnimation 统一门控
//   （Reduce Motion 时无位移，审计测试钉住）。
import SwiftUI
import DesignSystem

/// 比例环的一片（纯模型，无色 —— 颜色由 `CompositionSlice` 携带，视图层映射）。
/// `isOther == true` 表示这是 top-N 折叠后的「其他」合并片：`id` 只是占位
/// （取被折叠最大片 kind，保证 Identifiable 唯一），不参与下钻语义。
struct RingSliceModel: Identifiable, Equatable {
    let id: GroupKind
    let fraction: Double
    var isOther: Bool = false

    init(id: GroupKind, fraction: Double, isOther: Bool = false) {
        self.id = id
        self.fraction = fraction
        self.isOther = isOther
    }
}

/// top-N 折叠：前 `top` 大份额原样保留，其余合并为一片「其他」。
/// 角度守恒：输入 fraction 合计 == 输出合计（1.0 口径）。
enum RingFold {

    /// 折叠规则：
    /// - 片数 ≤ `top` → 原样返回（没有折叠发生的必要）；
    /// - 其余合计为 0（异常的零份额片）→ 只保留前 N（合并片无意义）；
    /// - 否则前 N + 一片 `isOther == true` 的合并片（fraction = 其余合计，
    ///   id 取被折叠的最大片 kind，仅作占位）。
    static func fold(_ slices: [RingSliceModel], top: Int = 3) -> [RingSliceModel] {
        guard slices.count > top else { return slices }
        let sorted = slices.sorted { $0.fraction > $1.fraction }
        let head = sorted.prefix(top)
        let rest = sorted.dropFirst(top)
        let restFraction = rest.reduce(0.0) { $0 + $1.fraction }
        guard restFraction > 0, let largestRest = rest.first else { return Array(head) }
        return Array(head) + [RingSliceModel(id: largestRest.id,
                                             fraction: restFraction,
                                             isOther: true)]
    }
}

/// hero 迷你比例环：Canvas 绘制（2π 守恒），分段命中区 → 下钻。
/// 「其他」片不可点（没有对应的单一组可以下钻——诚实降级）。
struct CompositionRing: View {

    let slices: [CompositionSlice]
    var onSelect: (GroupKind) -> Void = { _ in }

    @State private var appeared = false

    private static let ringSize: CGFloat = 84
    private static let lineWidth: CGFloat = 10
    private static let inset: CGFloat = 4

    /// 折叠后的片（视图唯一渲染口径）。「其他」片颜色用中性灰，
    /// 不冒用任何被折叠组的原色。
    private var folded: [RingSliceModel] {
        RingFold.fold(slices.map { RingSliceModel(id: $0.id, fraction: $0.fraction) })
    }

    /// kind → 颜色（来自 compositionSlices 的既有配色）。
    private var colorByKind: [GroupKind: Color] {
        Dictionary(slices.map { ($0.id, $0.color) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let pieces = folded
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - Self.inset
                var start = Angle.degrees(-90)
                for slice in pieces where slice.fraction > 0 {
                    let sweep = Angle.degrees(slice.fraction * 360)
                    var path = Path()
                    path.addArc(center: center, radius: radius,
                                startAngle: start, endAngle: start + sweep,
                                clockwise: false)
                    let shading = GraphicsContext.Shading.color(
                        slice.isOther ? Self.otherColor : colorByKind[slice.id] ?? Self.otherColor)
                    context.stroke(path, with: shading,
                                   style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .butt))
                    start += sweep
                }
            }
            // 命中区：与 Canvas 同几何的环形带（外弧 + 内弧回卷），不是整块
            // 扇形 —— 圆心附近不误触。ForEach 按下标（folded 内 id 理论唯一，
            // 但下标最稳）。
            ForEach(pieces.indices, id: \.self) { index in
                let slice = pieces[index]
                if slice.fraction > 0, !slice.isOther {
                    RingBandShape(start: Self.startAngle(index: index, pieces: pieces),
                                  end: Self.endAngle(index: index, pieces: pieces),
                                  lineWidth: Self.lineWidth,
                                  inset: Self.inset)
                        .contentShape(RingBandShape(start: Self.startAngle(index: index, pieces: pieces),
                                                    end: Self.endAngle(index: index, pieces: pieces),
                                                    lineWidth: Self.lineWidth,
                                                    inset: Self.inset))
                        .onTapGesture { onSelect(slice.id) }
                }
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        // 入场缩放：Reduce Motion 时无缩放（初值即 1），动画退化为最短线性。
        .scaleEffect(appeared || AccessibilitySettings.reduceMotionEnabled
                     ? 1 : 0.9)
        .onAppear {
            withAnimation(AccessibilitySettings.reduceMotionAnimation(.easeOut(duration: 0.4))) {
                appeared = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(a11ySummary))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(String(localized: String.LocalizationValue("canvas.ring.a11y.hint"))))
    }

    /// 「其他」合并片的中性色 —— 不冒用被折叠组的语义色。
    private static let otherColor = Color.textSecondary.opacity(0.45)

    // MARK: 角度几何（Canvas 与命中区共用一套口径）

    private static func startAngle(index: Int, pieces: [RingSliceModel]) -> Angle {
        let consumed = pieces.prefix(index).reduce(0.0) { $0 + $1.fraction }
        return Angle.degrees(-90 + consumed * 360)
    }

    private static func endAngle(index: Int, pieces: [RingSliceModel]) -> Angle {
        startAngle(index: index, pieces: pieces)
            + Angle.degrees(pieces[index].fraction * 360)
    }

    // MARK: A11y

    /// 读屏摘要：按折叠后的片合成「组名 + 百分比」清单（与视觉一致，
    /// 「其他」用独立文案）。单一 key，条目 join 后填入。
    private var a11ySummary: String {
        let items = folded.map { slice -> String in
            let name = slice.isOther
                ? String(localized: String.LocalizationValue("canvas.ring.other"))
                : CanvasGroupAssembler.localizedTitle(for: slice.id)
            let percent = Int((slice.fraction * 100).rounded())
            return "\(name) \(percent)%"
        }
        return String(
            format: String(localized: String.LocalizationValue("canvas.ring.a11y.summary")),
            items.joined(separator: ", "))
    }
}

/// 环形带命中区 Shape：外弧正向 + 内弧回卷 + 闭合 —— 与 Canvas 的描边带
/// 几何一致（同 start/inset/lineWidth 口径）。
private struct RingBandShape: Shape {
    let start: Angle
    let end: Angle
    let lineWidth: CGFloat
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2 - inset
        var path = Path()
        guard outerRadius > 0 else { return path }
        let innerRadius = max(0, outerRadius - lineWidth)
        path.addArc(center: center, radius: outerRadius,
                    startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius,
                    startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
