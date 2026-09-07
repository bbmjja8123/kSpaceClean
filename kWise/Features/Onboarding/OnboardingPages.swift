import SwiftUI
import DesignSystem

// MARK: - Page 1: Value Proposition

struct OnboardingPage1: View {
    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(Color.brandPrimary)

            VStack(spacing: AppSpacing.sm) {
                Text("更快,更干净")
                    .font(AppFont.largeTitle)
                    .foregroundColor(.textPrimary)

                Text("智能磁盘清理，让您的 Mac 存储空间回到\"足够\"")
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }
}

// MARK: - Page 2: Core Features

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)
                Text(description)
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, AppSpacing.sm)
    }
}

struct OnboardingPage2: View {
    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Text("核心功能")
                .font(AppFont.largeTitle)
                .foregroundColor(.textPrimary)

            VStack(spacing: AppSpacing.xl) {
                FeatureRow(
                    icon: "magnifyingglass",
                    title: "智能扫描",
                    description: "快速扫描系统缓存、应用残留与可清理文件"
                )
                FeatureRow(
                    icon: "brain",
                    title: "AI 智能分类",
                    description: "CoreML 本地 AI 自动识别文件类型，精准分类"
                )
                FeatureRow(
                    icon: "trash",
                    title: "一键清理",
                    description: "智能清理系统缓存、应用残留与临时文件"
                )
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }
}

// MARK: - Page 3: Privacy Promise

struct OnboardingPage3: View {
    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(Color.success)

            VStack(spacing: AppSpacing.sm) {
                Text("隐私至上")
                    .font(AppFont.largeTitle)
                    .foregroundColor(.textPrimary)

                Text("100% 本地处理，零数据上报")
                    .font(AppFont.title3)
                    .foregroundColor(.textSecondary)
            }

            Text("所有扫描、分类和 AI 分析均在您的设备本地完成。\n我们不会收集、上传或分享任何个人数据。")
                .font(AppFont.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }
}

// MARK: - Page 4: Home Folder Grant (PowerScope)

/// PowerScope grant page — replaces the old Full Disk Access instructions.
///
/// MAS sandboxing makes FDA unobtainable; the honest ask is a one-time
/// NSOpenPanel grant of the home folder, persisted as a security-scoped
/// bookmark (see `PowerScope` in kFoundation).
struct OnboardingPage4: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var appScope = AppScope.shared

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "folder.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(Color.brandPrimary)

            VStack(spacing: AppSpacing.sm) {
                Text("授权主目录访问")
                    .font(AppFont.largeTitle)
                    .foregroundColor(.textPrimary)

                Text("kWise 在沙箱内运行，需要你一次性授权主目录才能扫描缓存、日志与应用残留。文件不会被上传，扫描全部在本机完成。")
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.xxxl)

            VStack(spacing: AppSpacing.md) {
                Button {
                    Task { await appScope.grant() }
                } label: {
                    Label(appScope.capability.level == .homeGranted ? "重新选择" : "授权主目录",
                          systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                        .font(AppFont.title3)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
                .controlSize(.large)

                if appScope.capability.level == .homeGranted {
                    Label("已授权", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.stateSuccess)
                        .font(AppFont.callout)
                }

                Button("跳过此步骤", action: coordinator.skipFDA)
                    .buttonStyle(.plain)
                    .font(AppFont.callout)
                    .foregroundColor(.textSecondary)
                    .underline()
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
    }
}

/// A small helper view for rendering numbered instruction steps.
private struct StepLabel: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Text(number)
                .font(AppFont.callout)
                .foregroundColor(.brandPrimary)
                .fontWeight(.bold)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .stroke(Color.brandPrimary, lineWidth: 1.5)
                )

            Text(text)
                .font(AppFont.body)
                .foregroundColor(.textPrimary)
        }
    }
}

// MARK: - Page 5: Ready to Scan

struct OnboardingPage5: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(Color.success)

            VStack(spacing: AppSpacing.sm) {
                Text("准备就绪")
                    .font(AppFont.largeTitle)
                    .foregroundColor(.textPrimary)

                Text("现在开始您的第一次扫描，发现可清理的空间")
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Button {
                coordinator.next()
            } label: {
                Text("开始首次扫描")
                    .frame(maxWidth: .infinity)
                    .font(AppFont.title3)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
            .controlSize(.large)
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }
}

// MARK: - Container

struct OnboardingContainerView: View {
    let onComplete: () -> Void

    @StateObject private var coordinator = OnboardingCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            // UX 重构 Phase 1: a switch instead of a label-less TabView —
            // the native tab strip rendered as an empty artifact strip.
            ZStack {
                switch coordinator.currentPage {
                case 0: OnboardingPage1()
                case 1: OnboardingPage2()
                case 2: OnboardingPage3()
                case 3: OnboardingPage4(coordinator: coordinator)
                default: OnboardingPage5(coordinator: coordinator)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(KFAnimation.easeInOut, value: coordinator.currentPage)
            .transition(.opacity)

            StepIndicatorView(count: coordinator.totalPages,
                              current: coordinator.currentPage)
                .padding(.vertical, AppSpacing.md)

            Divider()
                .foregroundColor(.separatorColor)

            // Bottom navigation bar — unconditional; last page shows 完成.
            HStack(spacing: AppSpacing.md) {
                Button("上一步") {
                    withAnimation(KFAnimation.easeInOut) { coordinator.back() }
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.currentPage == 0)

                Spacer()

                Text("第 \(coordinator.currentPage + 1) / \(coordinator.totalPages) 步")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)

                Button(coordinator.currentPage == coordinator.totalPages - 1 ? "完成" : "下一步") {
                    withAnimation(KFAnimation.easeInOut) { coordinator.next() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
            .background(Color.bgPrimary)
        }
        .frame(minWidth: 540, minHeight: 500)
        .background(Color.bgPrimary)
        .onAppear {
            coordinator.onComplete = onComplete
        }
    }
}

// MARK: - Step Indicator

/// 5 dots + current highlight, so the user always knows where they are
/// (UX 重构 Phase 1 — fixes "不知道有几个步骤，当前处于哪个").
struct StepIndicatorView: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.brandPrimary : Color.bgSecondary)
                    .frame(width: index == current ? 24 : 8, height: 8)
                    .animation(KFAnimation.easeInOut, value: current)
            }
        }
    }
}
