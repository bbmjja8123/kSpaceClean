// kWise/Features/Assistant/AssistantView.swift
//
// 助手 surface (v2.0 Phase 8). Zero-network Q&A: intent match → answer
// cards. No match → example questions, never a fabricated answer (C-5).
import SwiftUI
import DesignSystem

struct AssistantView: View {
    @Environment(\.appGraph) private var injectedGraph
    @StateObject private var viewModel: AssistantViewModel

    init(viewModel: AssistantViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AssistantViewModel())
    }

    private var graph: AppGraph { injectedGraph ?? AppGraph.shared }

    var body: some View {
        assistantBody
            .onAppear {
                // 实扫数据接线：largestFiles/categorySummary 回答基于真实扫描。
                viewModel.scanResultsProvider = { graph.assistantScanVM }
            }
    }

    private var assistantBody: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    inputBar
                    if let answer = viewModel.answer {
                        answerSection(answer)
                    } else {
                        suggestionsSection(AssistantAnswerBuilder.exampleQuestions)
                    }
                }
                .padding(AppSpacing.lg)
            }
        }
        .background(Color.bgPrimary)
    }

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(Color.brandPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("清理助手")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text("本机智能匹配 · 不联网 · 不上传任何数据")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .padding(AppSpacing.lg)
    }

    private var inputBar: some View {
        HStack(spacing: AppSpacing.sm) {
            TextField("问问空间都用在哪了…", text: $viewModel.draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.ask() }
            Button("提问") { viewModel.ask() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func answerSection(_ answer: AssistantAnswer) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(answer.headline)
                .font(AppFont.title3)
                .foregroundStyle(Color.textPrimary)

            ForEach(answer.cards) { card in
                HStack {
                    Image(systemName: "doc")
                        .foregroundStyle(Color.brandPrimary)
                    Text(card.title)
                        .font(AppFont.body)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(card.detail)
                        .font(AppFont.monoDigit)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(AppSpacing.md)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            }

            if !answer.suggestions.isEmpty {
                suggestionsSection(answer.suggestions)
            }
        }
    }

    private func suggestionsSection(_ suggestions: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("试试这样问：")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
            HStack {
                ForEach(suggestions.prefix(4), id: \.self) { suggestion in
                    Button(suggestion) {
                        viewModel.askSuggestion(suggestion)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

#Preview {
    AssistantView()
        .frame(width: 680, height: 480)
        .preferredColorScheme(.dark)
}
