import SwiftUI

@MainActor
final class CharacterPresentationStore: ObservableObject {
    struct Request: Equatable {
        var surfaceKind: CharacterSurfaceKind
        var characterID: String?
        var sceneID: String?
        var voiceBundleID: String?
        var visualStyle: VideoCallVisualStyle
        var showsBackdrop: Bool
        var prefersContinuousAnimation: Bool

        static let `default` = Request(
            surfaceKind: .homeHero,
            characterID: CharacterCatalog.flagship.id,
            sceneID: CharacterCatalog.flagship.defaultSceneID,
            voiceBundleID: VoiceCatalog.defaultBundle(
                for: CharacterCatalog.flagship.id,
                languageID: LanguageCatalog.english.id
            ).id,
            visualStyle: .natural,
            showsBackdrop: true,
            prefersContinuousAnimation: false
        )
    }

    struct Presentation: Equatable {
        var request: Request
        var continuitySnapshot: CharacterContinuitySnapshot
        var layoutSpec: CharacterStageLayoutSpec
        var character: CharacterProfile
        var characterBundle: CharacterBundle
        var scene: CharacterScene
        var portraitProfile: PortraitRenderProfile?
        var renderRuntimeKind: CharacterRenderRuntimeKind
        var usesPhotoRuntime: Bool
        var shouldShowBackdrop: Bool
        var prefersContinuousAnimation: Bool
    }

    struct StagePlacement: Equatable {
        var layoutSpec: CharacterStageLayoutSpec
        var stageSize: CGSize
        var topClearance: CGFloat
        var bottomClearance: CGFloat
        var verticalOffset: CGFloat
    }

    @Published private(set) var presentation: Presentation

    init(request: Request = .default) {
        presentation = Self.makePresentation(for: request)
    }

    func update(_ request: Request) {
        let resolved = Self.makePresentation(for: request)
        guard resolved != presentation else { return }
        presentation = resolved
    }

    static func resolvedSurfaceKind(
        explicit: CharacterSurfaceKind?,
        emphasis: AvatarEmphasis
    ) -> CharacterSurfaceKind {
        if let explicit {
            return explicit
        }

        switch emphasis {
        case .hero:
            return .callHero
        case .preview:
            return .quickStartPreview
        case .compact:
            return .homeHero
        }
    }

    static func stagePlacement(
        for surfaceKind: CharacterSurfaceKind,
        in containerSize: CGSize,
        safeAreaBottom: CGFloat = 0
    ) -> StagePlacement {
        let layoutSpec = surfaceKind.defaultLayoutSpec
        let stageSize = layoutSpec.stageSize(in: containerSize)
        let bottomClearance = max(
            CGFloat(layoutSpec.controlsInset(safeAreaBottom: safeAreaBottom)),
            containerSize.height - layoutSpec.subtitleBaseline(in: containerSize.height)
        )
        let topClearance = max(12, containerSize.height * 0.02)
        let verticalOffset = layoutSpec.verticalOffset(in: containerSize)

        return StagePlacement(
            layoutSpec: layoutSpec,
            stageSize: stageSize,
            topClearance: topClearance,
            bottomClearance: bottomClearance,
            verticalOffset: verticalOffset
        )
    }

    private static func makePresentation(for request: Request) -> Presentation {
        let normalizedCharacterID = CharacterCatalog.profile(for: request.characterID).id
        let character = CharacterCatalog.profile(for: normalizedCharacterID)
        let scene = CharacterCatalog.scene(for: request.sceneID, characterID: character.id)
        let bundle = CharacterCatalog.bundle(for: character.id)
        let resolvedVoiceBundleID = request.voiceBundleID
            ?? VoiceCatalog.defaultBundle(
                for: character.id,
                languageID: LanguageCatalog.english.id
            ).id
        let continuitySnapshot = CharacterContinuitySnapshot(
            surfaceKind: request.surfaceKind,
            characterID: character.id,
            sceneID: scene.id,
            voiceBundleID: resolvedVoiceBundleID,
            visualStyle: request.visualStyle
        )
        let portraitProfile = bundle.portraitProfileID.flatMap(CharacterCatalog.portraitProfile(for:))
        let usesPhotoRuntime = bundle.renderRuntimeKind == .photoPseudo3D && CharacterCatalog.primaryPortraitAvailable

        return Presentation(
            request: request,
            continuitySnapshot: continuitySnapshot,
            layoutSpec: request.surfaceKind.defaultLayoutSpec,
            character: character,
            characterBundle: bundle,
            scene: scene,
            portraitProfile: portraitProfile,
            renderRuntimeKind: bundle.renderRuntimeKind,
            usesPhotoRuntime: usesPhotoRuntime,
            shouldShowBackdrop: request.showsBackdrop,
            prefersContinuousAnimation: request.prefersContinuousAnimation || request.surfaceKind.prefersContinuousAnimation
        )
    }
}

enum AvatarEmphasis {
    case compact
    case preview
    case hero
}

struct MiraAvatarView: View {
    let state: AvatarState
    let audioLevel: Double
    var lipSyncFrame: LipSyncFrame = .neutral
    var emphasis: AvatarEmphasis = .compact
    var surfaceKind: CharacterSurfaceKind? = nil
    var characterID: String? = nil
    var sceneID: String? = nil
    var visualStyle: VideoCallVisualStyle = .natural
    var isAnimated: Bool? = nil
    var showsBackdrop: Bool = true

    var body: some View {
        CharacterStageView(
            state: state,
            audioLevel: audioLevel,
            lipSyncFrame: lipSyncFrame,
            emphasis: emphasis,
            surfaceKind: surfaceKind,
            characterID: characterID,
            sceneID: sceneID,
            visualStyle: visualStyle,
            isAnimated: isAnimated,
            showsBackdrop: showsBackdrop
        )
    }
}

struct CharacterStageSurface: View {
    let character: CharacterProfile
    let scene: CharacterScene
    var visualStyle: VideoCallVisualStyle = .natural
    var state: AvatarState = .idle
    var audioLevel: Double = 0.05
    var lipSyncFrame: LipSyncFrame = .neutral
    var emphasis: AvatarEmphasis = .preview
    var surfaceKind: CharacterSurfaceKind? = nil
    var size: CGSize
    var isAnimated: Bool = false
    var showsBackdrop: Bool = false
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0
    var shadowYOffset: CGFloat = 0
    var groundShadowWidth: CGFloat? = nil
    var groundShadowHeight: CGFloat = 14
    var groundShadowBlur: CGFloat = 10
    var verticalOffset: CGFloat = 0

    var body: some View {
        CharacterStageView(
            state: state,
            audioLevel: audioLevel,
            lipSyncFrame: lipSyncFrame,
            emphasis: emphasis,
            surfaceKind: surfaceKind,
            characterID: character.id,
            sceneID: scene.id,
            visualStyle: visualStyle,
            isAnimated: isAnimated,
            showsBackdrop: showsBackdrop
        )
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(alignment: .bottom) {
            if let groundShadowWidth {
                Capsule()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: groundShadowWidth, height: groundShadowHeight)
                    .blur(radius: groundShadowBlur)
                    .offset(y: 10)
            }
        }
        .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
        .offset(y: verticalOffset)
    }
}

struct CharacterCallHeroSurface: View {
    let character: CharacterProfile
    let scene: CharacterScene
    let visualStyle: VideoCallVisualStyle
    let state: AvatarState
    let audioLevel: Double
    let lipSyncFrame: LipSyncFrame
    let stageSize: CGSize
    let verticalOffset: CGFloat
    var isAnimated: Bool

    var body: some View {
        CharacterStageSurface(
            character: character,
            scene: scene,
            visualStyle: visualStyle,
            state: state,
            audioLevel: audioLevel,
            lipSyncFrame: lipSyncFrame,
            emphasis: .hero,
            surfaceKind: .callHero,
            size: stageSize,
            isAnimated: isAnimated,
            showsBackdrop: false,
            shadowColor: .black.opacity(0.26),
            shadowRadius: 42,
            shadowYOffset: 24,
            verticalOffset: verticalOffset
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
