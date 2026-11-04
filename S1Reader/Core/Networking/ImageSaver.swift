import Foundation
import Photos
import UIKit

enum ImageSaveError: LocalizedError {
    case denied
    case downloadFailed
    case notAnImage

    var errorDescription: String? {
        switch self {
        case .denied:
            return "没有相册写入权限。请到「设置 → S1 → 照片」里允许添加照片。"
        case .downloadFailed:
            return "图片下载失败，请稍后再试。"
        case .notAnImage:
            return "这张图片的格式无法保存。"
        }
    }
}

/// Saves a remote image into the user's photo library (add-only permission).
enum ImageSaver {
    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ImageSaveError.denied
        }
        guard let data = await ImageLoader.shared.originalData(for: url) else {
            throw ImageSaveError.downloadFailed
        }
        guard let image = UIImage(data: data) else {
            throw ImageSaveError.notAnImage
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
