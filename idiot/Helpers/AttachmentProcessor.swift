import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

nonisolated struct ReceiptFile: Identifiable, Sendable, Equatable {
    let id: UUID
    let filename: String
    let contentType: String
    let data: Data

    var isPDF: Bool {
        contentType == UTType.pdf.identifier
    }

    static func == (lhs: ReceiptFile, rhs: ReceiptFile) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated struct ReceiptThumbnail: @unchecked Sendable {
    let image: CGImage
}

nonisolated enum AttachmentProcessor {
    static let maxPixelSize = 2000
    static let jpegQuality = 0.7
    static let importTypes: [UTType] = [.image, .pdf]

    static func process(data: Data, filename: String? = nil) -> ReceiptFile? {
        let base = filename.map { ($0 as NSString).deletingPathExtension }.flatMap { $0.isEmpty ? nil : $0 } ?? "Receipt"
        if isPDF(data) {
            return ReceiptFile(id: UUID(), filename: base + ".pdf", contentType: UTType.pdf.identifier, data: data)
        }
        guard let image = downscaled(data, maxPixelSize: maxPixelSize), let jpeg = jpegData(image) else { return nil }
        return ReceiptFile(id: UUID(), filename: base + ".jpg", contentType: UTType.jpeg.identifier, data: jpeg)
    }

    static func process(url: URL) -> ReceiptFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return process(data: data, filename: url.lastPathComponent)
    }

    static func thumbnail(for file: ReceiptFile, maxPixelSize: Int) -> ReceiptThumbnail? {
        let image = file.isPDF
            ? renderFirstPage(ofPDF: file.data, maxPixelSize: maxPixelSize)
            : downscaled(file.data, maxPixelSize: maxPixelSize)
        return image.map(ReceiptThumbnail.init)
    }

    static func renderFirstPage(ofPDF data: Data, maxPixelSize: Int) -> CGImage? {
        guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = CGFloat(maxPixelSize) / max(bounds.width, bounds.height)
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private static func isPDF(_ data: Data) -> Bool {
        data.prefix(1024).range(of: Data("%PDF-".utf8)) != nil
    }

    private static func downscaled(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func jpegData(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

nonisolated enum ReceiptImporter {
    static func files(from urls: [URL]) async -> [ReceiptFile] {
        await Task.detached(priority: .userInitiated) {
            urls.compactMap(AttachmentProcessor.process(url:))
        }.value
    }

    static func files(from payloads: [Data], filename: String? = nil) async -> [ReceiptFile] {
        await Task.detached(priority: .userInitiated) {
            payloads.compactMap { AttachmentProcessor.process(data: $0, filename: filename) }
        }.value
    }

    @MainActor
    static func files(from providers: [NSItemProvider]) async -> [ReceiptFile] {
        var files: [ReceiptFile] = []
        for provider in providers {
            if let file = await file(from: provider) {
                files.append(file)
            }
        }
        return files
    }

    @MainActor
    static func pasteboardFiles() async -> [ReceiptFile] {
        #if os(macOS)
            let pasteboard = NSPasteboard.general
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
                let found = await files(from: urls)
                if !found.isEmpty {
                    return found
                }
            }
            for type in [NSPasteboard.PasteboardType.pdf, .png, .tiff] {
                if let data = pasteboard.data(forType: type) {
                    return await files(from: [data], filename: "Pasted")
                }
            }
            return []
        #else
            let pasteboard = UIPasteboard.general
            if let data = pasteboard.data(forPasteboardType: UTType.pdf.identifier) {
                return await files(from: [data], filename: "Pasted")
            }
            let payloads = (pasteboard.images ?? []).compactMap { $0.jpegData(compressionQuality: 0.95) }
            return await files(from: payloads, filename: "Pasted")
        #endif
    }

    @MainActor
    private static func file(from provider: NSItemProvider) async -> ReceiptFile? {
        let name = provider.suggestedName
        let identifier = provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .pdf) || type.conforms(to: .image)
        }
        if let identifier, let data = await data(from: provider, identifier: identifier) {
            return await files(from: [data], filename: name).first
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier), let url = await url(from: provider) {
            return await files(from: [url]).first
        }
        return nil
    }

    @MainActor
    private static func data(from provider: NSItemProvider, identifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    @MainActor
    private static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

nonisolated enum ReceiptPreview {
    static func urls(for files: [ReceiptFile]) -> [URL] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReceiptPreview", isDirectory: true)
        return files.compactMap { file in
            let folder = root.appendingPathComponent(file.id.uuidString, isDirectory: true)
            let name = file.filename.replacingOccurrences(of: "/", with: "-")
            let url = folder.appendingPathComponent(name.isEmpty ? "Receipt" : name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try file.data.write(to: url)
                return url
            } catch {
                return nil
            }
        }
    }
}
