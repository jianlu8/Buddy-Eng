import CoreImage
import CryptoKit
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import Vision

struct PortraitPreparedImages {
    let backgroundPlate: UIImage
    let torsoPlate: UIImage
    let headPlate: UIImage
    let faceDetailOverlay: UIImage
    let eyeMask: UIImage
    let mouthMask: UIImage
    let featheredMatte: UIImage
    let subjectMask: UIImage
}

@MainActor
final class PortraitCharacterRuntime: ObservableObject {
    struct CachedPreparedSnapshot {
        let derivedAssets: PortraitDerivedAssets
        let preparedImages: PortraitPreparedImages
    }

    private static var sourceImageCache: [String: UIImage] = [:]
    private static var preparedSnapshotCache: [String: CachedPreparedSnapshot] = [:]
    private static var preparationTasks: [String: Task<CachedPreparedSnapshot, Error>] = [:]

    @Published private(set) var image: UIImage?
    @Published private(set) var derivedAssets: PortraitDerivedAssets?
    @Published private(set) var preparedImages: PortraitPreparedImages?
    @Published private(set) var focusCrop: CGRect = CharacterCatalog.primaryPortraitProfile.focusCrop
    @Published private(set) var preparationState: PortraitPreparationState = .idle

    private var activeProfileID: String?

    static func previewImage(for bundle: CharacterBundle) -> UIImage? {
        guard bundle.renderRuntimeKind == .photoPseudo3D,
              let portraitProfileID = bundle.portraitProfileID,
              let profile = CharacterCatalog.portraitProfile(for: portraitProfileID) else {
            return nil
        }
        return previewImage(for: profile)
    }

    static func cachedPreparedSnapshot(for bundle: CharacterBundle) -> CachedPreparedSnapshot? {
        guard bundle.renderRuntimeKind == .photoPseudo3D,
              let portraitProfileID = bundle.portraitProfileID else {
            return nil
        }
        return preparedSnapshotCache[portraitProfileID]
    }

    static func prewarmIfNeeded(for bundle: CharacterBundle) async {
        guard bundle.renderRuntimeKind == .photoPseudo3D,
              let portraitProfileID = bundle.portraitProfileID,
              let profile = CharacterCatalog.portraitProfile(for: portraitProfileID) else {
            return
        }

        _ = previewImage(for: profile)
        _ = try? await preparedSnapshot(for: profile)
    }

    func prepareIfNeeded(bundle: CharacterBundle) async {
        guard bundle.renderRuntimeKind == .photoPseudo3D,
              let portraitProfileID = bundle.portraitProfileID,
              let profile = CharacterCatalog.portraitProfile(for: portraitProfileID) else {
            return
        }

        if activeProfileID == profile.id, case .ready = preparationState {
            return
        }
        if activeProfileID == profile.id, case .preparing = preparationState {
            return
        }

        activeProfileID = profile.id
        focusCrop = profile.focusCrop
        image = Self.previewImage(for: profile)
        guard image != nil else {
            derivedAssets = nil
            preparedImages = nil
            preparationState = .failed("Missing local portrait asset.")
            return
        }

        if let cached = Self.preparedSnapshotCache[profile.id] {
            applyPreparedSnapshot(cached)
            preparationState = .ready
            return
        }

        preparationState = .preparing

        do {
            let cached = try await Self.preparedSnapshot(for: profile)
            applyPreparedSnapshot(cached)
            preparationState = .ready
        } catch {
            derivedAssets = nil
            preparedImages = nil
            preparationState = .failed(error.localizedDescription)
        }
    }

    private static func previewImage(for profile: PortraitRenderProfile) -> UIImage? {
        if let cached = sourceImageCache[profile.id] {
            return cached
        }

        guard let image = PortraitAssetPipeline.loadBundledImage(named: profile.sourceAssetName) else {
            return nil
        }
        sourceImageCache[profile.id] = image
        return image
    }

    private static func preparedSnapshot(for profile: PortraitRenderProfile) async throws -> CachedPreparedSnapshot {
        if let cached = preparedSnapshotCache[profile.id] {
            return cached
        }

        if let task = preparationTasks[profile.id] {
            return try await task.value
        }
        let task = Task.detached(priority: .userInitiated) {
            let normalizedData = try PortraitAssetPipeline.normalizedSourceData(for: profile)
            let assets = try PortraitAssetPipeline.prepare(profile: profile, normalizedSourceData: normalizedData)
            let preparedImages = try PortraitAssetPipeline.loadPreparedImages(from: assets)
            return CachedPreparedSnapshot(derivedAssets: assets, preparedImages: preparedImages)
        }
        preparationTasks[profile.id] = task

        do {
            let snapshot = try await task.value
            preparedSnapshotCache[profile.id] = snapshot
            preparationTasks[profile.id] = nil
            return snapshot
        } catch {
            preparationTasks[profile.id] = nil
            throw error
        }
    }

    private func applyPreparedSnapshot(_ snapshot: CachedPreparedSnapshot) {
        derivedAssets = snapshot.derivedAssets
        preparedImages = snapshot.preparedImages
        focusCrop = snapshot.derivedAssets.focusCrop
    }
}

private enum PortraitAssetError: LocalizedError {
    case missingSourceAsset
    case cannotDecodeSource
    case cannotEncodeSource
    case cannotCreateDestination(String)
    case cannotLoadPreparedAsset(String)

    var errorDescription: String? {
        switch self {
        case .missingSourceAsset:
            return "Local portrait asset is unavailable."
        case .cannotDecodeSource:
            return "The portrait photo could not be decoded."
        case .cannotEncodeSource:
            return "The portrait photo could not be normalized for processing."
        case let .cannotCreateDestination(name):
            return "Failed to cache portrait asset \(name)."
        case let .cannotLoadPreparedAsset(name):
            return "Failed to read cached portrait asset \(name)."
        }
    }
}

private struct PortraitGeometry {
    var focusCrop: CGRect
    var faceRect: CGRect
    var headRect: CGRect
    var torsoRect: CGRect
    var headAnchor: CGPoint
    var eyeAnchors: [CGPoint]
    var mouthRect: CGRect
    var shoulderLine: CGFloat
}

private enum PortraitAssetPipeline {
    private static let ciContext = CIContext(options: nil)

    static func normalizedSourceData(for profile: PortraitRenderProfile) throws -> Data {
        if let sourceURL = bundledImageURL(named: profile.sourceAssetName),
           let data = try? Data(contentsOf: sourceURL) {
            return data
        }

        guard let image = loadBundledImage(named: profile.sourceAssetName),
              let encoded = image.pngData() ?? image.jpegData(compressionQuality: 1.0) else {
            throw PortraitAssetError.cannotEncodeSource
        }
        return encoded
    }

    static func loadBundledImage(named name: String) -> UIImage? {
        for fileName in candidateFileNames(for: name) {
            if let url = Bundle.main.url(forResource: fileName, withExtension: "jpg"),
               let image = UIImage(contentsOfFile: url.path) {
                return normalized(image)
            }
            if let url = Bundle.main.url(forResource: fileName, withExtension: "jpeg"),
               let image = UIImage(contentsOfFile: url.path) {
                return normalized(image)
            }
        }
        return nil
    }

    private static func bundledImageURL(named name: String) -> URL? {
        for fileName in candidateFileNames(for: name) {
            if let url = Bundle.main.url(forResource: fileName, withExtension: "jpg") {
                return url
            }
            if let url = Bundle.main.url(forResource: fileName, withExtension: "jpeg") {
                return url
            }
        }
        return nil
    }

    private static func candidateFileNames(for name: String) -> [String] {
        [name, "UserPortrait", "myself"]
    }

    static func prepare(profile: PortraitRenderProfile, normalizedSourceData: Data) throws -> PortraitDerivedAssets {
        let imageSource = CGImageSourceCreateWithData(normalizedSourceData as CFData, nil)
        guard let imageSource,
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw PortraitAssetError.cannotDecodeSource
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let imageExtent = CGRect(origin: .zero, size: imageSize)
        let sourceImage = CIImage(cgImage: cgImage)
        var cacheSeed = Data(profile.cacheKey.utf8)
        cacheSeed.append(normalizedSourceData)
        let checksum = SHA256.hash(data: cacheSeed).hexString
        let filesystem = AppFilesystem()
        try filesystem.prepareDirectories()

        let cacheDirectory = filesystem.portraitCacheDirectoryURL
            .appendingPathComponent(checksum, isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let metadataURL = cacheDirectory.appendingPathComponent("PortraitDerivedAssets.json")
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let data = try Data(contentsOf: metadataURL)
            let decoded = try JSONDecoder().decode(PortraitDerivedAssets.self, from: data)
            let urls = [
                decoded.backgroundPlateURL,
                decoded.torsoPlateURL,
                decoded.headPlateURL,
                decoded.faceDetailOverlayURL,
                decoded.eyeMaskURL,
                decoded.mouthMaskURL,
                decoded.featheredMatteURL,
                decoded.subjectMaskURL
            ]
            if urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
                return decoded
            }
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let subjectMask = try generateSubjectMask(handler: requestHandler, imageExtent: imageExtent)
        let geometry = try resolveGeometry(profile: profile, handler: requestHandler, imageSize: imageSize)
        let featheredMatte = softenMask(subjectMask, radius: 12, extent: imageExtent)
        let backgroundMask = inverted(subjectMask, extent: imageExtent)
        let headMask = combineMasks(
            subjectMask,
            makeEllipseMask(size: imageSize, normalizedRect: geometry.headRect, feather: 14)
        )
        let torsoMask = combineMasks(
            subjectMask,
            makeRoundedRectMask(size: imageSize, normalizedRect: geometry.torsoRect, cornerRatio: 0.22, feather: 18)
        )
        let faceMask = combineMasks(
            subjectMask,
            makeEllipseMask(size: imageSize, normalizedRect: geometry.faceRect.insetBy(dx: -0.03, dy: -0.02), feather: 8)
        )
        let eyeMask = makeEyeMask(size: imageSize, normalizedPoints: geometry.eyeAnchors, feather: 7)
        let mouthMask = makeRoundedRectMask(
            size: imageSize,
            normalizedRect: geometry.mouthRect.insetBy(dx: -0.04, dy: -0.03),
            cornerRatio: 0.45,
            feather: 10
        )

        let backgroundPlate = masked(sourceImage, with: backgroundMask, extent: imageExtent)
        let torsoPlate = masked(sourceImage, with: torsoMask, extent: imageExtent)
        let headPlate = masked(sourceImage, with: headMask, extent: imageExtent)
        let detailBase = sourceImage
            .applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 2.0,
                "inputIntensity": 0.85
            ])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.08,
                kCIInputContrastKey: 1.10,
                kCIInputBrightnessKey: 0.01
            ])
        let faceDetailOverlay = masked(detailBase, with: faceMask, extent: imageExtent)

        let backgroundPlateURL = cacheDirectory.appendingPathComponent("background-plate.png")
        let torsoPlateURL = cacheDirectory.appendingPathComponent("torso-plate.png")
        let headPlateURL = cacheDirectory.appendingPathComponent("head-plate.png")
        let faceDetailOverlayURL = cacheDirectory.appendingPathComponent("face-detail-overlay.png")
        let eyeMaskURL = cacheDirectory.appendingPathComponent("eye-mask.png")
        let mouthMaskURL = cacheDirectory.appendingPathComponent("mouth-mask.png")
        let featheredMatteURL = cacheDirectory.appendingPathComponent("feathered-matte.png")
        let subjectMaskURL = cacheDirectory.appendingPathComponent("subject-mask.png")

        try writePNG(backgroundPlate, to: backgroundPlateURL, extent: imageExtent, name: "background-plate")
        try writePNG(torsoPlate, to: torsoPlateURL, extent: imageExtent, name: "torso-plate")
        try writePNG(headPlate, to: headPlateURL, extent: imageExtent, name: "head-plate")
        try writePNG(faceDetailOverlay, to: faceDetailOverlayURL, extent: imageExtent, name: "face-detail-overlay")
        try writePNG(eyeMask, to: eyeMaskURL, extent: imageExtent, name: "eye-mask")
        try writePNG(mouthMask, to: mouthMaskURL, extent: imageExtent, name: "mouth-mask")
        try writePNG(featheredMatte, to: featheredMatteURL, extent: imageExtent, name: "feathered-matte")
        try writePNG(subjectMask, to: subjectMaskURL, extent: imageExtent, name: "subject-mask")

        let assets = PortraitDerivedAssets(
            backgroundPlateURL: backgroundPlateURL,
            torsoPlateURL: torsoPlateURL,
            headPlateURL: headPlateURL,
            faceDetailOverlayURL: faceDetailOverlayURL,
            eyeMaskURL: eyeMaskURL,
            mouthMaskURL: mouthMaskURL,
            featheredMatteURL: featheredMatteURL,
            subjectMaskURL: subjectMaskURL,
            focusCrop: geometry.focusCrop,
            headAnchor: geometry.headAnchor,
            eyeAnchors: geometry.eyeAnchors,
            mouthRect: geometry.mouthRect,
            shoulderLine: geometry.shoulderLine,
            parallaxTuning: profile.parallaxTuning,
            lightingPreset: profile.lightingPreset,
            motionPreset: profile.motionPreset,
            generatedAt: .now,
            checksum: checksum
        )

        let metadataData = try JSONEncoder().encode(assets)
        try metadataData.write(to: metadataURL, options: .atomic)
        return assets
    }

    static func loadPreparedImages(from assets: PortraitDerivedAssets) throws -> PortraitPreparedImages {
        guard
            let backgroundPlate = UIImage(contentsOfFile: assets.backgroundPlateURL.path),
            let torsoPlate = UIImage(contentsOfFile: assets.torsoPlateURL.path),
            let headPlate = UIImage(contentsOfFile: assets.headPlateURL.path),
            let faceDetailOverlay = UIImage(contentsOfFile: assets.faceDetailOverlayURL.path),
            let eyeMask = UIImage(contentsOfFile: assets.eyeMaskURL.path),
            let mouthMask = UIImage(contentsOfFile: assets.mouthMaskURL.path),
            let featheredMatte = UIImage(contentsOfFile: assets.featheredMatteURL.path),
            let subjectMask = UIImage(contentsOfFile: assets.subjectMaskURL.path)
        else {
            throw PortraitAssetError.cannotLoadPreparedAsset("portrait plates")
        }

        return PortraitPreparedImages(
            backgroundPlate: backgroundPlate,
            torsoPlate: torsoPlate,
            headPlate: headPlate,
            faceDetailOverlay: faceDetailOverlay,
            eyeMask: eyeMask,
            mouthMask: mouthMask,
            featheredMatte: featheredMatte,
            subjectMask: subjectMask
        )
    }

    private static func resolveGeometry(
        profile: PortraitRenderProfile,
        handler: VNImageRequestHandler,
        imageSize: CGSize
    ) throws -> PortraitGeometry {
        let faceRequest = VNDetectFaceLandmarksRequest()
        try? handler.perform([faceRequest])

        guard let face = faceRequest.results?
            .sorted(by: { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height })
            .first else {
            let focusCrop = profile.focusCrop.clampedToUnitRect()
            let faceRect = CGRect(
                x: focusCrop.minX + focusCrop.width * 0.20,
                y: focusCrop.minY + focusCrop.height * 0.05,
                width: focusCrop.width * 0.60,
                height: focusCrop.height * 0.52
            ).clampedToUnitRect()
            let headRect = CGRect(
                x: faceRect.minX - 0.08,
                y: faceRect.minY - 0.10,
                width: faceRect.width + 0.16,
                height: faceRect.height + 0.18
            ).clampedToUnitRect()
            let torsoRect = CGRect(
                x: focusCrop.minX - 0.03,
                y: headRect.minY + headRect.height * 0.32,
                width: focusCrop.width + 0.06,
                height: focusCrop.maxY - (headRect.minY + headRect.height * 0.32)
            ).clampedToUnitRect()
            return PortraitGeometry(
                focusCrop: focusCrop,
                faceRect: faceRect,
                headRect: headRect,
                torsoRect: torsoRect,
                headAnchor: profile.headAnchor,
                eyeAnchors: profile.eyeAnchors,
                mouthRect: profile.mouthRect,
                shoulderLine: profile.shoulderLine
            )
        }

        let faceRect = normalizedTopLeftRect(fromVisionRect: face.boundingBox).clampedToUnitRect()
        let eyeAnchors = resolvedEyeAnchors(from: face, fallback: profile.eyeAnchors)
        let mouthRect = resolvedMouthRect(from: face, fallback: profile.mouthRect)
        let focusCrop = CGRect(
            x: faceRect.minX - faceRect.width * 0.34,
            y: faceRect.minY - faceRect.height * 0.30,
            width: faceRect.width * 1.68,
            height: faceRect.height * 2.18
        ).clampedToUnitRect()
        let headRect = CGRect(
            x: faceRect.minX - faceRect.width * 0.26,
            y: faceRect.minY - faceRect.height * 0.36,
            width: faceRect.width * 1.52,
            height: faceRect.height * 1.82
        ).clampedToUnitRect()
        let shoulderLine = min(0.94, faceRect.maxY + faceRect.height * 1.18)
        let torsoTop = min(0.92, faceRect.minY + faceRect.height * 0.72)
        let torsoRect = CGRect(
            x: focusCrop.minX - 0.03,
            y: torsoTop,
            width: focusCrop.width + 0.06,
            height: max(0.10, 1.0 - torsoTop)
        ).clampedToUnitRect()
        let headAnchor = CGPoint(x: faceRect.midX, y: faceRect.minY + faceRect.height * 0.34).clampedToUnit()

        return PortraitGeometry(
            focusCrop: focusCrop,
            faceRect: faceRect,
            headRect: headRect,
            torsoRect: torsoRect,
            headAnchor: headAnchor,
            eyeAnchors: eyeAnchors,
            mouthRect: mouthRect,
            shoulderLine: shoulderLine
        )
    }

    private static func resolvedEyeAnchors(from face: VNFaceObservation, fallback: [CGPoint]) -> [CGPoint] {
        let left = firstOrAverage(
            face.landmarks?.leftPupil,
            secondary: face.landmarks?.leftEye,
            in: face.boundingBox
        ) ?? fallback.first ?? CGPoint(x: 0.42, y: 0.31)
        let right = firstOrAverage(
            face.landmarks?.rightPupil,
            secondary: face.landmarks?.rightEye,
            in: face.boundingBox
        ) ?? fallback.dropFirst().first ?? CGPoint(x: 0.58, y: 0.31)
        return [left.clampedToUnit(), right.clampedToUnit()]
    }

    private static func resolvedMouthRect(from face: VNFaceObservation, fallback: CGRect) -> CGRect {
        let mouthPoints = regionPoints(face.landmarks?.outerLips, in: face.boundingBox)
        guard mouthPoints.isEmpty == false else { return fallback.clampedToUnitRect() }

        let xs = mouthPoints.map(\.x)
        let ys = mouthPoints.map(\.y)
        let rect = CGRect(
            x: (xs.min() ?? fallback.minX) - 0.02,
            y: (ys.min() ?? fallback.minY) - 0.02,
            width: ((xs.max() ?? fallback.maxX) - (xs.min() ?? fallback.minX)) + 0.04,
            height: ((ys.max() ?? fallback.maxY) - (ys.min() ?? fallback.minY)) + 0.06
        )
        return rect.clampedToUnitRect()
    }

    private static func generateSubjectMask(
        handler: VNImageRequestHandler,
        imageExtent: CGRect
    ) throws -> CIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        try? handler.perform([request])

        if let observation = request.results?.first {
            let maskImage = CIImage(cvPixelBuffer: observation.instanceMask)
            let scaleX = imageExtent.width / maskImage.extent.width
            let scaleY = imageExtent.height / maskImage.extent.height
            return maskImage
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .cropped(to: imageExtent)
        }

        return makeEllipseMask(
            size: imageExtent.size,
            normalizedRect: CGRect(x: 0.18, y: 0.05, width: 0.64, height: 0.88),
            feather: 22
        )
    }

    private static func masked(_ source: CIImage, with mask: CIImage, extent: CGRect) -> CIImage {
        let clear = CIImage(color: .clear).cropped(to: extent)
        return source
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: clear,
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: extent)
    }

    private static func combineMasks(_ first: CIImage, _ second: CIImage) -> CIImage {
        first
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: second
            ])
    }

    private static func inverted(_ image: CIImage, extent: CGRect) -> CIImage {
        image
            .applyingFilter("CIColorInvert")
            .cropped(to: extent)
    }

    private static func softenMask(_ image: CIImage, radius: CGFloat, extent: CGRect) -> CIImage {
        image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
    }

    private static func makeEllipseMask(size: CGSize, normalizedRect: CGRect, feather: CGFloat) -> CIImage {
        makeMaskImage(size: size, feather: feather) { context in
            context.fillEllipse(in: normalizedRect.toPixelRect(in: size))
        }
    }

    private static func makeRoundedRectMask(
        size: CGSize,
        normalizedRect: CGRect,
        cornerRatio: CGFloat,
        feather: CGFloat
    ) -> CIImage {
        makeMaskImage(size: size, feather: feather) { context in
            let rect = normalizedRect.toPixelRect(in: size)
            let radius = min(rect.width, rect.height) * cornerRatio
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
        }
    }

    private static func makeEyeMask(size: CGSize, normalizedPoints: [CGPoint], feather: CGFloat) -> CIImage {
        makeMaskImage(size: size, feather: feather) { context in
            for point in normalizedPoints.prefix(2) {
                let rect = CGRect(x: point.x - 0.06, y: point.y - 0.03, width: 0.12, height: 0.06)
                    .clampedToUnitRect()
                    .toPixelRect(in: size)
                context.fillEllipse(in: rect)
            }
        }
    }

    private static func makeMaskImage(
        size: CGSize,
        feather: CGFloat,
        draw: (CGContext) -> Void
    ) -> CIImage {
        let width = max(Int(size.width.rounded(.up)), 1)
        let height = max(Int(size.height.rounded(.up)), 1)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )

        guard let context else {
            return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(gray: 1, alpha: 1)
        draw(context)

        guard let cgImage = context.makeImage() else {
            return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        }

        let base = CIImage(cgImage: cgImage)
        guard feather > 0 else { return base }
        return base
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func writePNG(_ image: CIImage, to url: URL, extent: CGRect, name: String) throws {
        guard let cgImage = ciContext.createCGImage(image, from: extent) else {
            throw PortraitAssetError.cannotCreateDestination(name)
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PortraitAssetError.cannotCreateDestination(name)
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PortraitAssetError.cannotCreateDestination(name)
        }
    }

    private static func firstOrAverage(
        _ preferred: VNFaceLandmarkRegion2D?,
        secondary: VNFaceLandmarkRegion2D?,
        in faceBoundingBox: CGRect
    ) -> CGPoint? {
        if let preferredPoints = regionPoints(preferred, in: faceBoundingBox).first {
            return preferredPoints
        }
        let points = regionPoints(secondary, in: faceBoundingBox)
        guard points.isEmpty == false else { return nil }
        return CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )
    }

    private static func regionPoints(_ region: VNFaceLandmarkRegion2D?, in faceBoundingBox: CGRect) -> [CGPoint] {
        guard let region else { return [] }
        let pointer = region.normalizedPoints
        return (0..<region.pointCount).map { index in
            let point = pointer[index]
            return CGPoint(
                x: faceBoundingBox.minX + point.x * faceBoundingBox.width,
                y: (1 - faceBoundingBox.minY - faceBoundingBox.height) + (1 - point.y) * faceBoundingBox.height
            )
        }
    }

    private static func normalizedTopLeftRect(fromVisionRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: 1 - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

private extension SHA256Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension CGRect {
    func clampedToUnitRect() -> CGRect {
        let x = min(max(origin.x, 0), 1)
        let y = min(max(origin.y, 0), 1)
        let maxX = min(max(self.maxX, 0), 1)
        let maxY = min(max(self.maxY, 0), 1)
        return CGRect(x: x, y: y, width: max(0.02, maxX - x), height: max(0.02, maxY - y))
    }

    func toPixelRect(in size: CGSize) -> CGRect {
        CGRect(
            x: origin.x * size.width,
            y: origin.y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}

private extension CGPoint {
    func clampedToUnit() -> CGPoint {
        CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}
