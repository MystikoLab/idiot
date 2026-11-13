import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
    import VisionKit
#endif

enum ReceiptSuggestion: Identifiable, Equatable {
    case amount(Double)
    case title(String)
    case date(Date)

    var id: String {
        switch self {
        case .amount: "amount"
        case .title: "title"
        case .date: "date"
        }
    }

    var label: String {
        switch self {
        case let .amount(value): "Amount \(String(format: "%.2f", value))"
        case let .title(value): "Title \(value)"
        case let .date(value): "Date \(value.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }
}

struct ReceiptsSection: View {
    let files: [ReceiptFile]
    let suggestions: [ReceiptSuggestion]
    let isScanning: Bool
    let onAdd: ([ReceiptFile]) -> Void
    let onRemove: (ReceiptFile) -> Void
    let onApply: (ReceiptSuggestion) -> Void
    let onDismiss: (ReceiptSuggestion) -> Void

    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var showScanner = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var previewURL: URL?

    var body: some View {
        Section {
            if !files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(files) { file in
                            thumbnail(file)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            addMenu

            if isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading receipt…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { suggestion in
                            chip(suggestion)
                        }
                    }
                }
            }
        } header: {
            Text("Receipts")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: AttachmentProcessor.importTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            Task {
                await onAdd(ReceiptImporter.files(from: urls))
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, matching: .images)
        .onChange(of: photoItems) {
            let items = photoItems
            guard !items.isEmpty else { return }
            photoItems = []
            Task {
                var payloads: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        payloads.append(data)
                    }
                }
                await onAdd(ReceiptImporter.files(from: payloads, filename: "Photo"))
            }
        }
        .quickLookPreview($previewURL, in: ReceiptPreview.urls(for: files))
        #if os(iOS)
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner { pages in
                    showScanner = false
                    guard !pages.isEmpty else { return }
                    Task {
                        await onAdd(ReceiptImporter.files(from: pages, filename: "Scan"))
                    }
                }
                .ignoresSafeArea()
            }
        #endif
    }

    private var addMenu: some View {
        Menu {
            Button {
                showFileImporter = true
            } label: {
                Label("Choose File…", systemImage: "folder")
            }

            Button {
                showPhotoPicker = true
            } label: {
                Label("Photo Library…", systemImage: "photo.on.rectangle")
            }

            #if os(iOS)
                if VNDocumentCameraViewController.isSupported {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan Document…", systemImage: "doc.viewfinder")
                    }
                }
            #endif

            Button {
                Task {
                    await onAdd(ReceiptImporter.pasteboardFiles())
                }
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
        } label: {
            Label("Add Receipt", systemImage: "paperclip")
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .fixedSize()
        #endif
    }

    private func thumbnail(_ file: ReceiptFile) -> some View {
        Button {
            previewURL = ReceiptPreview.urls(for: [file]).first
        } label: {
            ReceiptThumbnailView(file: file)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button {
                onRemove(file)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.body)
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove \(file.filename)")
        }
        .contextMenu {
            Button("View") {
                previewURL = ReceiptPreview.urls(for: [file]).first
            }
            Button("Remove", role: .destructive) {
                onRemove(file)
            }
        }
        .padding(.top, 6)
        .padding(.trailing, 6)
        .accessibilityLabel(file.filename)
    }

    private func chip(_ suggestion: ReceiptSuggestion) -> some View {
        HStack(spacing: 6) {
            Button {
                onApply(suggestion)
            } label: {
                Label(suggestion.label, systemImage: "text.viewfinder")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button {
                onDismiss(suggestion)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.15), in: Capsule())
    }
}

struct ReceiptThumbnailView: View {
    let file: ReceiptFile
    @State private var thumbnail: ReceiptThumbnail?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.4))
            if let thumbnail {
                Image(decorative: thumbnail.image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: file.isPDF ? "doc.richtext" : "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .task(id: file.id) {
            let file = file
            thumbnail = await Task.detached(priority: .utility) {
                AttachmentProcessor.thumbnail(for: file, maxPixelSize: 192)
            }.value
        }
    }
}

extension View {
    @ViewBuilder
    func receiptImportTarget(onAdd: @escaping ([ReceiptFile]) -> Void) -> some View {
        #if os(macOS)
            let load: ([NSItemProvider]) -> Bool = { providers in
                guard !providers.isEmpty else { return false }
                Task {
                    await onAdd(ReceiptImporter.files(from: providers))
                }
                return true
            }
            onDrop(of: AttachmentProcessor.importTypes + [.fileURL], isTargeted: nil, perform: load)
                .onPasteCommand(of: AttachmentProcessor.importTypes) { providers in
                    _ = load(providers)
                }
                .importsItemProviders(AttachmentProcessor.importTypes, onImport: load)
        #else
            self
        #endif
    }
}

#if os(iOS)
    struct DocumentScanner: UIViewControllerRepresentable {
        let onFinish: ([Data]) -> Void

        func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
            let controller = VNDocumentCameraViewController()
            controller.delegate = context.coordinator
            return controller
        }

        func updateUIViewController(_: VNDocumentCameraViewController, context _: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(onFinish: onFinish)
        }

        final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
            let onFinish: ([Data]) -> Void

            init(onFinish: @escaping ([Data]) -> Void) {
                self.onFinish = onFinish
            }

            func documentCameraViewController(_: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
                let pages = (0 ..< scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.95) }
                onFinish(pages)
            }

            func documentCameraViewControllerDidCancel(_: VNDocumentCameraViewController) {
                onFinish([])
            }

            func documentCameraViewController(_: VNDocumentCameraViewController, didFailWithError _: Error) {
                onFinish([])
            }
        }
    }
#endif
