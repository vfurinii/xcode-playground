//
//  ContentView.swift
//  wallpaper-collage
//
//  Created by Vitor Furini on 04/05/26.
//

import SwiftUI
import PhotosUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    struct CollageImage: Identifiable, Hashable {
        let id = UUID()
        let image: NSImage
        var usesFill = false
        var quarterTurns = 0
    }

    @State private var images: [CollageImage] = []
    @State private var statusMessage: String?
    @State private var previewImage: NSImage?
    @State private var isPreviewPresented = false
    @State private var removeSpaces = true
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var importedPhotoItemIDs: Set<String> = []
    private let lastSelectionFolderName = "LastWallpaperSelection"

    var body: some View {
        VStack {
            HStack {
                Button("Adicionar Fotos") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.allowedContentTypes = [.image]

                    if panel.runModal() == .OK {
                        let selected = panel.urls.compactMap { url -> CollageImage? in
                            guard let image = NSImage(contentsOf: url) else { return nil }
                            return CollageImage(image: image)
                        }
                        images.append(contentsOf: selected)
                        saveCurrentSelection(silent: true)
                    }
                }

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 100,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text("Importar do Photos")
                }

                Button("Criar Wallpaper") {
                    createAndApplyWallpaper()
                }
                .disabled(images.isEmpty)

                Button("Salvar Última Seleção") {
                    saveCurrentSelection()
                }
                .disabled(images.isEmpty)

                Button("Usar Última Seleção") {
                    loadLastSelection()
                }

                Button("Preview") {
                    showPreview()
                }
                .disabled(images.isEmpty)

                Button("Exportar Imagem") {
                    exportWallpaperImage()
                }
                .disabled(images.isEmpty)

                Button("Limpar Tudo", role: .destructive) {
                    images.removeAll()
                    selectedPhotoItems.removeAll()
                    importedPhotoItemIDs.removeAll()
                    clearLastSelectionStorage()
                    statusMessage = "Todas as imagens foram removidas."
                }
                .disabled(images.isEmpty)
            }
            .padding(.bottom, 8)

            Toggle("Remover espaços entre imagens (global)", isOn: $removeSpaces)
                .toggleStyle(.switch)
                .padding(.bottom, 6)

            Text("\(images.count) imagem(ns) selecionada(s)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                        VStack(spacing: 8) {
                            Image(nsImage: item.image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 150)
                                .rotationEffect(.degrees(Double((item.quarterTurns % 4) * 90)))

                            HStack(spacing: 8) {
                                Button("←") {
                                    moveImage(from: index, to: index - 1)
                                }
                                .disabled(index == 0)

                                Button("→") {
                                    moveImage(from: index, to: index + 1)
                                }
                                .disabled(index == images.count - 1)

                                Button("Excluir", role: .destructive) {
                                    images.remove(at: index)
                                    saveCurrentSelection(silent: true)
                                }

                                Button(item.usesFill ? "Fit" : "Fill") {
                                    toggleImageAdjustment(at: index)
                                }

                                Button("↻") {
                                    rotateImageClockwise(at: index)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding()
        .sheet(isPresented: $isPreviewPresented) {
            VStack(spacing: 12) {
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(minWidth: 700, minHeight: 400)
                } else {
                    Text("Não foi possível gerar o preview.")
                }

                Button("Fechar") {
                    isPreviewPresented = false
                }
            }
            .padding()
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                await importFromPhotos(newItems)
            }
        }
    }

    @MainActor
    private func moveImage(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex else { return }
        guard sourceIndex >= 0, sourceIndex < images.count else { return }
        guard destinationIndex >= 0, destinationIndex < images.count else { return }

        let element = images.remove(at: sourceIndex)
        images.insert(element, at: destinationIndex)
        saveCurrentSelection(silent: true)
    }

    @MainActor
    private func toggleImageAdjustment(at index: Int) {
        guard images.indices.contains(index) else { return }
        images[index].usesFill.toggle()
        saveCurrentSelection(silent: true)
    }

    @MainActor
    private func rotateImageClockwise(at index: Int) {
        guard images.indices.contains(index) else { return }
        images[index].quarterTurns = (images[index].quarterTurns + 1) % 4
        saveCurrentSelection(silent: true)
    }

    @MainActor
    private func createAndApplyWallpaper() {
        guard !images.isEmpty else { return }

        let targetSize = NSScreen.main?.frame.size ?? CGSize(width: 2560, height: 1440)
        guard let collage = renderCollage(size: targetSize) else {
            statusMessage = "Falha ao montar o wallpaper."
            return
        }

        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wallpaper-collage-\(Int(Date().timeIntervalSince1970)).png")

        guard saveImageAsPNG(collage, to: fileURL) else {
            statusMessage = "Falha ao salvar o wallpaper."
            return
        }

        do {
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(fileURL, for: screen, options: [:])
            }
            statusMessage = "Wallpaper criado e aplicado com sucesso."
        } catch {
            statusMessage = "Wallpaper criado, mas não foi possível aplicar: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func showPreview() {
        guard !images.isEmpty else { return }
        let targetSize = NSScreen.main?.frame.size ?? CGSize(width: 2560, height: 1440)
        previewImage = renderCollage(size: targetSize)
        isPreviewPresented = true
    }

    @MainActor
    private func exportWallpaperImage() {
        guard !images.isEmpty else { return }

        let targetSize = NSScreen.main?.frame.size ?? CGSize(width: 2560, height: 1440)
        guard let collage = renderCollage(size: targetSize) else {
            statusMessage = "Falha ao gerar imagem para exportação."
            return
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "wallpaper-collage.png"
        savePanel.title = "Exportar Wallpaper"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            if saveImageAsPNG(collage, to: url) {
                statusMessage = "Imagem exportada com sucesso."
            } else {
                statusMessage = "Falha ao exportar imagem."
            }
        }
    }

    @MainActor
    private func saveCurrentSelection(silent: Bool = false) {
        guard let folderURL = lastSelectionDirectoryURL() else {
            if !silent {
                statusMessage = "Não foi possível acessar pasta para salvar seleção."
            }
            return
        }

        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: folderURL.path) {
                let existingFiles = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                for fileURL in existingFiles {
                    try fileManager.removeItem(at: fileURL)
                }
            } else {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }

            for (index, item) in images.enumerated() {
                let fileURL = folderURL.appendingPathComponent(String(format: "image-%04d.png", index))
                guard saveImageAsPNG(item.image, to: fileURL) else {
                    if !silent {
                        statusMessage = "Falha ao salvar a seleção atual."
                    }
                    return
                }
            }

            if !silent {
                statusMessage = "Última seleção salva com sucesso."
            }
        } catch {
            if !silent {
                statusMessage = "Erro ao salvar seleção: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func loadLastSelection() {
        guard let folderURL = lastSelectionDirectoryURL() else {
            statusMessage = "Não foi possível acessar pasta da última seleção."
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folderURL.path) else {
            statusMessage = "Nenhuma seleção salva encontrada."
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            let loaded = files.compactMap { url -> CollageImage? in
                guard let image = NSImage(contentsOf: url) else { return nil }
                return CollageImage(image: image)
            }

            guard !loaded.isEmpty else {
                statusMessage = "A última seleção está vazia ou inválida."
                return
            }

            images = loaded
            statusMessage = "\(loaded.count) imagem(ns) carregada(s) da última seleção."
        } catch {
            statusMessage = "Erro ao carregar última seleção: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func clearLastSelectionStorage() {
        guard let folderURL = lastSelectionDirectoryURL() else { return }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folderURL.path) else { return }

        do {
            try fileManager.removeItem(at: folderURL)
        } catch {
            statusMessage = "Falha ao limpar seleção salva: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func renderCollage(size: CGSize) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        let count = images.count
        let columns = max(1, Int(ceil(sqrt(Double(count)))))
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let cellWidth = size.width / CGFloat(columns)
        let cellHeight = size.height / CGFloat(rows)

        for (index, item) in images.enumerated() {
            let row = index / columns
            let col = index % columns

            let x = CGFloat(col) * cellWidth
            let y = size.height - CGFloat(row + 1) * cellHeight
            let cellRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: cellRect).addClip()

            let angle = CGFloat((item.quarterTurns % 4) * 90)
            let radians = angle * .pi / 180

            let isOddTurn = item.quarterTurns % 2 != 0
            let effectiveSize = isOddTurn
                ? CGSize(width: item.image.size.height, height: item.image.size.width)
                : item.image.size

            let localContainer = CGRect(
                x: -cellRect.width / 2,
                y: -cellRect.height / 2,
                width: cellRect.width,
                height: cellRect.height
            )
            let shouldFill = removeSpaces || item.usesFill
            let localDrawRect = shouldFill
                ? filledRect(for: effectiveSize, in: localContainer)
                : fittedRect(for: effectiveSize, in: localContainer)

            if let cgContext = NSGraphicsContext.current?.cgContext {
                cgContext.translateBy(x: cellRect.midX, y: cellRect.midY)
                cgContext.rotate(by: radians)
            }

            item.image.draw(in: localDrawRect)
            NSGraphicsContext.restoreGraphicsState()
        }

        image.unlockFocus()
        return image
    }

    private func fittedRect(for imageSize: CGSize, in container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }

        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = container.midX - width / 2
        let y = container.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func filledRect(for imageSize: CGSize, in container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }

        let scale = max(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = container.midX - width / 2
        let y = container.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func saveImageAsPNG(_ image: NSImage, to url: URL) -> Bool {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return false
        }

        do {
            try pngData.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private func lastSelectionDirectoryURL() -> URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupportURL
            .appendingPathComponent("wallpaper-collage", isDirectory: true)
            .appendingPathComponent(lastSelectionFolderName, isDirectory: true)
    }

    private func importFromPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        var importedCount = 0
        for item in items {
            if let id = item.itemIdentifier, importedPhotoItemIDs.contains(id) {
                continue
            }

            if let data = try? await item.loadTransferable(type: Data.self),
               let image = NSImage(data: data) {
                await MainActor.run {
                    images.append(CollageImage(image: image))
                    if let id = item.itemIdentifier {
                        importedPhotoItemIDs.insert(id)
                    }
                    importedCount += 1
                }
            }
        }

        await MainActor.run {
            if importedCount == 0 {
                statusMessage = "Nenhuma imagem foi importada do Photos."
            } else {
                statusMessage = "\(importedCount) imagem(ns) importada(s) do Photos."
                saveCurrentSelection(silent: true)
            }
        }
    }
}
