// kWise/Features/Common/Components/KWThumbnailView.swift
//
// Toolbox 异步缩略图 (v2.3 Phase 1) — QLThumbnailGenerator 生成，加载中
// 显示 ProgressView，失败回退 NSWorkspace 通用文件图标。
import AppKit
import SwiftUI
import DesignSystem

struct KWThumbnailView: View {
    let url: URL
    var size: CGFloat = 64

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: size, height: size)
        .background(Color.bgSecondary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        .task(id: url) {
            failed = false
            image = nil
            if let result = await KWThumbnailCache.shared.thumbnail(for: url, size: size) {
                image = result
            } else {
                failed = true
            }
        }
    }
}
