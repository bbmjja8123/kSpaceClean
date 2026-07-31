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

// MARK: - Page 4: FDA Request

struct OnboardingPage4: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(Color.warning)

            VStack(spacing: AppSpacing.sm) {
                Text("需要完整磁盘访问权限")
                    .font(AppFont.largeTitle)
                    .foregroundColor(.textPrimary)

                Text("kSpaceClean 需要 Full Disk Access 才能扫描所有文件")
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.xxxl)

            // Instruction steps
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                StepLabel(number: "1", text: "点击下方按钮打开系统设置")
                StepLabel(number: "2", text: "进入「隐私与安全性」→「完全磁盘访问权限」")
                StepLabel(number: "3", text: "找到 kSpaceClean 并开启开关")
                StepLabel(number: "4", text: "返回本应用，点击「下一步」继续")
            }
            .padding(.horizontal, AppSpacing.xxl)

            // Action buttons
            VStack(spacing: AppSpacing.md) {
                Button {
                    coordinator.openSystemSettings()
                } label: {
                    Label("打开系统设置", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                        .font(AppFont.title3)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .controlSize(.large)

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
        .background(Color.bgPrimary)
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
            TabView(selection: $coordinator.currentPage) {
                OnboardingPage1().tag(0)
                OnboardingPage2().tag(1)
                OnboardingPage3().tag(2)
                OnboardingPage4(coordinator: coordinator).tag(3)
                OnboardingPage5(coordinator: coordinator).tag(4)
            }

            // Bottom navigation bar
            if coordinator.currentPage < coordinator.totalPages - 1 {
                Divider()
                    .foregroundColor(.separatorColor)

                HStack {
                    Spacer()

                    Button("下一步") {
                        coordinator.next()
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
        }
        .frame(minWidth: 540, minHeight: 460)
        .background(Color.bgPrimary)
        .onAppear {
            coordinator.onComplete = onComplete
        }
    }
}
