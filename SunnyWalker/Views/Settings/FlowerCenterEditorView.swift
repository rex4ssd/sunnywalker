// SunnyWalker — FlowerCenterEditorView.swift
// 自訂向日葵吉祥物：讓家長挑一張照片、用拖曳 + 縮放把最適合的部分放進圓形花心，存成全 app 共用的
// 一張花心圖（AppSettings.flowerImage）。SunflowerAvatar 會把它 clip 成圓顯示在花心。
//
// 做法：用同一個 `FlowerCropContent`（正方形）同時當「即時預覽」與「輸出」——預覽 clip 成圓給家長看，
// 輸出存正方形（角落用不到，SunflowerAvatar 一樣 clip 圓）。輸出用 ImageRenderer 直接把目前畫面的
// scale/offset 渲染下來，所見即所得。

import SwiftUI
import PhotosUI

struct FlowerCenterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    /// 預覽 / 輸出共用的正方形邊長（point）。預覽與輸出用同一個值才能 WYSIWYG。
    private let canvas: CGFloat = 300

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?

    // 已提交的縮放 / 位移；手勢進行中用 GestureState 疊加即時值。
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private var liveScale: CGFloat { min(max(scale * pinch, 1), 4) }
    private var liveOffset: CGSize {
        CGSize(width: offset.width + drag.width, height: offset.height + drag.height)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()
                VStack(spacing: 24) {
                    Text(image == nil
                         ? LocalizedStringKey("flower_editor_pick_hint")
                         : LocalizedStringKey("flower_editor_adjust_hint"))
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    cropArea

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(image == nil ? "flower_editor_choose_photo" : "flower_editor_change_photo",
                              systemImage: "photo.on.rectangle.angled")
                            .font(SunnyFonts.caption())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(SunnyColors.leafFresh))
                    }

                    if settings.hasFlowerImage {
                        Button(role: .destructive) {
                            settings.clearFlowerImage()
                            image = nil
                            resetTransform()
                        } label: {
                            Label("flower_editor_remove", systemImage: "trash")
                                .font(SunnyFonts.caption(14))
                        }
                    }

                    Spacer()
                }
                .padding(.top, 28)
            }
            .navigationTitle(Text("flower_editor_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { saveAndDismiss() }
                        .font(SunnyFonts.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(SunnyColors.lanternOrange)
                        .disabled(image == nil)
                }
            }
        }
        .onAppear {
            // 既有照片：當作起點顯示（已是裁好的正方形，scale 1 / offset 0）。
            if image == nil { image = settings.flowerImage }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    await MainActor.run {
                        image = ui
                        resetTransform()
                    }
                }
            }
        }
    }

    // MARK: - Crop area

    private var cropArea: some View {
        ZStack {
            // 底：淡淡的格子底，沒選照片時也看得到圓形花心位置。
            Circle()
                .fill(SunnyColors.sunnyGray.opacity(0.12))
                .frame(width: canvas, height: canvas)

            if let img = image {
                FlowerCropContent(image: img, canvas: canvas, scale: liveScale, offset: liveOffset)
                    .frame(width: canvas, height: canvas)
                    .clipShape(Circle())
                    .gesture(
                        DragGesture()
                            .updating($drag) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                offset = CGSize(width: offset.width + value.translation.width,
                                                height: offset.height + value.translation.height)
                            }
                    )
                    .simultaneousGesture(
                        MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in
                                scale = min(max(scale * value.magnification, 1), 4)
                            }
                    )
            } else {
                Image(systemName: "camera.macro")
                    .font(.system(size: 54))
                    .foregroundStyle(SunnyColors.wheatGold)
            }

            // 圓形取景框
            Circle()
                .stroke(Color.white, lineWidth: 4)
                .frame(width: canvas, height: canvas)
                .shadow(color: .black.opacity(0.12), radius: 4)
        }
        .frame(width: canvas, height: canvas)
    }

    // MARK: - Actions

    private func resetTransform() {
        scale = 1
        offset = .zero
    }

    @MainActor
    private func saveAndDismiss() {
        guard let img = image else { dismiss(); return }
        let renderer = ImageRenderer(
            content: FlowerCropContent(image: img, canvas: canvas, scale: scale, offset: offset)
                .frame(width: canvas, height: canvas)
        )
        renderer.scale = 3   // 300pt × 3 → 900px 輸出，夠清晰
        if let ui = renderer.uiImage {
            settings.saveFlowerImage(ui)
        }
        dismiss()
    }
}

// MARK: - FlowerCropContent (shared by live preview and the saved render)

/// 把照片以「填滿正方形」為基準，再套上使用者的 scale / offset。預覽與輸出用同一個 view，確保
/// 所見即所得。輸出存正方形即可——SunflowerAvatar 會再 clip 成圓。
private struct FlowerCropContent: View {
    let image: UIImage
    let canvas: CGFloat
    let scale: CGFloat
    let offset: CGSize

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: canvas, height: canvas)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: canvas, height: canvas)
            .clipped()
    }
}
