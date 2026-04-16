import CoreGraphics
import Foundation

enum CharacterRenderRuntimeKind: String, Codable, Hashable, CaseIterable, Sendable {
    case photoPseudo3D
    case legacyFallback
}

struct PortraitParallaxTuning: Codable, Equatable, Hashable, Sendable {
    var backgroundDrift: CGFloat
    var torsoDrift: CGFloat
    var headDrift: CGFloat
    var mouthDepth: CGFloat
    var blinkDepth: CGFloat
}

struct PortraitRenderProfile: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    var sourceAssetName: String
    var cacheKey: String
    var focusCrop: CGRect
    var headAnchor: CGPoint
    var eyeAnchors: [CGPoint]
    var mouthRect: CGRect
    var shoulderLine: CGFloat
    var parallaxTuning: PortraitParallaxTuning
    var lightingPreset: String
    var motionPreset: String
}

struct PortraitDerivedAssets: Codable, Equatable, Hashable, Sendable {
    var backgroundPlateURL: URL
    var torsoPlateURL: URL
    var headPlateURL: URL
    var faceDetailOverlayURL: URL
    var eyeMaskURL: URL
    var mouthMaskURL: URL
    var featheredMatteURL: URL
    var subjectMaskURL: URL
    var focusCrop: CGRect
    var headAnchor: CGPoint
    var eyeAnchors: [CGPoint]
    var mouthRect: CGRect
    var shoulderLine: CGFloat
    var parallaxTuning: PortraitParallaxTuning
    var lightingPreset: String
    var motionPreset: String
    var generatedAt: Date
    var checksum: String
}

enum PortraitPreparationState: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case failed(String)
}
