import SwiftUI
import UIKit

@MainActor
final class CharacterSpeechDriver: ObservableObject {
    struct Input: Equatable {
        var sourceState: AvatarState
        var sourceAudioLevel: Double
        var sourceLipSyncFrame: LipSyncFrame
        var prefersContinuousAnimation: Bool
    }

    struct Output: Equatable {
        var avatarState: AvatarState
        var audioLevel: Double
        var lipSyncFrame: LipSyncFrame
    }

    @Published private(set) var output: Output

    private var lastInput: Input
    private var interruptedHoldFrame: LipSyncFrame?
    private var interruptedHoldUntil: Date?

    init(
        state: AvatarState = .idle,
        audioLevel: Double = 0,
        lipSyncFrame: LipSyncFrame = .neutral,
        prefersContinuousAnimation: Bool = false
    ) {
        let input = Input(
            sourceState: state,
            sourceAudioLevel: audioLevel,
            sourceLipSyncFrame: lipSyncFrame,
            prefersContinuousAnimation: prefersContinuousAnimation
        )
        lastInput = input
        output = Self.makeOutput(from: input, previous: nil, heldInterruptedFrame: nil)
    }

    func update(
        state: AvatarState,
        audioLevel: Double,
        lipSyncFrame: LipSyncFrame,
        prefersContinuousAnimation: Bool
    ) {
        let input = Input(
            sourceState: state,
            sourceAudioLevel: audioLevel,
            sourceLipSyncFrame: lipSyncFrame,
            prefersContinuousAnimation: prefersContinuousAnimation
        )
        guard input != lastInput else { return }

        if lastInput.sourceState == .speaking, input.sourceState == .interrupted {
            interruptedHoldFrame = Self.isNeutralFrame(output.lipSyncFrame) ? Self.normalized(lipSyncFrame) : output.lipSyncFrame
            interruptedHoldUntil = Date().addingTimeInterval(0.12)
        } else if input.sourceState != .interrupted {
            interruptedHoldFrame = nil
            interruptedHoldUntil = nil
        }

        let heldInterruptedFrame: LipSyncFrame?
        if let interruptedHoldUntil, interruptedHoldUntil > Date() {
            heldInterruptedFrame = interruptedHoldFrame
        } else {
            heldInterruptedFrame = nil
            interruptedHoldFrame = nil
            interruptedHoldUntil = nil
        }

        output = Self.makeOutput(from: input, previous: output, heldInterruptedFrame: heldInterruptedFrame)
        lastInput = input
    }

    private static func makeOutput(
        from input: Input,
        previous: Output?,
        heldInterruptedFrame: LipSyncFrame?
    ) -> Output {
        let targetAudio = quantizedAudioLevel(input.sourceAudioLevel)
        let renderedAudio: Double
        let renderedFrame: LipSyncFrame

        if input.prefersContinuousAnimation {
            let previousAudio = previous?.audioLevel ?? 0
            renderedAudio = smoothedAudioLevel(
                previous: previousAudio,
                target: targetAudio,
                state: input.sourceState
            )

            switch input.sourceState {
            case .speaking:
                let normalizedFrame = normalized(input.sourceLipSyncFrame)
                renderedFrame = isNeutralFrame(normalizedFrame)
                    ? synthesizedFrame(for: renderedAudio)
                    : normalizedFrame
            case .interrupted:
                renderedFrame = heldInterruptedFrame ?? softClosedFrame(reference: input.sourceLipSyncFrame)
            case .thinking, .idle, .listening, .error:
                renderedFrame = neutralFrame(reference: input.sourceLipSyncFrame)
            }
        } else {
            renderedAudio = staticSurfaceAudioLevel(for: input.sourceState, target: targetAudio)
            renderedFrame = neutralFrame(reference: input.sourceLipSyncFrame)
        }

        return Output(
            avatarState: input.sourceState,
            audioLevel: renderedAudio,
            lipSyncFrame: renderedFrame
        )
    }

    private static func quantizedAudioLevel(_ rawValue: Double) -> Double {
        let clamped = max(0, min(rawValue, 1))
        return (clamped * 20).rounded() / 20
    }

    private static func smoothedAudioLevel(
        previous: Double,
        target: Double,
        state: AvatarState
    ) -> Double {
        let gain: Double = target > previous ? 0.52 : 0.28
        var smoothed = previous + (target - previous) * gain

        switch state {
        case .speaking:
            smoothed = max(smoothed, max(0.08, target * 0.72))
        case .interrupted:
            smoothed = min(smoothed, max(0.04, target * 0.50))
        case .thinking, .listening, .idle, .error:
            if smoothed < 0.04 {
                smoothed = 0
            }
        }

        return quantizedAudioLevel(smoothed)
    }

    private static func staticSurfaceAudioLevel(for state: AvatarState, target: Double) -> Double {
        switch state {
        case .speaking:
            return max(0.18, target)
        case .thinking:
            return 0.06
        case .listening:
            return 0.04
        case .interrupted:
            return 0.03
        case .idle, .error:
            return 0
        }
    }

    private static func normalized(_ frame: LipSyncFrame) -> LipSyncFrame {
        LipSyncFrame(
            openness: max(0, min(frame.openness, 1)),
            width: max(0, min(frame.width, 1)),
            jawOffset: max(0, min(frame.jawOffset, 1)),
            cheekLift: max(0, min(frame.cheekLift, 1)),
            timestamp: frame.timestamp
        )
    }

    private static func synthesizedFrame(for audioLevel: Double) -> LipSyncFrame {
        let openness = max(0.10, min(audioLevel * 0.92, 0.78))
        return LipSyncFrame(
            openness: openness,
            width: min(0.62, 0.26 + openness * 0.42),
            jawOffset: openness * 0.64,
            cheekLift: openness * 0.16,
            timestamp: .now
        )
    }

    private static func softClosedFrame(reference: LipSyncFrame) -> LipSyncFrame {
        LipSyncFrame(
            openness: 0.06,
            width: 0.18,
            jawOffset: 0.04,
            cheekLift: 0.02,
            timestamp: reference.timestamp
        )
    }

    private static func neutralFrame(reference: LipSyncFrame) -> LipSyncFrame {
        LipSyncFrame(
            openness: 0,
            width: 0,
            jawOffset: 0,
            cheekLift: 0,
            timestamp: reference.timestamp
        )
    }

    private static func isNeutralFrame(_ frame: LipSyncFrame) -> Bool {
        abs(frame.openness) < 0.001
            && abs(frame.width) < 0.001
            && abs(frame.jawOffset) < 0.001
            && abs(frame.cheekLift) < 0.001
    }
}

struct CharacterStageView: View {
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

    @EnvironmentObject private var performanceGovernor: PerformanceGovernor
    @StateObject private var presentationStore: CharacterPresentationStore
    @StateObject private var portraitRuntime = PortraitCharacterRuntime()
    @StateObject private var speechDriver: CharacterSpeechDriver
    @State private var lockedPreparedAvailability: Bool?
    @State private var staticSurfaceDate: Date

    init(
        state: AvatarState,
        audioLevel: Double,
        lipSyncFrame: LipSyncFrame = .neutral,
        emphasis: AvatarEmphasis = .compact,
        surfaceKind: CharacterSurfaceKind? = nil,
        characterID: String? = nil,
        sceneID: String? = nil,
        visualStyle: VideoCallVisualStyle = .natural,
        isAnimated: Bool? = nil,
        showsBackdrop: Bool = true
    ) {
        self.state = state
        self.audioLevel = audioLevel
        self.lipSyncFrame = lipSyncFrame
        self.emphasis = emphasis
        self.surfaceKind = surfaceKind
        self.characterID = characterID
        self.sceneID = sceneID
        self.visualStyle = visualStyle
        self.isAnimated = isAnimated
        self.showsBackdrop = showsBackdrop

        let prefersContinuousAnimation = isAnimated ?? (emphasis == .hero)
        let request = CharacterPresentationStore.Request(
            surfaceKind: CharacterPresentationStore.resolvedSurfaceKind(
                explicit: surfaceKind,
                emphasis: emphasis
            ),
            characterID: characterID,
            sceneID: sceneID,
            voiceBundleID: nil,
            visualStyle: visualStyle,
            showsBackdrop: showsBackdrop,
            prefersContinuousAnimation: prefersContinuousAnimation
        )

        _presentationStore = StateObject(wrappedValue: CharacterPresentationStore(request: request))
        _speechDriver = StateObject(
            wrappedValue: CharacterSpeechDriver(
                state: state,
                audioLevel: audioLevel,
                lipSyncFrame: lipSyncFrame,
                prefersContinuousAnimation: prefersContinuousAnimation
            )
        )
        _staticSurfaceDate = State(initialValue: .now)
    }

    private var shouldAnimate: Bool {
        isAnimated ?? (emphasis == .hero)
    }

    private var effectiveShouldAnimate: Bool {
        shouldAnimate && performanceGovernor.profile.allowsContinuousHeroAnimation
    }

    private var animationInterval: TimeInterval {
        let targetFPS = max(performanceGovernor.profile.callHeroFrameRate, 1)
        return 1.0 / targetFPS
    }

    private var presentationRequest: CharacterPresentationStore.Request {
        CharacterPresentationStore.Request(
            surfaceKind: CharacterPresentationStore.resolvedSurfaceKind(
                explicit: surfaceKind,
                emphasis: emphasis
            ),
            characterID: characterID,
            sceneID: sceneID,
            voiceBundleID: nil,
            visualStyle: visualStyle,
            showsBackdrop: showsBackdrop,
            prefersContinuousAnimation: effectiveShouldAnimate
        )
    }

    private var speechInput: CharacterSpeechDriver.Input {
        CharacterSpeechDriver.Input(
            sourceState: state,
            sourceAudioLevel: audioLevel,
            sourceLipSyncFrame: lipSyncFrame,
            prefersContinuousAnimation: effectiveShouldAnimate
        )
    }

    private var presentation: CharacterPresentationStore.Presentation {
        presentationStore.presentation
    }

    private var usesPhotoRuntime: Bool {
        presentation.usesPhotoRuntime
    }

    private var isCallHeroSurface: Bool {
        presentation.continuitySnapshot.surfaceKind == .callHero
    }

    var body: some View {
        GeometryReader { proxy in
            if effectiveShouldAnimate {
                TimelineView(.animation(minimumInterval: animationInterval)) { timeline in
                    renderedStage(size: proxy.size, date: timeline.date)
                }
            } else {
                renderedStage(size: proxy.size, date: staticSurfaceDate)
            }
        }
        .task(id: presentationRequest) {
            presentationStore.update(presentationRequest)

            guard usesPhotoRuntime else {
                lockedPreparedAvailability = nil
                return
            }
            // Keep a single renderer path for the lifetime of this surface to avoid
            // jumping between static/photo-prepared compositions after the view appears.
            let hasPreparedSnapshot = PortraitCharacterRuntime.cachedPreparedSnapshot(for: presentation.characterBundle) != nil
            lockedPreparedAvailability = hasPreparedSnapshot

            // Preview surfaces stay lightweight and static. Only the animated call hero
            // actively prepares layered assets; previews can still reuse any shared cache.
            if presentation.prefersContinuousAnimation {
                await portraitRuntime.prepareIfNeeded(bundle: presentation.characterBundle)
            }
        }
        .onAppear {
            speechDriver.update(
                state: speechInput.sourceState,
                audioLevel: speechInput.sourceAudioLevel,
                lipSyncFrame: speechInput.sourceLipSyncFrame,
                prefersContinuousAnimation: speechInput.prefersContinuousAnimation
            )
        }
        .onChange(of: speechInput) { _, newValue in
            speechDriver.update(
                state: newValue.sourceState,
                audioLevel: newValue.sourceAudioLevel,
                lipSyncFrame: newValue.sourceLipSyncFrame,
                prefersContinuousAnimation: newValue.prefersContinuousAnimation
            )
        }
    }

    private var badgeText: String? {
        switch speechDriver.output.avatarState {
        case .interrupted:
            return "Interrupted"
        case .error:
            return "Resetting"
        case .listening:
            return emphasis == .hero ? "Listening" : nil
        case .thinking:
            return emphasis == .hero ? "Thinking" : nil
        case .speaking, .idle:
            return nil
        }
    }

    @ViewBuilder
    private func renderedStage(size: CGSize, date: Date) -> some View {
        let metrics = CharacterStageMetrics(size: size, emphasis: emphasis)
        let palette = PhotoStagePalette.forScene(
            presentation.scene,
            characterID: presentation.character.id,
            visualStyle: presentation.continuitySnapshot.visualStyle
        )
        let pose = CharacterStagePose(
            time: date.timeIntervalSinceReferenceDate,
            state: speechDriver.output.avatarState,
            audioLevel: speechDriver.output.audioLevel,
            lipSyncFrame: speechDriver.output.lipSyncFrame
        )
        let portraitProfile = usesPhotoRuntime ? presentation.portraitProfile : nil
        let cachedPreparedSnapshot = usesPhotoRuntime
            ? PortraitCharacterRuntime.cachedPreparedSnapshot(for: presentation.characterBundle)
            : nil
        let preparedRendererAllowed = lockedPreparedAvailability ?? (cachedPreparedSnapshot != nil)
        let portraitImage = usesPhotoRuntime
            ? (portraitRuntime.image ?? PortraitCharacterRuntime.previewImage(for: presentation.characterBundle))
            : nil
        let preparedImages = usesPhotoRuntime && preparedRendererAllowed
            ? (portraitRuntime.preparedImages ?? cachedPreparedSnapshot?.preparedImages)
            : nil
        let derivedAssets = usesPhotoRuntime && preparedRendererAllowed
            ? (portraitRuntime.derivedAssets ?? cachedPreparedSnapshot?.derivedAssets)
            : nil
        let focusCrop = derivedAssets?.focusCrop
            ?? (usesPhotoRuntime ? portraitRuntime.focusCrop : CGRect(x: 0.20, y: 0.10, width: 0.60, height: 0.74))
        let effectivePreparationState = usesPhotoRuntime && derivedAssets != nil
            ? PortraitPreparationState.ready
            : portraitRuntime.preparationState
        let prefersStaticPreparingCard = performanceGovernor.profile.prefersStaticPreparingCard
        let reducesBackdropEffects = performanceGovernor.profile.reducesBackdropEffects

        ZStack {
            if presentation.shouldShowBackdrop {
                PhotoSceneBackdrop(
                    image: preparedImages?.backgroundPlate ?? portraitImage,
                    scene: presentation.scene,
                    palette: palette,
                    metrics: metrics,
                    pose: pose,
                    reduceEffects: reducesBackdropEffects
                )
            }

            if isCallHeroSurface, let preparedImages, let derivedAssets {
                PreparedPhotoPseudo3DPortrait(
                    images: preparedImages,
                    derivedAssets: derivedAssets,
                    scene: presentation.scene,
                    palette: palette,
                    pose: pose,
                    metrics: metrics,
                    state: speechDriver.output.avatarState
                )
                    .scaleEffect(metrics.scale, anchor: .center)
                    .offset(y: metrics.verticalOffset)
            } else if let image = portraitImage {
                if isCallHeroSurface == false {
                    StaticPhotoPortraitCard(
                        image: image,
                        portraitProfile: portraitProfile,
                        focusRect: focusCrop,
                        palette: palette,
                        pose: pose,
                        metrics: metrics,
                        state: speechDriver.output.avatarState
                    )
                        .scaleEffect(metrics.scale, anchor: .center)
                        .offset(y: metrics.verticalOffset)
                } else if case .failed = effectivePreparationState {
                    StaticPhotoPortraitCard(
                        image: image,
                        portraitProfile: portraitProfile,
                        focusRect: focusCrop,
                        palette: palette,
                        pose: pose,
                        metrics: metrics,
                        state: speechDriver.output.avatarState
                    )
                        .scaleEffect(metrics.scale, anchor: .center)
                        .offset(y: metrics.verticalOffset)
                } else if prefersStaticPreparingCard, effectivePreparationState != .ready {
                    StaticPhotoPortraitCard(
                        image: image,
                        portraitProfile: portraitProfile,
                        focusRect: focusCrop,
                        palette: palette,
                        pose: pose,
                        metrics: metrics,
                        state: speechDriver.output.avatarState
                    )
                        .scaleEffect(metrics.scale, anchor: .center)
                        .offset(y: metrics.verticalOffset)
                } else {
                    PhotoPseudo3DPortrait(
                        image: image,
                        portraitProfile: portraitProfile,
                        focusRect: focusCrop,
                        scene: presentation.scene,
                        palette: palette,
                        pose: pose,
                        metrics: metrics,
                        state: speechDriver.output.avatarState
                    )
                        .scaleEffect(metrics.scale, anchor: .center)
                        .offset(y: metrics.verticalOffset)
                }
            } else {
                PhotoFallbackStage(
                    characterID: presentation.character.id,
                    palette: palette,
                    metrics: metrics,
                    pose: pose,
                    state: speechDriver.output.avatarState
                )
                    .scaleEffect(metrics.scale, anchor: .center)
                    .offset(y: metrics.verticalOffset)
            }

            if speechDriver.output.avatarState == .thinking {
                ThinkingHalo(color: palette.accent, metrics: metrics, pose: pose)
                    .scaleEffect(metrics.scale, anchor: .center)
                    .offset(y: metrics.verticalOffset)
            }

            if let badge = badgeText {
                StageBadge(text: badge, palette: palette)
                    .padding(.top, emphasis == .hero ? 18 : 12)
                    .padding(.horizontal, emphasis == .hero ? 18 : 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

private struct CharacterStageMetrics {
    let size: CGSize
    let emphasis: AvatarEmphasis
    let canvasSize: CGSize
    let portraitSize: CGSize
    let scale: CGFloat
    let verticalOffset: CGFloat
    let cornerRadius: CGFloat
    let portraitCornerRadius: CGFloat

    init(size: CGSize, emphasis: AvatarEmphasis) {
        self.size = size
        self.emphasis = emphasis

        switch emphasis {
        case .hero:
            canvasSize = CGSize(width: 340, height: 500)
            portraitSize = CGSize(width: 270, height: 392)
            cornerRadius = 46
            portraitCornerRadius = 42
            verticalOffset = -2
        case .preview:
            canvasSize = CGSize(width: 210, height: 250)
            portraitSize = CGSize(width: 138, height: 178)
            cornerRadius = 24
            portraitCornerRadius = 22
            verticalOffset = 0
        case .compact:
            canvasSize = CGSize(width: 250, height: 320)
            portraitSize = CGSize(width: 166, height: 214)
            cornerRadius = 28
            portraitCornerRadius = 24
            verticalOffset = 2
        }

        scale = min(size.width / canvasSize.width, size.height / canvasSize.height)
    }
}

private struct CharacterStagePose {
    let breathing: CGFloat
    let swayX: CGFloat
    let swayY: CGFloat
    let tilt: Angle
    let perspectiveX: CGFloat
    let perspectiveY: CGFloat
    let mouthPulse: CGFloat
    let glow: CGFloat
    let shimmer: CGFloat
    let blink: CGFloat
    let gazeX: CGFloat
    let gazeY: CGFloat
    let smile: CGFloat

    init(time: TimeInterval, state: AvatarState, audioLevel: Double, lipSyncFrame: LipSyncFrame) {
        let t = CGFloat(time)
        let audio = max(0, min(CGFloat(audioLevel), 1))
        let breathingWave = sin(t * 1.2)
        let idleDrift = sin(t * 0.65)
        let verticalDrift = cos(t * 0.53)
        let speechCadence = (sin(t * 17.0) + 1) * 0.5
        let blinkDriver = sin(t * 0.84 + 0.7)
        let lipOpenness = max(0, min(CGFloat(lipSyncFrame.openness), 1))
        let lipWidth = max(0, min(CGFloat(lipSyncFrame.width), 1))
        let jawOffset = max(0, min(CGFloat(lipSyncFrame.jawOffset), 1))
        let cheekLift = max(0, min(CGFloat(lipSyncFrame.cheekLift), 1))

        var swayX = idleDrift * 5
        var swayY = verticalDrift * 4
        var tilt = Angle.degrees(Double(sin(t * 0.55) * 1.8))
        var perspectiveX = idleDrift * 3.4
        var perspectiveY = verticalDrift * 2.2
        var mouthPulse = max(audio, max(lipOpenness, CGFloat(speechCadence) * 0.12))
        var glow: CGFloat = 0.16
        var shimmer: CGFloat = (sin(t * 0.8) + 1) * 0.5
        var blink: CGFloat = 1.0
        var gazeX = idleDrift * 2.2
        var gazeY = verticalDrift * 1.3
        var smile: CGFloat = 0.20 + cheekLift * 0.14

        switch state {
        case .idle:
            break
        case .listening:
            swayY -= 7
            tilt = .degrees(-2.6)
            perspectiveY = -4
            glow = 0.22
            gazeX = -2.6
            gazeY = -1.4
            smile = 0.28
        case .thinking:
            swayX += 8
            swayY -= 4
            tilt = .degrees(4.8)
            perspectiveX += 7
            perspectiveY -= 6
            glow = 0.28
            gazeX = 3.4
            gazeY = -2.2
            smile = 0.12
        case .speaking:
            swayY -= 3
            tilt = .degrees(Double(sin(t * 2.1) * 2.8))
            perspectiveX *= 0.7
            perspectiveY = -1.4
            mouthPulse = max(audio, max(lipOpenness * 1.05, CGFloat(speechCadence) * 0.9))
            glow = 0.32
            shimmer = (sin(t * 2.6) + 1) * 0.5
            gazeX *= 0.7 + lipWidth * 0.05
            gazeY = -0.3
            smile = 0.24 + cheekLift * 0.30
        case .interrupted:
            swayX -= 5
            tilt = .degrees(-5.2)
            perspectiveX = -5.5
            perspectiveY = -0.8
            mouthPulse = max(0.04, lipOpenness * 0.3)
            glow = 0.18
            gazeX = -4
            gazeY = 0.4
            smile = 0.06
        case .error:
            swayX = 0
            swayY = 2
            tilt = .degrees(-0.8)
            perspectiveX = 0
            perspectiveY = 1
            mouthPulse = 0.03
            glow = 0.12
            gazeX = 0
            gazeY = 1.4
            smile = 0.02
        }

        if blinkDriver > 0.92 {
            blink = 0.16
        }
        if blinkDriver > 0.985 {
            blink = 0.04
        }

        breathing = breathingWave
        self.swayX = swayX
        self.swayY = swayY - breathingWave * 2.4 + jawOffset * 0.8
        self.tilt = tilt
        self.perspectiveX = perspectiveX
        self.perspectiveY = perspectiveY
        self.mouthPulse = mouthPulse
        self.glow = glow + sin(t * 1.6) * 0.03
        self.shimmer = shimmer
        self.blink = blink
        self.gazeX = gazeX
        self.gazeY = gazeY
        self.smile = smile
    }
}

private struct PhotoStagePalette {
    let top: Color
    let bottom: Color
    let ambient: Color
    let accent: Color
    let frame: Color
    let frameShadow: Color
    let backdropImageOpacity: Double
    let backdropBlur: CGFloat
    let portraitSaturation: Double
    let portraitContrast: Double
    let highlightOpacity: Double
    let shadowOpacity: Double
    let glowMultiplier: CGFloat

    static func forScene(_ scene: CharacterScene, characterID: String, visualStyle: VideoCallVisualStyle) -> PhotoStagePalette {
        switch (scene.id, visualStyle) {
        case ("study", .cinematic):
            return PhotoStagePalette(
                top: Color(red: 0.09, green: 0.10, blue: 0.14),
                bottom: Color(red: 0.18, green: 0.15, blue: 0.14),
                ambient: Color(red: 0.72, green: 0.66, blue: 0.56),
                accent: Color(red: 0.83, green: 0.58, blue: 0.36),
                frame: Color.white.opacity(0.12),
                frameShadow: Color.black.opacity(0.36),
                backdropImageOpacity: 0.76,
                backdropBlur: 18,
                portraitSaturation: 1.02,
                portraitContrast: 1.16,
                highlightOpacity: 0.12,
                shadowOpacity: 0.30,
                glowMultiplier: 0.82
            )
        case ("study", .softFocus):
            return PhotoStagePalette(
                top: Color(red: 0.18, green: 0.17, blue: 0.18),
                bottom: Color(red: 0.30, green: 0.25, blue: 0.22),
                ambient: Color(red: 0.95, green: 0.84, blue: 0.74),
                accent: Color(red: 0.92, green: 0.70, blue: 0.52),
                frame: Color.white.opacity(0.18),
                frameShadow: Color.black.opacity(0.16),
                backdropImageOpacity: 0.62,
                backdropBlur: 30,
                portraitSaturation: 1.10,
                portraitContrast: 1.00,
                highlightOpacity: 0.24,
                shadowOpacity: 0.16,
                glowMultiplier: 1.24
            )
        case ("study", _):
            return PhotoStagePalette(
                top: Color(red: 0.13, green: 0.14, blue: 0.18),
                bottom: Color(red: 0.22, green: 0.20, blue: 0.18),
                ambient: Color(red: 0.80, green: 0.76, blue: 0.66),
                accent: Color(red: 0.80, green: 0.63, blue: 0.42),
                frame: Color.white.opacity(0.18),
                frameShadow: Color.black.opacity(0.28),
                backdropImageOpacity: 0.58,
                backdropBlur: 24,
                portraitSaturation: 1.06,
                portraitContrast: 1.06,
                highlightOpacity: 0.18,
                shadowOpacity: 0.22,
                glowMultiplier: 1.0
            )
        case ("nightcity", .cinematic):
            return PhotoStagePalette(
                top: Color(red: 0.05, green: 0.07, blue: 0.15),
                bottom: Color(red: 0.10, green: 0.06, blue: 0.15),
                ambient: Color(red: 0.41, green: 0.58, blue: 0.94),
                accent: Color(red: 0.99, green: 0.62, blue: 0.31),
                frame: Color.white.opacity(0.10),
                frameShadow: Color.black.opacity(0.40),
                backdropImageOpacity: 0.82,
                backdropBlur: 16,
                portraitSaturation: 1.00,
                portraitContrast: 1.18,
                highlightOpacity: 0.11,
                shadowOpacity: 0.32,
                glowMultiplier: 0.78
            )
        case ("nightcity", .softFocus):
            return PhotoStagePalette(
                top: Color(red: 0.11, green: 0.12, blue: 0.20),
                bottom: Color(red: 0.18, green: 0.12, blue: 0.20),
                ambient: Color(red: 0.67, green: 0.76, blue: 0.98),
                accent: Color(red: 0.98, green: 0.73, blue: 0.46),
                frame: Color.white.opacity(0.17),
                frameShadow: Color.black.opacity(0.18),
                backdropImageOpacity: 0.66,
                backdropBlur: 28,
                portraitSaturation: 1.08,
                portraitContrast: 1.00,
                highlightOpacity: 0.22,
                shadowOpacity: 0.18,
                glowMultiplier: 1.20
            )
        case ("nightcity", _):
            return PhotoStagePalette(
                top: Color(red: 0.08, green: 0.10, blue: 0.18),
                bottom: Color(red: 0.12, green: 0.09, blue: 0.16),
                ambient: Color(red: 0.47, green: 0.64, blue: 0.95),
                accent: Color(red: 0.97, green: 0.67, blue: 0.36),
                frame: Color.white.opacity(0.16),
                frameShadow: Color.black.opacity(0.32),
                backdropImageOpacity: 0.60,
                backdropBlur: 24,
                portraitSaturation: 1.06,
                portraitContrast: 1.08,
                highlightOpacity: 0.17,
                shadowOpacity: 0.24,
                glowMultiplier: 1.0
            )
        case (_, .cinematic):
            return PhotoStagePalette(
                top: Color(red: 0.08, green: 0.10, blue: 0.16),
                bottom: Color(red: 0.18, green: 0.12, blue: 0.12),
                ambient: Color(red: 0.92, green: 0.72, blue: 0.49),
                accent: Color(red: 0.95, green: 0.60, blue: 0.34),
                frame: Color.white.opacity(0.12),
                frameShadow: Color.black.opacity(0.38),
                backdropImageOpacity: 0.78,
                backdropBlur: 18,
                portraitSaturation: 1.00,
                portraitContrast: 1.18,
                highlightOpacity: 0.12,
                shadowOpacity: 0.30,
                glowMultiplier: 0.84
            )
        case (_, .softFocus):
            return PhotoStagePalette(
                top: Color(red: 0.18, green: 0.19, blue: 0.24),
                bottom: Color(red: 0.34, green: 0.22, blue: 0.18),
                ambient: Color(red: 1.00, green: 0.84, blue: 0.66),
                accent: Color(red: 1.0, green: 0.76, blue: 0.58),
                frame: Color.white.opacity(0.18),
                frameShadow: Color.black.opacity(0.18),
                backdropImageOpacity: 0.64,
                backdropBlur: 30,
                portraitSaturation: 1.10,
                portraitContrast: 1.00,
                highlightOpacity: 0.24,
                shadowOpacity: 0.18,
                glowMultiplier: 1.24
            )
        default:
            return PhotoStagePalette(
                top: Color(red: 0.12, green: 0.15, blue: 0.21),
                bottom: Color(red: 0.22, green: 0.17, blue: 0.16),
                ambient: Color(red: 0.98, green: 0.80, blue: 0.58),
                accent: Color(red: 1.0, green: 0.69, blue: 0.47),
                frame: Color.white.opacity(0.18),
                frameShadow: Color.black.opacity(0.30),
                backdropImageOpacity: 0.60,
                backdropBlur: 24,
                portraitSaturation: 1.06,
                portraitContrast: 1.06,
                highlightOpacity: 0.18,
                shadowOpacity: 0.22,
                glowMultiplier: 1.0
            )
        }
    }
}

private struct PreparedPhotoPseudo3DPortrait: View {
    let images: PortraitPreparedImages
    let derivedAssets: PortraitDerivedAssets
    let scene: CharacterScene
    let palette: PhotoStagePalette
    let pose: CharacterStagePose
    let metrics: CharacterStageMetrics
    let state: AvatarState

    private var portraitShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.portraitCornerRadius, style: .continuous)
    }

    private struct PlatePlacement {
        let xShift: CGFloat
        let yShift: CGFloat
        let extraScale: CGFloat
    }

    private var tuning: PortraitParallaxTuning {
        derivedAssets.parallaxTuning
    }

    private var isHero: Bool {
        metrics.emphasis == .hero
    }

    private var motionDamping: CGFloat {
        derivedAssets.motionPreset.contains("natural") ? 0.86 : 1.0
    }

    private var keylightTint: Color {
        derivedAssets.lightingPreset.contains("daylight")
            ? Color(red: 1.00, green: 0.97, blue: 0.92)
            : Color.white
    }

    private var shadowTint: Color {
        derivedAssets.lightingPreset.contains("daylight")
            ? Color(red: 0.20, green: 0.14, blue: 0.12)
            : Color.black
    }

    private var torsoPlacement: PlatePlacement {
        PlatePlacement(
            xShift: (-pose.perspectiveX * 1.15 * tuning.torsoDrift - pose.gazeX * 0.10) * motionDamping,
            yShift: (isHero ? 10 : 8) + (pose.perspectiveY * 0.42 + pose.breathing * 0.78) * motionDamping,
            extraScale: isHero ? 0.05 : 0.08
        )
    }

    private var headPlacement: PlatePlacement {
        PlatePlacement(
            xShift: ((pose.perspectiveX * 0.92) + (pose.gazeX * 0.18)) * tuning.headDrift * motionDamping,
            yShift: (pose.perspectiveY * 0.46 - pose.breathing * 0.14) * motionDamping,
            extraScale: isHero ? 0.06 : 0.08
        )
    }

    private var detailPlacement: PlatePlacement {
        PlatePlacement(
            xShift: headPlacement.xShift * 1.02,
            yShift: headPlacement.yShift * 1.04,
            extraScale: headPlacement.extraScale
        )
    }

    private var mouthPlacement: PlatePlacement {
        PlatePlacement(
            xShift: headPlacement.xShift * 0.98 + pose.gazeX * 0.04,
            yShift: headPlacement.yShift + pose.mouthPulse * 1.08 * tuning.mouthDepth,
            extraScale: headPlacement.extraScale
        )
    }

    private var eyePlacement: PlatePlacement {
        PlatePlacement(
            xShift: headPlacement.xShift * 0.94 + pose.gazeX * 0.08 * tuning.blinkDepth,
            yShift: headPlacement.yShift * 0.92 + pose.gazeY * 0.08 * tuning.blinkDepth,
            extraScale: headPlacement.extraScale
        )
    }

    var body: some View {
        Group {
            if isHero {
                heroPortrait
            } else {
                compactPortrait
            }
        }
    }

    private var compactPortrait: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.portraitCornerRadius + 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .frame(width: metrics.portraitSize.width + 18, height: metrics.portraitSize.height + 20)
                .blur(radius: 10)
                .offset(x: pose.swayX * 0.50, y: 24)

            portraitCard
                .frame(width: metrics.portraitSize.width, height: metrics.portraitSize.height)
                .rotation3DEffect(.degrees(Double(pose.perspectiveY)), axis: (x: 1, y: 0, z: 0), perspective: 0.75)
                .rotation3DEffect(.degrees(Double(-pose.perspectiveX)), axis: (x: 0, y: 1, z: 0), perspective: 0.75)
                .rotationEffect(pose.tilt)
                .offset(x: pose.swayX, y: pose.swayY + pose.breathing * 1.3)

            glassReflection
                .frame(width: metrics.portraitSize.width, height: metrics.portraitSize.height)
                .rotation3DEffect(.degrees(Double(pose.perspectiveY)), axis: (x: 1, y: 0, z: 0), perspective: 0.75)
                .rotation3DEffect(.degrees(Double(-pose.perspectiveX)), axis: (x: 0, y: 1, z: 0), perspective: 0.75)
                .rotationEffect(pose.tilt)
                .offset(x: pose.swayX, y: pose.swayY + pose.breathing * 1.3)
                .blendMode(.screen)
                .allowsHitTesting(false)
        }
    }

    private var heroPortrait: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.20))
                .frame(width: metrics.portraitSize.width * 0.72, height: 44)
                .blur(radius: 20)
                .offset(y: metrics.portraitSize.height * 0.47)

            portraitCard
                .frame(width: metrics.portraitSize.width, height: metrics.portraitSize.height)
                .rotation3DEffect(.degrees(Double(pose.perspectiveY * 0.58)), axis: (x: 1, y: 0, z: 0), perspective: 0.82)
                .rotation3DEffect(.degrees(Double(-pose.perspectiveX * 0.76)), axis: (x: 0, y: 1, z: 0), perspective: 0.82)
                .rotationEffect(.degrees(pose.tilt.degrees * 0.42))
                .offset(x: pose.swayX * 0.68, y: pose.swayY * 0.54 + pose.breathing * 1.1)
        }
    }

    private var portraitCard: some View {
        ZStack {
            portraitShape
                .fill(Color.black.opacity(isHero ? 0.08 : 0.16))

            ZStack {
                plateImage(images.torsoPlate, opacity: isHero ? 0.76 : 0.84, placement: torsoPlacement)
                plateImage(images.headPlate, opacity: 1.0, placement: headPlacement)
                plateImage(images.faceDetailOverlay, opacity: isHero ? 0.24 : 0.20, placement: detailPlacement)
                    .blendMode(.screen)

                facialDepthLayer
                mouthMotionLayer
                cheekMotionLayer
                blinkShadowLayer
                eyeCatchlightLayer
                portraitLighting

                LinearGradient(
                    colors: [
                        keylightTint.opacity(isHero ? 0.08 : 0.05),
                        .clear,
                        shadowTint.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if isHero {
                    Rectangle()
                        .fill(keylightTint.opacity(0.10))
                        .frame(width: metrics.portraitSize.width * 0.18)
                        .blur(radius: 18)
                        .rotationEffect(.degrees(-17))
                        .offset(x: metrics.portraitSize.width * 0.18, y: -metrics.portraitSize.height * 0.18)
                        .clipShape(portraitShape)
                        .blendMode(.screen)
                }
            }
            .clipShape(portraitShape)

            portraitShape
                .stroke(isHero ? Color.white.opacity(0.14) : palette.frame, lineWidth: 1)
                .shadow(color: palette.frameShadow, radius: 26, y: 18)

            portraitShape
                .stroke(Color.white.opacity(0.06), lineWidth: 6)
                .blur(radius: 12)
                .opacity(0.62)
        }
    }

    private func plateImage(
        _ image: UIImage,
        opacity: Double,
        placement: PlatePlacement
    ) -> some View {
        let size = metrics.portraitSize
        let imageScale: CGFloat = (isHero ? 0.90 : 1.12) + placement.extraScale
        let focusX = ((derivedAssets.focusCrop.midX - 0.5) * size.width * (isHero ? 0.22 : 0.30))
        let focusY = ((derivedAssets.focusCrop.midY - (isHero ? 0.35 : 0.42)) * size.height * (isHero ? 0.24 : 0.34))

        return Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size.width * imageScale, height: size.height * imageScale)
            .saturation(state == .error ? 0.76 : palette.portraitSaturation)
            .contrast(palette.portraitContrast)
            .opacity(opacity)
            .offset(
                x: -focusX + placement.xShift,
                y: -focusY + placement.yShift - size.height * (isHero ? 0.19 : 0.05)
            )
    }

    private var facialDepthLayer: some View {
        ZStack {
            shadowTint.opacity(state == .speaking ? 0.18 : 0.12)
                .blur(radius: isHero ? 22 : 14)
                .offset(x: headPlacement.xShift * 0.14 + 6, y: headPlacement.yShift + (isHero ? 12 : 8))
                .mask(plateImage(images.headPlate, opacity: 1, placement: headPlacement))
                .blendMode(.multiply)

            RadialGradient(
                colors: [
                    keylightTint.opacity(0.14 + Double(pose.shimmer) * 0.06),
                    .clear
                ],
                center: UnitPoint(
                    x: derivedAssets.headAnchor.x + pose.gazeX * 0.002,
                    y: max(0.16, derivedAssets.headAnchor.y + 0.02)
                ),
                startRadius: 4,
                endRadius: metrics.portraitSize.width * (isHero ? 0.30 : 0.24)
            )
            .mask(plateImage(images.faceDetailOverlay, opacity: 1, placement: detailPlacement))
            .blendMode(.screen)
        }
    }

    private var mouthMotionLayer: some View {
        plateImage(
            images.headPlate,
            opacity: state == .speaking ? 0.30 : 0.10,
            placement: mouthPlacement
        )
        .scaleEffect(
            x: 1 + pose.mouthPulse * 0.010 * tuning.mouthDepth,
            y: 1 + pose.mouthPulse * 0.060 * tuning.mouthDepth,
            anchor: UnitPoint(x: derivedAssets.mouthRect.midX, y: max(0.02, derivedAssets.mouthRect.minY - 0.02))
        )
        .mask(
            plateImage(
                images.mouthMask,
                opacity: 1,
                placement: PlatePlacement(
                    xShift: mouthPlacement.xShift,
                    yShift: mouthPlacement.yShift,
                    extraScale: mouthPlacement.extraScale
                )
            )
        )
    }

    private var cheekMotionLayer: some View {
        plateImage(
            images.faceDetailOverlay,
            opacity: state == .speaking ? 0.16 : 0.05,
            placement: PlatePlacement(
                xShift: detailPlacement.xShift,
                yShift: detailPlacement.yShift + pose.mouthPulse * 0.34,
                extraScale: detailPlacement.extraScale
            )
        )
        .scaleEffect(
            x: 1 + pose.mouthPulse * 0.004,
            y: 1 + pose.mouthPulse * 0.016,
            anchor: UnitPoint(x: derivedAssets.mouthRect.midX, y: max(0.04, derivedAssets.mouthRect.minY - 0.12))
        )
        .mask(plateImage(images.featheredMatte, opacity: 1, placement: detailPlacement))
        .blendMode(.overlay)
    }

    private var blinkShadowLayer: some View {
        plateImage(
            images.eyeMask,
            opacity: Double((1 - pose.blink) * 0.42),
            placement: eyePlacement
        )
        .colorMultiply(.black)
        .blendMode(.multiply)
    }

    private var eyeCatchlightLayer: some View {
        ZStack {
            ForEach(Array(derivedAssets.eyeAnchors.enumerated()), id: \.offset) { index, eyeAnchor in
                let point = pointInCard(for: eyeAnchor, placement: headPlacement)

                Circle()
                    .fill(keylightTint.opacity(pose.blink > 0.14 ? 0.80 : 0.18))
                    .frame(width: isHero ? 7 : 5, height: isHero ? 7 : 5)
                    .blur(radius: isHero ? 0.9 : 0.6)
                    .offset(
                        x: point.x - metrics.portraitSize.width / 2 + pose.gazeX * 0.10 + (index == 0 ? -1.5 : 1.2),
                        y: point.y - metrics.portraitSize.height / 2 + pose.gazeY * 0.06 - (isHero ? 1.8 : 1.1)
                    )
            }
        }
        .blendMode(.screen)
        .opacity(state == .error ? 0.20 : 1.0)
    }

    private var portraitLighting: some View {
        ZStack {
            LinearGradient(
                colors: [
                    keylightTint.opacity(palette.highlightOpacity * pose.shimmer),
                    .clear,
                    shadowTint.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [palette.ambient.opacity(Double(pose.glow * palette.glowMultiplier) * 0.55), .clear],
                center: UnitPoint(
                    x: 0.48 + pose.perspectiveX * 0.01,
                    y: 0.28 + pose.perspectiveY * 0.01
                ),
                startRadius: 8,
                endRadius: metrics.portraitSize.width * 0.52
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    .clear,
                    keylightTint.opacity(isHero ? 0.10 : 0.06),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .mask(plateImage(images.featheredMatte, opacity: 1, placement: headPlacement))
            .offset(x: isHero ? 10 : 6)
            .blendMode(.screen)
        }
    }

    private var glassReflection: some View {
        portraitShape
            .fill(
                LinearGradient(
                    colors: [
                        keylightTint.opacity(0.18),
                        keylightTint.opacity(0.03),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            )
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(keylightTint.opacity(0.12))
                    .frame(width: metrics.portraitSize.width * 0.18)
                    .blur(radius: 14)
                    .rotationEffect(.degrees(-18))
                    .offset(x: metrics.portraitSize.width * 0.06, y: metrics.portraitSize.height * 0.10)
                    .clipShape(portraitShape)
            }
    }

    private func pointInCard(for normalizedPoint: CGPoint, placement: PlatePlacement) -> CGPoint {
        let size = metrics.portraitSize
        let imageScale: CGFloat = (isHero ? 0.90 : 1.12) + placement.extraScale
        let focusX = ((derivedAssets.focusCrop.midX - 0.5) * size.width * (isHero ? 0.22 : 0.30))
        let focusY = ((derivedAssets.focusCrop.midY - (isHero ? 0.35 : 0.42)) * size.height * (isHero ? 0.24 : 0.34))

        return CGPoint(
            x: size.width / 2 + (normalizedPoint.x - 0.5) * size.width * imageScale - focusX + placement.xShift,
            y: size.height / 2 + (normalizedPoint.y - 0.5) * size.height * imageScale - focusY + placement.yShift - size.height * (isHero ? 0.19 : 0.05)
        )
    }
}

private struct StaticPhotoPortraitCard: View {
    let image: UIImage
    let portraitProfile: PortraitRenderProfile?
    let focusRect: CGRect
    let palette: PhotoStagePalette
    let pose: CharacterStagePose
    let metrics: CharacterStageMetrics
    let state: AvatarState

    private var portraitShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.portraitCornerRadius, style: .continuous)
    }

    private var profile: PortraitRenderProfile {
        portraitProfile ?? CharacterCatalog.primaryPortraitProfile
    }

    private var isHero: Bool {
        metrics.emphasis == .hero
    }

    private var keylightTint: Color {
        profile.lightingPreset.contains("daylight")
            ? Color(red: 1.00, green: 0.97, blue: 0.92)
            : Color.white
    }

    private var shadowTint: Color {
        profile.lightingPreset.contains("daylight")
            ? Color(red: 0.20, green: 0.14, blue: 0.12)
            : Color.black
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: metrics.portraitSize.width * 0.68, height: 40)
                .blur(radius: 18)
                .offset(y: metrics.portraitSize.height * 0.46)

            portraitShape
                .fill(Color.black.opacity(0.10))
                .overlay {
                    ZStack {
                        photoLayer(opacity: 1.0, extraScale: isHero ? 0.06 : 0.06)
                        portraitLight
                        eyeCatchlightLayer
                        LinearGradient(
                            colors: [
                                keylightTint.opacity(0.08),
                                .clear,
                                shadowTint.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .clipShape(portraitShape)
                }
                .overlay {
                    portraitShape
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
                .frame(width: metrics.portraitSize.width, height: metrics.portraitSize.height)
                .rotation3DEffect(.degrees(Double(pose.perspectiveY * 0.35)), axis: (x: 1, y: 0, z: 0), perspective: 0.78)
                .rotation3DEffect(.degrees(Double(-pose.perspectiveX * 0.38)), axis: (x: 0, y: 1, z: 0), perspective: 0.78)
                .rotationEffect(.degrees(pose.tilt.degrees * 0.24))
                .offset(x: pose.swayX * 0.45, y: pose.swayY * 0.30 + pose.breathing * 0.8)
        }
    }

    private func photoLayer(opacity: Double, extraScale: CGFloat) -> some View {
        let size = metrics.portraitSize
        let imageScale: CGFloat = (isHero ? 0.92 : 1.10) + extraScale
        let focusX = ((focusRect.midX - 0.5) * size.width * (isHero ? 0.22 : 0.30))
        let focusY = ((focusRect.midY - (isHero ? 0.35 : 0.42)) * size.height * (isHero ? 0.24 : 0.34))

        return Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size.width * imageScale, height: size.height * imageScale)
            .saturation(state == .error ? 0.78 : palette.portraitSaturation)
            .contrast(palette.portraitContrast)
            .opacity(opacity)
            .offset(
                x: -focusX,
                y: -focusY - size.height * (isHero ? 0.19 : 0.05)
            )
    }

    private var portraitLight: some View {
        ZStack {
            RadialGradient(
                colors: [
                    keylightTint.opacity(0.14 + Double(pose.shimmer) * 0.04),
                    .clear
                ],
                center: UnitPoint(x: profile.headAnchor.x, y: max(0.18, profile.headAnchor.y + 0.04)),
                startRadius: 4,
                endRadius: metrics.portraitSize.width * (isHero ? 0.28 : 0.22)
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    .clear,
                    shadowTint.opacity(0.10),
                    shadowTint.opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.multiply)
        }
    }

    private var eyeCatchlightLayer: some View {
        ZStack {
            ForEach(Array(profile.eyeAnchors.enumerated()), id: \.offset) { index, eyeAnchor in
                let point = pointInCard(for: eyeAnchor, extraScale: isHero ? 0.06 : 0.06)

                Circle()
                    .fill(keylightTint.opacity(pose.blink > 0.14 ? 0.72 : 0.16))
                    .frame(width: isHero ? 6 : 4.5, height: isHero ? 6 : 4.5)
                    .blur(radius: isHero ? 0.8 : 0.5)
                    .offset(
                        x: point.x - metrics.portraitSize.width / 2 + (index == 0 ? -1.0 : 1.0),
                        y: point.y - metrics.portraitSize.height / 2 - (isHero ? 1.6 : 1.0)
                    )
            }
        }
        .blendMode(.screen)
        .opacity(state == .error ? 0.24 : 1.0)
    }

    private func pointInCard(for normalizedPoint: CGPoint, extraScale: CGFloat) -> CGPoint {
        let size = metrics.portraitSize
        let imageScale: CGFloat = (isHero ? 0.92 : 1.10) + extraScale
        let focusX = ((focusRect.midX - 0.5) * size.width * (isHero ? 0.22 : 0.30))
        let focusY = ((focusRect.midY - (isHero ? 0.35 : 0.42)) * size.height * (isHero ? 0.24 : 0.34))

        return CGPoint(
            x: size.width / 2 + (normalizedPoint.x - 0.5) * size.width * imageScale - focusX,
            y: size.height / 2 + (normalizedPoint.y - 0.5) * size.height * imageScale - focusY - size.height * (isHero ? 0.19 : 0.05)
        )
    }
}

private struct PhotoSceneBackdrop: View {
    let image: UIImage?
    let scene: CharacterScene
    let palette: PhotoStagePalette
    let metrics: CharacterStageMetrics
    let pose: CharacterStagePose
    let reduceEffects: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        let isHero = metrics.emphasis == .hero
        let blurRadius = reduceEffects ? max(6, palette.backdropBlur * 0.33) : palette.backdropBlur + (isHero ? 8 : -4)
        let backdropOpacity = reduceEffects
            ? min(0.42, palette.backdropImageOpacity * 0.55)
            : min(0.9, palette.backdropImageOpacity + (isHero ? 0.08 : -0.02))

        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [palette.top, palette.bottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: metrics.size.width * (isHero ? 1.28 : 1.16), height: metrics.size.height * (isHero ? 1.28 : 1.16))
                    .blur(radius: blurRadius)
                    .saturation(palette.portraitSaturation + (reduceEffects ? 0 : (isHero ? 0.06 : 0.02)))
                    .opacity(backdropOpacity)
                    .offset(x: -pose.swayX * (isHero ? 2.2 : 1.6), y: -pose.swayY * (isHero ? 1.8 : 1.2))
                    .clipped()
                    .clipShape(shape)
            }

            if reduceEffects == false {
                sceneDecor
                    .clipShape(shape)
            }

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isHero ? 0.08 : 0.06),
                            .clear,
                            Color.black.opacity(isHero ? 0.18 : 0.28)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [palette.ambient.opacity(Double(pose.glow * palette.glowMultiplier)), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: metrics.size.width * (isHero ? 0.56 : 0.42)
                    )
                )
                .frame(width: metrics.size.width, height: metrics.size.height)
                .blur(radius: reduceEffects ? 12 : (isHero ? 30 : 20))
                .offset(y: -metrics.size.height * (isHero ? 0.14 : 0.08))
                .blendMode(.screen)
                .opacity(reduceEffects ? 0.48 : 1)

            Ellipse()
                .fill(Color.black.opacity(palette.shadowOpacity))
                .frame(width: metrics.size.width * (isHero ? 0.52 : 0.68), height: metrics.size.height * (isHero ? 0.10 : 0.14))
                .blur(radius: reduceEffects ? 14 : (isHero ? 34 : 24))
                .offset(y: metrics.size.height * (isHero ? 0.39 : 0.34))

            if isHero == false {
                shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }
        }
        .shadow(color: Color.black.opacity(isHero ? palette.shadowOpacity * 0.54 : palette.shadowOpacity), radius: isHero ? 16 : 26, y: isHero ? 8 : 18)
    }

    @ViewBuilder
    private var sceneDecor: some View {
        if metrics.emphasis == .hero {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.10))
                    .frame(width: metrics.size.width * 0.52, height: metrics.size.width * 0.52)
                    .blur(radius: 26)
                    .offset(x: metrics.size.width * 0.18, y: -metrics.size.height * 0.12)

                Ellipse()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: metrics.size.width * 0.84, height: metrics.size.height * 0.52)
                    .blur(radius: 38)
                    .offset(y: -metrics.size.height * 0.06)
            }
        } else {
        switch scene.id {
        case "study":
            VStack(spacing: metrics.size.height * 0.03) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: metrics.size.width * 0.016) {
                        ForEach(0..<7, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(column.isMultiple(of: 2) ? 0.08 : 0.04))
                                .frame(height: metrics.size.height * 0.10)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.size.width * 0.09)
            .padding(.top, metrics.size.height * 0.10)
            .padding(.bottom, metrics.size.height * 0.22)
        case "nightcity":
            VStack {
                HStack(spacing: metrics.size.width * 0.06) {
                    ForEach(0..<5, id: \.self) { index in
                        Circle()
                            .fill((index.isMultiple(of: 2) ? palette.accent : palette.ambient).opacity(0.18))
                            .frame(width: metrics.size.width * (index.isMultiple(of: 2) ? 0.10 : 0.07))
                            .blur(radius: 16)
                    }
                }
                .padding(.top, metrics.size.height * 0.12)
                Spacer()
            }
        default:
            HStack(spacing: metrics.size.width * 0.04) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .padding(.horizontal, metrics.size.width * 0.08)
            .padding(.top, metrics.size.height * 0.07)
            .padding(.bottom, metrics.size.height * 0.20)
        }
        }
    }
}

private struct PhotoPseudo3DPortrait: View {
    let image: UIImage
    let portraitProfile: PortraitRenderProfile?
    let focusRect: CGRect
    let scene: CharacterScene
    let palette: PhotoStagePalette
    let pose: CharacterStagePose
    let metrics: CharacterStageMetrics
    let state: AvatarState

    private var portraitShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.portraitCornerRadius, style: .continuous)
    }

    private var profile: PortraitRenderProfile {
        portraitProfile ?? CharacterCatalog.primaryPortraitProfile
    }

    private var isHero: Bool {
        metrics.emphasis == .hero
    }

    private var keylightTint: Color {
        profile.lightingPreset.contains("daylight")
            ? Color(red: 1.00, green: 0.97, blue: 0.92)
            : Color.white
    }

    private var shadowTint: Color {
        profile.lightingPreset.contains("daylight")
            ? Color(red: 0.20, green: 0.14, blue: 0.12)
            : Color.black
    }

    var body: some View {
        Group {
            if isHero {
                heroPortrait
            } else {
                compactPortrait
            }
        }
    }

    private var compactPortrait: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.portraitCornerRadius + 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .frame(width: metrics.portraitSize.width + 18, height: metrics.portraitSize.height + 20)
                .blur(radius: 10)
                .offset(x: pose.swayX * 0.55, y: 26)

            portraitCard
                .frame(width: metrics.portraitSize.width, height: metrics.portraitSize.height)
                .rotation3DEffect(.degrees(Double(pose.perspectiveY)), axis: (x: 1, y: 0, z: 0), perspective: 0.75)
                .rotation3DEffect(.degrees(Double(-pose.perspectiveX)), axis: (x: 0, y: 1, z: 0), perspective: 0.75)
                .rotationEffect(pose.tilt)
                .offset(x: pose.swayX, y: pose.swayY + pose.breathing * 1.5)

            glassReflection
                .frame(width: metrics.portraitSize.width, height: metrics.portraitSize.height)
                .rotation3DEffect(.degrees(Double(pose.perspectiveY)), axis: (x: 1, y: 0, z: 0), perspective: 0.75)
                .rotation3DEffect(.degrees(Double(-pose.perspectiveX)), axis: (x: 0, y: 1, z: 0), perspective: 0.75)
                .rotationEffect(pose.tilt)
                .offset(x: pose.swayX, y: pose.swayY + pose.breathing * 1.5)
                .blendMode(.screen)
                .allowsHitTesting(false)
        }
    }

    private var heroPortrait: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.20))
                .frame(width: metrics.portraitSize.width * 0.72, height: 44)
                .blur(radius: 20)
                .offset(y: metrics.portraitSize.height * 0.47)

            heroPortraitCard
                .frame(width: metrics.portraitSize.width, height: metrics.portraitSize.height)
                .rotation3DEffect(.degrees(Double(pose.perspectiveY * 0.55)), axis: (x: 1, y: 0, z: 0), perspective: 0.82)
                .rotation3DEffect(.degrees(Double(-pose.perspectiveX * 0.72)), axis: (x: 0, y: 1, z: 0), perspective: 0.82)
                .rotationEffect(.degrees(pose.tilt.degrees * 0.45))
                .offset(x: pose.swayX * 0.7, y: pose.swayY * 0.55 + pose.breathing * 1.2)
        }
    }

    private var heroPortraitCard: some View {
        ZStack {
            portraitShape
                .fill(Color.black.opacity(0.08))

            ZStack {
                photoLayer(
                    blurRadius: 18,
                    brightness: -0.05,
                    opacity: 0.38,
                    xShift: -pose.perspectiveX * 2.0,
                    yShift: -pose.perspectiveY * 1.8,
                    extraScale: 0.08
                )

                photoLayer(
                    blurRadius: 0,
                    brightness: 0.01,
                    opacity: 1,
                    xShift: pose.perspectiveX * 1.2,
                    yShift: pose.perspectiveY * 0.9,
                    extraScale: 0.06
                )

                lowerFaceMotionLayer
                cheekMotionLayer
                blinkShadeLayer
                eyeCatchlightLayer

                portraitLighting

                LinearGradient(
                    colors: [
                        keylightTint.opacity(0.09),
                        .clear,
                        shadowTint.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [
                        .clear,
                        .clear,
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(portraitShape)

            portraitShape
                .stroke(Color.white.opacity(0.14), lineWidth: 1)

            portraitShape
                .stroke(Color.white.opacity(0.06), lineWidth: 8)
                .blur(radius: 12)
                .opacity(0.45)

            Rectangle()
                .fill(keylightTint.opacity(0.12))
                .frame(width: metrics.portraitSize.width * 0.18)
                .blur(radius: 18)
                .rotationEffect(.degrees(-17))
                .offset(x: metrics.portraitSize.width * 0.18, y: -metrics.portraitSize.height * 0.18)
                .clipShape(portraitShape)
                .blendMode(.screen)
        }
    }

    private var portraitCard: some View {
        ZStack {
            portraitShape
                .fill(Color.white.opacity(0.08))
                .background(.ultraThinMaterial, in: portraitShape)

            portraitShape
                .fill(Color.black.opacity(0.24))
                .overlay {
                    ZStack {
                        photoLayer(
                            blurRadius: 16,
                            brightness: -0.06,
                            opacity: 0.54,
                            xShift: -pose.perspectiveX * 1.8,
                            yShift: -pose.perspectiveY * 1.4,
                            extraScale: 0.12
                        )

                        photoLayer(
                            blurRadius: 0,
                            brightness: 0,
                            opacity: 1,
                            xShift: pose.perspectiveX * 0.9,
                            yShift: pose.perspectiveY * 0.7,
                            extraScale: 0.04
                        )

                        lowerFaceMotionLayer
                        cheekMotionLayer
                        blinkShadeLayer
                        eyeCatchlightLayer

                        portraitLighting
                    }
                    .clipShape(portraitShape)
                }

            portraitShape
                .stroke(palette.frame, lineWidth: 1)
                .shadow(color: palette.frameShadow, radius: 30, y: 18)

            portraitShape
                .stroke(Color.white.opacity(0.06), lineWidth: 6)
                .blur(radius: 12)
                .opacity(0.7)
        }
    }

    private func photoLayer(
        blurRadius: CGFloat,
        brightness: Double,
        opacity: Double,
        xShift: CGFloat,
        yShift: CGFloat,
        extraScale: CGFloat
    ) -> some View {
        let size = metrics.portraitSize
        let imageScale: CGFloat = (isHero ? 0.92 : 1.12) + extraScale
        let focusX = ((focusRect.midX - 0.5) * size.width * (isHero ? 0.22 : 0.30))
        let focusY = ((focusRect.midY - (isHero ? 0.35 : 0.42)) * size.height * (isHero ? 0.24 : 0.34))

        return Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size.width * imageScale, height: size.height * imageScale)
            .saturation(state == .error ? 0.75 : palette.portraitSaturation)
            .brightness(brightness)
            .contrast(palette.portraitContrast)
            .blur(radius: blurRadius)
            .opacity(opacity)
            .offset(
                x: -focusX + xShift,
                y: -focusY + yShift - size.height * (isHero ? 0.19 : 0.05)
            )
    }

    private var lowerFaceMotionLayer: some View {
        let height = metrics.portraitSize.height
        let width = metrics.portraitSize.width
        let maskWidth = width * max(0.24, profile.mouthRect.width * 1.25)
        let maskHeight = height * max(0.12, profile.mouthRect.height * 1.30)
        let mouthCenter = pointInCard(for: CGPoint(x: profile.mouthRect.midX, y: profile.mouthRect.midY), extraScale: 0.06)
        let maskX = mouthCenter.x - width / 2
        let maskY = mouthCenter.y - height / 2

        return photoLayer(
            blurRadius: 0.6,
            brightness: 0.03,
            opacity: state == .speaking ? 0.34 : 0.12,
            xShift: pose.perspectiveX * 1.1,
            yShift: pose.perspectiveY * 0.9 + pose.mouthPulse * 1.8,
            extraScale: 0.06
        )
        .scaleEffect(
            x: 1 + pose.mouthPulse * 0.01,
            y: 1 + pose.mouthPulse * 0.08,
            anchor: .top
        )
        .mask(
            RoundedRectangle(cornerRadius: maskHeight * 0.34, style: .continuous)
                .frame(width: maskWidth, height: maskHeight)
                .offset(x: maskX, y: maskY)
                .blur(radius: 8)
        )
    }

    private var cheekMotionLayer: some View {
        photoLayer(
            blurRadius: 0,
            brightness: 0.02,
            opacity: state == .speaking ? 0.10 : 0.04,
            xShift: pose.perspectiveX * 0.95,
            yShift: pose.perspectiveY * 0.82 + pose.mouthPulse * 0.45,
            extraScale: 0.08
        )
        .scaleEffect(
            x: 1 + pose.mouthPulse * 0.004,
            y: 1 + pose.mouthPulse * 0.018,
            anchor: UnitPoint(x: profile.mouthRect.midX, y: max(0.04, profile.mouthRect.minY - 0.10))
        )
        .mask(
            Ellipse()
                .frame(
                    width: metrics.portraitSize.width * max(0.42, profile.focusCrop.width * 0.62),
                    height: metrics.portraitSize.height * max(0.28, profile.focusCrop.height * 0.34)
                )
                .offset(y: metrics.portraitSize.height * 0.02)
                .blur(radius: 12)
        )
        .blendMode(.overlay)
    }

    private var blinkShadeLayer: some View {
        let eyeCenter = averageEyeAnchor
        let eyePoint = pointInCard(for: eyeCenter, extraScale: 0.08)

        return RoundedRectangle(cornerRadius: metrics.portraitSize.height * 0.04, style: .continuous)
            .fill(shadowTint.opacity(Double((1 - pose.blink) * 0.18)))
            .frame(
                width: metrics.portraitSize.width * max(0.34, profile.focusCrop.width * 0.44),
                height: metrics.portraitSize.height * max(0.08, profile.focusCrop.height * 0.10)
            )
            .blur(radius: 10)
            .offset(
                x: eyePoint.x - metrics.portraitSize.width / 2,
                y: eyePoint.y - metrics.portraitSize.height / 2
            )
            .blendMode(.multiply)
    }

    private var eyeCatchlightLayer: some View {
        ZStack {
            ForEach(Array(profile.eyeAnchors.enumerated()), id: \.offset) { index, eyeAnchor in
                let point = pointInCard(for: eyeAnchor, extraScale: 0.08)

                Circle()
                    .fill(keylightTint.opacity(pose.blink > 0.14 ? 0.80 : 0.18))
                    .frame(width: isHero ? 7 : 5, height: isHero ? 7 : 5)
                    .blur(radius: isHero ? 0.8 : 0.5)
                    .offset(
                        x: point.x - metrics.portraitSize.width / 2 + (index == 0 ? -1.2 : 1.0),
                        y: point.y - metrics.portraitSize.height / 2 - (isHero ? 1.8 : 1.0)
                    )
            }
        }
        .blendMode(.screen)
        .opacity(state == .error ? 0.20 : 1.0)
    }

    private var portraitLighting: some View {
        ZStack {
            LinearGradient(
                colors: [
                    keylightTint.opacity(palette.highlightOpacity * pose.shimmer),
                    .clear,
                    shadowTint.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [palette.ambient.opacity(Double(pose.glow * palette.glowMultiplier) * 0.55), .clear],
                center: UnitPoint(
                    x: 0.48 + pose.perspectiveX * 0.01,
                    y: 0.28 + pose.perspectiveY * 0.01
                ),
                startRadius: 8,
                endRadius: metrics.portraitSize.width * 0.52
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [
                    keylightTint.opacity(0.08 + Double(pose.shimmer) * 0.05),
                    .clear
                ],
                center: UnitPoint(x: profile.headAnchor.x, y: max(0.18, profile.headAnchor.y + 0.05)),
                startRadius: 4,
                endRadius: metrics.portraitSize.width * (isHero ? 0.30 : 0.24)
            )
            .blendMode(.screen)
        }
    }

    private var glassReflection: some View {
        portraitShape
            .fill(
                LinearGradient(
                    colors: [
                        keylightTint.opacity(0.20),
                        keylightTint.opacity(0.03),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            )
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(keylightTint.opacity(0.14))
                    .frame(width: metrics.portraitSize.width * 0.18)
                    .blur(radius: 14)
                    .rotationEffect(.degrees(-18))
                    .offset(x: metrics.portraitSize.width * 0.06, y: metrics.portraitSize.height * 0.10)
                    .clipShape(portraitShape)
            }
    }

    private var averageEyeAnchor: CGPoint {
        guard profile.eyeAnchors.isEmpty == false else {
            return CGPoint(x: profile.headAnchor.x, y: profile.headAnchor.y + 0.16)
        }

        let sum = profile.eyeAnchors.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let count = CGFloat(profile.eyeAnchors.count)
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    private func pointInCard(for normalizedPoint: CGPoint, extraScale: CGFloat) -> CGPoint {
        let size = metrics.portraitSize
        let imageScale: CGFloat = (isHero ? 0.92 : 1.12) + extraScale
        let focusX = ((focusRect.midX - 0.5) * size.width * (isHero ? 0.22 : 0.30))
        let focusY = ((focusRect.midY - (isHero ? 0.35 : 0.42)) * size.height * (isHero ? 0.24 : 0.34))

        return CGPoint(
            x: size.width / 2 + (normalizedPoint.x - 0.5) * size.width * imageScale - focusX,
            y: size.height / 2 + (normalizedPoint.y - 0.5) * size.height * imageScale - focusY - size.height * (isHero ? 0.19 : 0.05)
        )
    }
}

private enum FallbackHairStyle {
    case softWave
    case curtain
    case crop
}

private struct FallbackCharacterLook {
    let skinTop: Color
    let skinBottom: Color
    let hair: Color
    let hairShadow: Color
    let eye: Color
    let lip: Color
    let outfit: Color
    let outfitAccent: Color
    let glow: Color
    let accessory: Color?
    let hairStyle: FallbackHairStyle

    static func forCharacter(_ characterID: String, palette: PhotoStagePalette) -> FallbackCharacterLook {
        switch characterID {
        case "lyra":
            return FallbackCharacterLook(
                skinTop: Color(red: 0.94, green: 0.84, blue: 0.77),
                skinBottom: Color(red: 0.84, green: 0.69, blue: 0.61),
                hair: Color(red: 0.18, green: 0.13, blue: 0.12),
                hairShadow: Color(red: 0.10, green: 0.07, blue: 0.07),
                eye: Color(red: 0.24, green: 0.18, blue: 0.16),
                lip: Color(red: 0.71, green: 0.36, blue: 0.37),
                outfit: Color(red: 0.27, green: 0.30, blue: 0.42),
                outfitAccent: Color(red: 0.86, green: 0.77, blue: 0.63),
                glow: palette.accent.opacity(0.24),
                accessory: Color.white.opacity(0.68),
                hairStyle: .curtain
            )
        case "sol":
            return FallbackCharacterLook(
                skinTop: Color(red: 0.90, green: 0.73, blue: 0.62),
                skinBottom: Color(red: 0.77, green: 0.57, blue: 0.47),
                hair: Color(red: 0.13, green: 0.10, blue: 0.12),
                hairShadow: Color(red: 0.07, green: 0.05, blue: 0.07),
                eye: Color(red: 0.19, green: 0.12, blue: 0.10),
                lip: Color(red: 0.69, green: 0.34, blue: 0.31),
                outfit: Color(red: 0.23, green: 0.19, blue: 0.25),
                outfitAccent: Color(red: 0.96, green: 0.64, blue: 0.33),
                glow: palette.accent.opacity(0.30),
                accessory: nil,
                hairStyle: .crop
            )
        default:
            return FallbackCharacterLook(
                skinTop: Color(red: 0.96, green: 0.84, blue: 0.78),
                skinBottom: Color(red: 0.86, green: 0.68, blue: 0.63),
                hair: Color(red: 0.29, green: 0.19, blue: 0.17),
                hairShadow: Color(red: 0.16, green: 0.10, blue: 0.10),
                eye: Color(red: 0.21, green: 0.15, blue: 0.13),
                lip: Color(red: 0.77, green: 0.39, blue: 0.40),
                outfit: Color(red: 0.17, green: 0.23, blue: 0.38),
                outfitAccent: Color(red: 0.90, green: 0.50, blue: 0.32),
                glow: palette.accent.opacity(0.28),
                accessory: Color(red: 0.96, green: 0.76, blue: 0.44),
                hairStyle: .softWave
            )
        }
    }
}

private struct PhotoFallbackStage: View {
    let characterID: String
    let palette: PhotoStagePalette
    let metrics: CharacterStageMetrics
    let pose: CharacterStagePose
    let state: AvatarState

    private var look: FallbackCharacterLook {
        FallbackCharacterLook.forCharacter(characterID, palette: palette)
    }

    var body: some View {
        let width = metrics.portraitSize.width
        let height = metrics.portraitSize.height

        ZStack {
            RoundedRectangle(cornerRadius: metrics.portraitCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.top.opacity(0.96), palette.bottom.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Circle()
                .fill(look.glow)
                .frame(width: width * 0.86, height: width * 0.86)
                .blur(radius: metrics.emphasis == .hero ? 26 : 18)
                .offset(y: -height * 0.12)

            RoundedRectangle(cornerRadius: metrics.portraitCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)

            bust(width: width, height: height)
                .padding(.top, height * 0.06)
                .padding(.horizontal, width * 0.05)
        }
        .frame(width: width, height: height)
        .saturation(state == .error ? 0.62 : 1)
        .opacity(state == .error ? 0.86 : 1)
    }

    @ViewBuilder
    private func bust(width: CGFloat, height: CGFloat) -> some View {
        let blinkScale = max(pose.blink, 0.04)
        let faceWidth = width * 0.43
        let faceHeight = height * 0.50
        let eyeWidth = faceWidth * 0.14
        let eyeHeight = max(faceHeight * 0.038 * blinkScale, 1.8)
        let pupilSize = max(faceWidth * 0.030, 4)
        let pupilOffsetX = pose.gazeX * 0.35
        let pupilOffsetY = pose.gazeY * 0.20
        let smileLift = max(-4, min(6, pose.smile * 7 - pose.mouthPulse * 2))
        let mouthHeight = max(3, 5 + pose.mouthPulse * 10)

        ZStack {
            shoulderShape(width: width, height: height)
                .fill(
                    LinearGradient(
                        colors: [look.outfit.opacity(0.98), look.outfit.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .top) {
                    outfitAccentShape(width: width, height: height)
                        .fill(look.outfitAccent.opacity(0.94))
                }
                .shadow(color: Color.black.opacity(0.16), radius: 18, y: 12)
                .offset(y: height * 0.23)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [look.skinTop.opacity(0.96), look.skinBottom.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: faceWidth * 0.24, height: faceHeight * 0.22)
                .offset(y: height * 0.11)

            hairBackShape(width: width, height: height)
                .fill(
                    LinearGradient(
                        colors: [look.hair, look.hairShadow],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: -height * 0.05)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [look.skinTop, look.skinBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: faceWidth, height: faceHeight)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: faceWidth * 0.34, height: faceWidth * 0.34)
                        .blur(radius: 6)
                        .offset(x: faceWidth * 0.08, y: faceHeight * 0.10)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 10, y: 8)
                .offset(x: pose.perspectiveX * 0.2, y: -height * 0.06)

            hairFrontShape(width: width, height: height)
                .fill(
                    LinearGradient(
                        colors: [look.hair, look.hairShadow],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: -height * 0.12)

            HStack(spacing: faceWidth * 0.20) {
                eyeStack(
                    width: eyeWidth,
                    height: eyeHeight,
                    pupilSize: pupilSize,
                    pupilOffsetX: pupilOffsetX,
                    pupilOffsetY: pupilOffsetY
                )
                eyeStack(
                    width: eyeWidth,
                    height: eyeHeight,
                    pupilSize: pupilSize,
                    pupilOffsetX: pupilOffsetX,
                    pupilOffsetY: pupilOffsetY
                )
            }
            .offset(x: pose.perspectiveX * 0.15, y: -height * 0.11 + pose.gazeY * 0.1)

            eyebrowStack(faceWidth: faceWidth)
                .offset(x: pose.perspectiveX * 0.12, y: -height * 0.16)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.22))
                .frame(width: faceWidth * 0.05, height: faceHeight * 0.12)
                .rotationEffect(.degrees(8))
                .offset(x: faceWidth * 0.01 + pose.perspectiveX * 0.08, y: -height * 0.04)

            mouthShape(width: faceWidth * 0.28, height: CGFloat(mouthHeight), lift: CGFloat(smileLift))
                .stroke(look.lip, style: StrokeStyle(lineWidth: max(2.4, CGFloat(mouthHeight) * 0.34), lineCap: .round))
                .offset(x: pose.perspectiveX * 0.12, y: height * 0.03)

            if let accessory = look.accessory {
                accessoryView(color: accessory, width: width, height: height)
            }
        }
    }

    private func eyeStack(
        width: CGFloat,
        height: CGFloat,
        pupilSize: CGFloat,
        pupilOffsetX: CGFloat,
        pupilOffsetY: CGFloat
    ) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.96))
                .frame(width: width, height: height)
            Circle()
                .fill(look.eye)
                .frame(width: pupilSize, height: pupilSize)
                .offset(x: pupilOffsetX, y: pupilOffsetY)
            Circle()
                .fill(Color.white.opacity(0.68))
                .frame(width: pupilSize * 0.28, height: pupilSize * 0.28)
                .offset(x: pupilOffsetX + 1, y: pupilOffsetY - 1)
        }
    }

    private func eyebrowStack(faceWidth: CGFloat) -> some View {
        HStack(spacing: faceWidth * 0.17) {
            Capsule(style: .continuous)
                .fill(look.hairShadow.opacity(0.86))
                .frame(width: faceWidth * 0.18, height: 5)
                .rotationEffect(.degrees(characterID == "sol" ? -18 : -9))
            Capsule(style: .continuous)
                .fill(look.hairShadow.opacity(0.86))
                .frame(width: faceWidth * 0.18, height: 5)
                .rotationEffect(.degrees(characterID == "sol" ? 11 : 6))
        }
    }

    private func accessoryView(color: Color, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if characterID == "lyra" {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color, lineWidth: 2)
                    .frame(width: width * 0.17, height: height * 0.08)
                    .offset(x: -width * 0.10, y: -height * 0.12)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color, lineWidth: 2)
                    .frame(width: width * 0.17, height: height * 0.08)
                    .offset(x: width * 0.10, y: -height * 0.12)
                Rectangle()
                    .fill(color)
                    .frame(width: width * 0.06, height: 2)
                    .offset(y: -height * 0.12)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: width * 0.034, height: width * 0.034)
                    .offset(x: width * 0.17, y: -height * 0.02)
            }
        }
    }

    private func shoulderShape(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: width * 0.14, y: height * 0.82))
            path.addCurve(
                to: CGPoint(x: width * 0.50, y: height * 0.58),
                control1: CGPoint(x: width * 0.18, y: height * 0.64),
                control2: CGPoint(x: width * 0.34, y: height * 0.56)
            )
            path.addCurve(
                to: CGPoint(x: width * 0.86, y: height * 0.82),
                control1: CGPoint(x: width * 0.66, y: height * 0.56),
                control2: CGPoint(x: width * 0.82, y: height * 0.64)
            )
            path.addLine(to: CGPoint(x: width * 0.92, y: height * 0.98))
            path.addLine(to: CGPoint(x: width * 0.08, y: height * 0.98))
            path.closeSubpath()
        }
    }

    private func outfitAccentShape(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: width * 0.50, y: height * 0.60))
            path.addLine(to: CGPoint(x: width * 0.46, y: height * 0.84))
            path.addLine(to: CGPoint(x: width * 0.54, y: height * 0.84))
            path.closeSubpath()
        }
    }

    private func hairBackShape(width: CGFloat, height: CGFloat) -> Path {
        switch look.hairStyle {
        case .softWave:
            return Path { path in
                path.move(to: CGPoint(x: width * 0.30, y: height * 0.10))
                path.addCurve(
                    to: CGPoint(x: width * 0.22, y: height * 0.54),
                    control1: CGPoint(x: width * 0.18, y: height * 0.18),
                    control2: CGPoint(x: width * 0.16, y: height * 0.42)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.78, y: height * 0.54),
                    control1: CGPoint(x: width * 0.34, y: height * 0.70),
                    control2: CGPoint(x: width * 0.66, y: height * 0.70)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.70, y: height * 0.10),
                    control1: CGPoint(x: width * 0.84, y: height * 0.42),
                    control2: CGPoint(x: width * 0.82, y: height * 0.18)
                )
                path.closeSubpath()
            }
        case .curtain:
            return Path { path in
                path.move(to: CGPoint(x: width * 0.28, y: height * 0.10))
                path.addCurve(
                    to: CGPoint(x: width * 0.20, y: height * 0.48),
                    control1: CGPoint(x: width * 0.18, y: height * 0.16),
                    control2: CGPoint(x: width * 0.16, y: height * 0.36)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.80, y: height * 0.48),
                    control1: CGPoint(x: width * 0.36, y: height * 0.64),
                    control2: CGPoint(x: width * 0.64, y: height * 0.64)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.72, y: height * 0.10),
                    control1: CGPoint(x: width * 0.84, y: height * 0.36),
                    control2: CGPoint(x: width * 0.82, y: height * 0.16)
                )
                path.closeSubpath()
            }
        case .crop:
            return Path { path in
                path.move(to: CGPoint(x: width * 0.30, y: height * 0.16))
                path.addCurve(
                    to: CGPoint(x: width * 0.24, y: height * 0.40),
                    control1: CGPoint(x: width * 0.21, y: height * 0.20),
                    control2: CGPoint(x: width * 0.20, y: height * 0.32)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.76, y: height * 0.40),
                    control1: CGPoint(x: width * 0.38, y: height * 0.50),
                    control2: CGPoint(x: width * 0.62, y: height * 0.50)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.70, y: height * 0.16),
                    control1: CGPoint(x: width * 0.80, y: height * 0.32),
                    control2: CGPoint(x: width * 0.79, y: height * 0.20)
                )
                path.closeSubpath()
            }
        }
    }

    private func hairFrontShape(width: CGFloat, height: CGFloat) -> Path {
        switch look.hairStyle {
        case .softWave:
            return Path { path in
                path.move(to: CGPoint(x: width * 0.28, y: height * 0.18))
                path.addCurve(
                    to: CGPoint(x: width * 0.46, y: height * 0.12),
                    control1: CGPoint(x: width * 0.32, y: height * 0.10),
                    control2: CGPoint(x: width * 0.40, y: height * 0.09)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.72, y: height * 0.20),
                    control1: CGPoint(x: width * 0.54, y: height * 0.15),
                    control2: CGPoint(x: width * 0.65, y: height * 0.13)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.62, y: height * 0.32),
                    control1: CGPoint(x: width * 0.72, y: height * 0.24),
                    control2: CGPoint(x: width * 0.67, y: height * 0.32)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.44, y: height * 0.24),
                    control1: CGPoint(x: width * 0.56, y: height * 0.32),
                    control2: CGPoint(x: width * 0.48, y: height * 0.30)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.28, y: height * 0.18),
                    control1: CGPoint(x: width * 0.34, y: height * 0.20),
                    control2: CGPoint(x: width * 0.30, y: height * 0.20)
                )
                path.closeSubpath()
            }
        case .curtain:
            return Path { path in
                path.move(to: CGPoint(x: width * 0.32, y: height * 0.20))
                path.addCurve(
                    to: CGPoint(x: width * 0.50, y: height * 0.14),
                    control1: CGPoint(x: width * 0.36, y: height * 0.12),
                    control2: CGPoint(x: width * 0.44, y: height * 0.10)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.68, y: height * 0.20),
                    control1: CGPoint(x: width * 0.56, y: height * 0.10),
                    control2: CGPoint(x: width * 0.64, y: height * 0.12)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.60, y: height * 0.34),
                    control1: CGPoint(x: width * 0.68, y: height * 0.28),
                    control2: CGPoint(x: width * 0.66, y: height * 0.34)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.50, y: height * 0.28),
                    control1: CGPoint(x: width * 0.56, y: height * 0.34),
                    control2: CGPoint(x: width * 0.52, y: height * 0.32)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.40, y: height * 0.34),
                    control1: CGPoint(x: width * 0.48, y: height * 0.32),
                    control2: CGPoint(x: width * 0.44, y: height * 0.34)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.32, y: height * 0.20),
                    control1: CGPoint(x: width * 0.34, y: height * 0.34),
                    control2: CGPoint(x: width * 0.32, y: height * 0.28)
                )
                path.closeSubpath()
            }
        case .crop:
            return Path { path in
                path.move(to: CGPoint(x: width * 0.28, y: height * 0.24))
                path.addCurve(
                    to: CGPoint(x: width * 0.74, y: height * 0.22),
                    control1: CGPoint(x: width * 0.38, y: height * 0.12),
                    control2: CGPoint(x: width * 0.64, y: height * 0.10)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.64, y: height * 0.34),
                    control1: CGPoint(x: width * 0.72, y: height * 0.30),
                    control2: CGPoint(x: width * 0.68, y: height * 0.34)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.28, y: height * 0.24),
                    control1: CGPoint(x: width * 0.54, y: height * 0.28),
                    control2: CGPoint(x: width * 0.38, y: height * 0.28)
                )
                path.closeSubpath()
            }
        }
    }

    private func mouthShape(width: CGFloat, height: CGFloat, lift: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: width * 0.36, y: height * 0.50))
            path.addQuadCurve(
                to: CGPoint(x: width * 0.64, y: height * 0.50),
                control: CGPoint(x: width * 0.50, y: height * 0.50 + lift)
            )
        }
    }
}

private struct ThinkingHalo: View {
    let color: Color
    let metrics: CharacterStageMetrics
    let pose: CharacterStagePose

    var body: some View {
        Circle()
            .trim(from: 0.14, to: 0.86)
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.18), color.opacity(0.88), Color.white.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: metrics.emphasis == .hero ? 5 : 3, lineCap: .round)
            )
            .frame(width: metrics.portraitSize.width + 58, height: metrics.portraitSize.width + 58)
            .rotationEffect(.degrees(Double(pose.shimmer * 220)))
            .blur(radius: 0.3)
    }
}

private struct StageBadge: View {
    let text: String
    let palette: PhotoStagePalette

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(palette.accent)
                .frame(width: 8, height: 8)
            Text(text)
        }
        .font(.system(.caption, design: .rounded, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .down:
            self = .down
        case .left:
            self = .left
        case .right:
            self = .right
        case .upMirrored:
            self = .upMirrored
        case .downMirrored:
            self = .downMirrored
        case .leftMirrored:
            self = .leftMirrored
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
