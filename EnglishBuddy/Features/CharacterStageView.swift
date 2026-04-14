import SwiftUI

struct CharacterStageView: View {
    let state: AvatarState
    let audioLevel: Double
    var emphasis: AvatarEmphasis = .compact
    var characterID: String? = nil
    var sceneID: String? = nil

    private var character: CharacterProfile {
        CharacterCatalog.profile(for: characterID)
    }

    private var scene: CharacterScene {
        CharacterCatalog.scene(for: sceneID, characterID: characterID)
    }

    private var pack: CharacterPackManifest {
        CharacterCatalog.pack(for: character.id)
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let metrics = CharacterStageMetrics(size: proxy.size, emphasis: emphasis)
                let palette = CharacterStagePalette.palette(for: character.id)
                let pose = CharacterStagePose(
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    state: state,
                    audioLevel: audioLevel,
                    lipSyncStyle: pack.lipSyncStyle
                )

                ZStack {
                    CharacterStageBackground(
                        scene: scene,
                        palette: palette,
                        metrics: metrics,
                        state: state,
                        pose: pose
                    )

                    CharacterPortrait(
                        character: character,
                        scene: scene,
                        pack: pack,
                        palette: palette,
                        pose: pose,
                        metrics: metrics,
                        state: state
                    )
                    .frame(width: metrics.canvasSize.width, height: metrics.canvasSize.height)
                    .scaleEffect(metrics.scale, anchor: .center)
                    .offset(y: metrics.verticalOffset)

                    if state == .thinking {
                        ThinkingHalo(color: palette.accent, metrics: metrics, pose: pose)
                            .scaleEffect(metrics.scale, anchor: .center)
                            .offset(y: metrics.verticalOffset - (emphasis == .hero ? 4 : 2))
                    }

                    if let badge = badgeText {
                        StageBadge(text: badge, palette: palette)
                            .padding(.top, emphasis == .hero ? 18 : 12)
                            .padding(.horizontal, emphasis == .hero ? 18 : 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private var badgeText: String? {
        switch state {
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
}

private struct CharacterStageMetrics {
    let size: CGSize
    let emphasis: AvatarEmphasis
    let canvasSize: CGSize
    let scale: CGFloat
    let verticalOffset: CGFloat
    let cornerRadius: CGFloat

    init(size: CGSize, emphasis: AvatarEmphasis) {
        self.size = size
        self.emphasis = emphasis

        switch emphasis {
        case .hero:
            canvasSize = CGSize(width: 320, height: 420)
            cornerRadius = 36
            verticalOffset = 10
        case .compact:
            canvasSize = CGSize(width: 240, height: 300)
            cornerRadius = 28
            verticalOffset = 4
        }

        scale = min(size.width / canvasSize.width, size.height / canvasSize.height)
    }
}

private struct CharacterStagePose {
    let breathing: CGFloat
    let bodyFloat: CGFloat
    let shoulderLift: CGFloat
    let headOffsetX: CGFloat
    let headOffsetY: CGFloat
    let headTilt: Angle
    let gazeX: CGFloat
    let gazeY: CGFloat
    let blinkAmount: CGFloat
    let mouthOpen: CGFloat
    let smileCurve: CGFloat
    let auraPulse: CGFloat
    let attentionLift: CGFloat
    let browLift: CGFloat

    init(time: TimeInterval, state: AvatarState, audioLevel: Double, lipSyncStyle: String) {
        let cycle = CGFloat(time)
        let clampedAudio = max(0, min(CGFloat(audioLevel), 1))
        let breathingWave = sin(cycle * 1.3)
        let bodyFloatWave = sin(cycle * 0.85)
        let blink = max(
            Self.blinkPulse(time: cycle, period: 3.1, width: 0.08, offset: 0.32),
            Self.blinkPulse(time: cycle, period: 4.7, width: 0.07, offset: 1.18)
        )
        let idleGazeX = sin(cycle * 0.42) * 3.2
        let idleGazeY = cos(cycle * 0.31) * 1.8
        let speechCadence = (sin(cycle * 18.0) + 1) * 0.5

        var stateHeadX: CGFloat = 0
        var stateHeadY: CGFloat = 0
        var stateTilt: CGFloat = sin(cycle * 0.55) * 1.6
        var stateGazeX: CGFloat = idleGazeX
        var stateGazeY: CGFloat = idleGazeY
        var mouthBase: CGFloat = 0.08
        var mouthRange: CGFloat = 0.06
        var smile: CGFloat = 0.14
        var aura: CGFloat = 0.16
        var attention: CGFloat = 0
        var brow: CGFloat = 0

        switch state {
        case .idle:
            stateHeadY = breathingWave * -1.4
        case .listening:
            stateHeadY = -6 + breathingWave * -1.6
            stateTilt -= 2.8
            stateGazeY = -3.2
            smile = 0.2
            attention = 6
            brow = 1.5
        case .thinking:
            stateHeadX = 5
            stateHeadY = -3
            stateTilt += 4.5
            stateGazeX = 9
            stateGazeY = -8
            mouthBase = 0.05
            mouthRange = 0.03
            smile = 0.04
            aura = 0.26
            attention = 10
            brow = 2.4
        case .speaking:
            stateHeadY = -3 + sin(cycle * 3.5) * 1.8
            stateTilt += sin(cycle * 2.9) * 2.4
            stateGazeX = idleGazeX * 0.5
            stateGazeY = -1
            mouthBase = 0.18
            mouthRange = lipSyncStyle == "wide-bright" ? 0.42 : (lipSyncStyle == "narrow-precise" ? 0.28 : 0.34)
            smile = 0.18
            aura = 0.34
            attention = 7
            brow = 1.2
        case .interrupted:
            stateHeadX = -4
            stateHeadY = -2
            stateTilt -= 6.5
            stateGazeX = -5
            stateGazeY = -1
            mouthBase = 0.11
            mouthRange = 0.09
            smile = -0.02
            aura = 0.2
            attention = 4
        case .error:
            stateHeadY = 1
            stateTilt = -1.2
            stateGazeX = 0
            stateGazeY = 1
            mouthBase = 0.04
            mouthRange = 0.02
            smile = -0.08
            aura = 0.12
            attention = 0
            brow = -1.4
        }

        breathing = breathingWave
        bodyFloat = bodyFloatWave * 2.4
        shoulderLift = breathingWave * 3.8
        headOffsetX = stateHeadX + sin(cycle * 0.92) * 1.5
        headOffsetY = stateHeadY + breathingWave * -2.1
        headTilt = .degrees(stateTilt)
        gazeX = stateGazeX
        gazeY = stateGazeY
        blinkAmount = blink
        mouthOpen = max(0.02, mouthBase + mouthRange * max(clampedAudio, CGFloat(speechCadence) * (state == .speaking ? 0.9 : 0.18)))
        smileCurve = smile
        auraPulse = aura + sin(cycle * 1.8) * 0.04
        attentionLift = attention + sin(cycle * 1.4) * 1.6
        browLift = brow
    }

    private static func blinkPulse(time: CGFloat, period: CGFloat, width: CGFloat, offset: CGFloat) -> CGFloat {
        let t = (time + offset).truncatingRemainder(dividingBy: period)
        let distance = min(t, period - t)
        guard distance < width else { return 0 }
        let normalized = 1 - (distance / width)
        return normalized * normalized
    }
}

private struct CharacterStagePalette {
    let skinLight: Color
    let skinMid: Color
    let skinShadow: Color
    let hairPrimary: Color
    let hairSecondary: Color
    let outfitPrimary: Color
    let outfitSecondary: Color
    let accent: Color
    let ambientGlow: Color
    let lip: Color
    let iris: Color
    let shadow: Color

    static func palette(for characterID: String) -> CharacterStagePalette {
        switch characterID {
        case "lyra":
            return CharacterStagePalette(
                skinLight: Color(red: 0.98, green: 0.88, blue: 0.79),
                skinMid: Color(red: 0.93, green: 0.75, blue: 0.67),
                skinShadow: Color(red: 0.77, green: 0.57, blue: 0.52),
                hairPrimary: Color(red: 0.18, green: 0.16, blue: 0.23),
                hairSecondary: Color(red: 0.31, green: 0.27, blue: 0.39),
                outfitPrimary: Color(red: 0.25, green: 0.29, blue: 0.45),
                outfitSecondary: Color(red: 0.14, green: 0.18, blue: 0.29),
                accent: Color(red: 0.54, green: 0.71, blue: 0.95),
                ambientGlow: Color(red: 0.70, green: 0.79, blue: 1.0),
                lip: Color(red: 0.76, green: 0.42, blue: 0.49),
                iris: Color(red: 0.34, green: 0.48, blue: 0.75),
                shadow: Color.black.opacity(0.28)
            )
        case "sol":
            return CharacterStagePalette(
                skinLight: Color(red: 0.90, green: 0.71, blue: 0.55),
                skinMid: Color(red: 0.77, green: 0.55, blue: 0.41),
                skinShadow: Color(red: 0.55, green: 0.36, blue: 0.28),
                hairPrimary: Color(red: 0.11, green: 0.10, blue: 0.12),
                hairSecondary: Color(red: 0.25, green: 0.21, blue: 0.20),
                outfitPrimary: Color(red: 0.17, green: 0.32, blue: 0.32),
                outfitSecondary: Color(red: 0.09, green: 0.16, blue: 0.15),
                accent: Color(red: 0.96, green: 0.62, blue: 0.28),
                ambientGlow: Color(red: 1.0, green: 0.72, blue: 0.34),
                lip: Color(red: 0.60, green: 0.24, blue: 0.23),
                iris: Color(red: 0.27, green: 0.22, blue: 0.16),
                shadow: Color.black.opacity(0.30)
            )
        default:
            return CharacterStagePalette(
                skinLight: Color(red: 1.0, green: 0.89, blue: 0.78),
                skinMid: Color(red: 0.98, green: 0.76, blue: 0.66),
                skinShadow: Color(red: 0.81, green: 0.58, blue: 0.50),
                hairPrimary: Color(red: 0.17, green: 0.12, blue: 0.15),
                hairSecondary: Color(red: 0.34, green: 0.19, blue: 0.24),
                outfitPrimary: Color(red: 0.22, green: 0.28, blue: 0.43),
                outfitSecondary: Color(red: 0.47, green: 0.22, blue: 0.19),
                accent: Color(red: 0.99, green: 0.62, blue: 0.42),
                ambientGlow: Color(red: 1.0, green: 0.78, blue: 0.56),
                lip: Color(red: 0.77, green: 0.28, blue: 0.34),
                iris: Color(red: 0.24, green: 0.29, blue: 0.41),
                shadow: Color.black.opacity(0.28)
            )
        }
    }
}

private enum CharacterLook {
    case nova
    case lyra
    case sol

    init(characterID: String) {
        switch characterID {
        case "lyra":
            self = .lyra
        case "sol":
            self = .sol
        default:
            self = .nova
        }
    }
}

private struct CharacterStageBackground: View {
    let scene: CharacterScene
    let palette: CharacterStagePalette
    let metrics: CharacterStageMetrics
    let state: AvatarState
    let pose: CharacterStagePose

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)

        ZStack {
            shape
                .fill(baseGradient)

            sceneDecor
                .clipShape(shape)

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.black.opacity(0.12),
                            Color.black.opacity(0.34)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            shape
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1.1)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.ambientGlow.opacity(state == .error ? 0.18 : Double(pose.auraPulse)),
                            .clear
                        ],
                        center: .center,
                        startRadius: 12,
                        endRadius: metrics.size.width * 0.42
                    )
                )
                .blur(radius: 10)
                .offset(x: 0, y: -metrics.size.height * 0.05)
                .blendMode(.screen)

            Ellipse()
                .fill(Color.black.opacity(0.16))
                .frame(width: metrics.size.width * 0.72, height: metrics.size.height * 0.18)
                .blur(radius: 28)
                .offset(y: metrics.size.height * 0.34)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 24, y: 18)
    }

    private var baseGradient: LinearGradient {
        switch scene.lightingStyle {
        case "golden":
            return LinearGradient(
                colors: [
                    Color(red: 0.31, green: 0.28, blue: 0.37),
                    Color(red: 0.63, green: 0.41, blue: 0.28),
                    Color(red: 0.17, green: 0.14, blue: 0.19)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "neon":
            return LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.14, blue: 0.24),
                    Color(red: 0.19, green: 0.16, blue: 0.29),
                    Color(red: 0.07, green: 0.09, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.20, blue: 0.28),
                    Color(red: 0.24, green: 0.21, blue: 0.31),
                    Color(red: 0.12, green: 0.13, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var sceneDecor: some View {
        switch scene.backdropStyle {
        case "library-depth":
            libraryBackdrop
        case "city-bokeh":
            cityBackdrop
        default:
            sunroomBackdrop
        }
    }

    private var sunroomBackdrop: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: metrics.size.width * 0.05) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.24),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .padding(.horizontal, metrics.size.width * 0.08)
            .padding(.top, metrics.size.height * 0.07)
            .padding(.bottom, metrics.size.height * 0.22)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: metrics.size.width * 0.22)
                .blur(radius: 34)
                .rotationEffect(.degrees(-18))
                .offset(x: metrics.size.width * 0.18, y: -metrics.size.height * 0.15)

            Circle()
                .fill(Color(red: 1.0, green: 0.82, blue: 0.62).opacity(0.20))
                .frame(width: metrics.size.width * 0.30)
                .blur(radius: 20)
                .offset(x: -metrics.size.width * 0.23, y: -metrics.size.height * 0.20)
        }
    }

    private var libraryBackdrop: some View {
        ZStack {
            VStack(spacing: metrics.size.height * 0.035) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: metrics.size.width * 0.018) {
                        ForEach(0..<8, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    Color.white.opacity(((row + column) % 3 == 0) ? 0.14 : 0.07)
                                )
                                .frame(height: metrics.size.height * (column % 2 == 0 ? 0.12 : 0.10))
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.size.width * 0.08)
            .padding(.top, metrics.size.height * 0.10)
            .padding(.bottom, metrics.size.height * 0.26)
            .blur(radius: 0.4)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: metrics.size.width * 0.16)
                .blur(radius: 24)
                .rotationEffect(.degrees(12))
                .offset(x: -metrics.size.width * 0.12, y: -metrics.size.height * 0.10)
        }
    }

    private var cityBackdrop: some View {
        ZStack(alignment: .bottom) {
            VStack {
                HStack(spacing: metrics.size.width * 0.06) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill((index % 2 == 0 ? palette.accent : Color(red: 0.56, green: 0.72, blue: 1.0)).opacity(0.24))
                            .frame(width: metrics.size.width * (index % 2 == 0 ? 0.12 : 0.08))
                            .blur(radius: 16)
                    }
                }
                .padding(.top, metrics.size.height * 0.12)
                Spacer()
            }

            HStack(alignment: .bottom, spacing: metrics.size.width * 0.028) {
                ForEach(0..<9, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(index % 3 == 0 ? 0.16 : 0.08))
                        .frame(width: metrics.size.width * 0.07, height: metrics.size.height * [0.16, 0.22, 0.19, 0.28, 0.17, 0.24, 0.20, 0.15, 0.18][index])
                }
            }
            .padding(.horizontal, metrics.size.width * 0.08)
            .padding(.bottom, metrics.size.height * 0.19)
        }
    }
}

private struct CharacterPortrait: View {
    let character: CharacterProfile
    let scene: CharacterScene
    let pack: CharacterPackManifest
    let palette: CharacterStagePalette
    let pose: CharacterStagePose
    let metrics: CharacterStageMetrics
    let state: AvatarState

    private var look: CharacterLook {
        CharacterLook(characterID: character.id)
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(palette.shadow.opacity(0.40))
                .frame(width: 190, height: 36)
                .blur(radius: 16)
                .offset(y: 166)

            torsoLayer
                .offset(y: pose.bodyFloat * 0.55)

            neck
                .offset(y: 42 + pose.bodyFloat * 0.55)

            headLayer
                .offset(x: pose.headOffsetX, y: pose.headOffsetY + pose.bodyFloat * 0.6 - 4)
                .rotationEffect(pose.headTilt, anchor: .bottom)

            if look == .nova {
                Circle()
                    .fill(palette.accent.opacity(0.16))
                    .frame(width: 180, height: 180)
                    .blur(radius: 24)
                    .offset(y: -6)
                    .blendMode(.screen)
            }
        }
    }

    private var torsoLayer: some View {
        ZStack {
            TorsoShape(look: look)
                .fill(
                    LinearGradient(
                        colors: [palette.outfitPrimary, palette.outfitSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    TorsoShape(look: look)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                .frame(width: 236, height: 210)
                .shadow(color: Color.black.opacity(0.24), radius: 18, y: 18)

            clothingDetail
                .offset(y: 22)

            if state == .listening || state == .speaking {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 78, height: 10)
                    .blur(radius: 7)
                    .offset(y: 76 - pose.shoulderLift * 0.2)
            }
        }
        .offset(y: 124 + pose.shoulderLift * 0.35)
    }

    @ViewBuilder
    private var clothingDetail: some View {
        switch look {
        case .nova:
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .frame(width: 136, height: 110)
                HStack(spacing: 28) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 22, height: 94)
                        .rotationEffect(.degrees(12))
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 20, height: 82)
                        .rotationEffect(.degrees(-10))
                }
                .offset(y: -4)
            }
        case .lyra:
            VStack(spacing: 10) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 122, height: 18)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .frame(width: 150, height: 54)
            }
        case .sol:
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 38, height: 98)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.16))
                    .frame(width: 110, height: 104)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 38, height: 98)
            }
        }
    }

    private var neck: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [palette.skinLight, palette.skinMid],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 54, height: 74)
            .overlay(alignment: .top) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 28, height: 10)
                    .offset(y: 10)
            }
            .shadow(color: Color.black.opacity(0.10), radius: 7, y: 4)
    }

    private var headLayer: some View {
        ZStack {
            BackHairShape(look: look)
                .fill(
                    LinearGradient(
                        colors: [palette.hairSecondary, palette.hairPrimary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 172, height: look == .sol ? 148 : 176)
                .offset(y: look == .sol ? -12 : -4)

            ears

            face

            if look == .lyra {
                lyraHairSides
            }

            facialFeatures

            FrontHairShape(look: look)
                .fill(
                    LinearGradient(
                        colors: [palette.hairPrimary, palette.hairSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 154, height: look == .sol ? 102 : 126)
                .offset(y: look == .sol ? -48 : -42)

            accessory
        }
    }

    private var ears: some View {
        HStack(spacing: 102) {
            Circle()
                .fill(palette.skinMid)
                .frame(width: 18, height: 26)
            Circle()
                .fill(palette.skinMid)
                .frame(width: 18, height: 26)
        }
        .offset(y: 6)
    }

    private var face: some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [palette.skinLight, palette.skinMid],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 132, height: 156)
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 5)

            Ellipse()
                .fill(Color.white.opacity(0.18))
                .frame(width: 44, height: 84)
                .blur(radius: 3)
                .offset(x: -24, y: -12)

            Ellipse()
                .fill(palette.skinShadow.opacity(0.18))
                .frame(width: 26, height: 78)
                .blur(radius: 10)
                .offset(x: 30, y: 12)

            HStack(spacing: 48) {
                Circle()
                    .fill(Color(red: 0.96, green: 0.68, blue: 0.70).opacity(0.20))
                    .frame(width: 16)
                Circle()
                    .fill(Color(red: 0.96, green: 0.68, blue: 0.70).opacity(0.20))
                    .frame(width: 16)
            }
            .offset(y: 18)
        }
    }

    private var lyraHairSides: some View {
        HStack(spacing: 98) {
            Capsule(style: .continuous)
                .fill(palette.hairPrimary)
                .frame(width: 18, height: 108)
                .rotationEffect(.degrees(5))
            Capsule(style: .continuous)
                .fill(palette.hairPrimary)
                .frame(width: 18, height: 116)
                .rotationEffect(.degrees(-7))
        }
        .offset(y: 26)
    }

    private var facialFeatures: some View {
        ZStack {
            eyeRow
                .offset(y: -10)

            nose
                .offset(y: 16)

            mouth
                .offset(y: 48)

            if state == .error {
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(0.22))
                    .frame(width: 84, height: 10)
                    .blur(radius: 8)
                    .offset(y: 72)
            }
        }
    }

    private var eyeRow: some View {
        HStack(spacing: 36) {
            eye
            eye
        }
        .overlay(alignment: .topLeading) {
            eyebrows
        }
    }

    private var eye: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.96))
                .frame(width: 28, height: max(3.5, 15 - pose.blinkAmount * 11))

            Circle()
                .fill(palette.iris)
                .frame(width: max(4, 11 - pose.blinkAmount * 6))
                .overlay {
                    Circle()
                        .fill(Color.black.opacity(0.75))
                        .frame(width: max(2, 5 - pose.blinkAmount * 2.5))
                }
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 3, height: 3)
                        .offset(x: 2, y: 1)
                }
                .offset(x: pose.gazeX, y: pose.gazeY)
                .mask(
                    Capsule(style: .continuous)
                        .frame(width: 28, height: max(3.5, 15 - pose.blinkAmount * 11))
                )
        }
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.12))
                .frame(width: 30, height: 4)
                .offset(y: -7)
                .opacity(Double(1 - pose.blinkAmount * 0.55))
        }
    }

    private var eyebrows: some View {
        HStack(spacing: 30) {
            Capsule(style: .continuous)
                .fill(palette.hairPrimary.opacity(0.86))
                .frame(width: 24, height: 5)
                .rotationEffect(.degrees(-10 - Double(pose.browLift * 2)))
            Capsule(style: .continuous)
                .fill(palette.hairPrimary.opacity(0.86))
                .frame(width: 24, height: 5)
                .rotationEffect(.degrees(10 + Double(pose.browLift * 2)))
        }
        .offset(x: 12, y: -16 - pose.browLift)
    }

    private var nose: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: 5, y: 14), control: CGPoint(x: 7, y: 7))
            path.addQuadCurve(to: CGPoint(x: -2, y: 18), control: CGPoint(x: 4, y: 20))
        }
        .stroke(palette.skinShadow.opacity(0.44), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .frame(width: 16, height: 22)
    }

    private var mouth: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.18))
                .frame(width: mouthWidth * 1.02, height: mouthHeight * 1.04)
                .blur(radius: 0.8)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.lip, palette.lip.opacity(0.74)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: mouthWidth, height: mouthHeight)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }

            if pose.mouthOpen > 0.16 {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .frame(width: mouthWidth * 0.34, height: 3)
                    .offset(y: -mouthHeight * 0.2)
            }
        }
        .clipShape(Capsule(style: .continuous))
        .rotationEffect(.degrees(Double(-pose.smileCurve * 8)))
        .overlay(alignment: .top) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 8))
                path.addQuadCurve(
                    to: CGPoint(x: mouthWidth, y: 8),
                    control: CGPoint(x: mouthWidth / 2, y: 8 - (pose.smileCurve * 18))
                )
            }
            .stroke(Color.black.opacity(0.20), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: mouthWidth, height: 18)
        }
    }

    private var accessory: some View {
        Group {
            switch look {
            case .nova:
                HStack(spacing: 90) {
                    Circle()
                        .fill(palette.accent.opacity(0.88))
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(palette.accent.opacity(0.88))
                        .frame(width: 8, height: 8)
                }
                .offset(y: 34)
            case .lyra:
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 62, height: 16)
                    .offset(y: 88)
            case .sol:
                Capsule(style: .continuous)
                    .fill(palette.accent.opacity(0.80))
                    .frame(width: 34, height: 8)
                    .offset(x: 42, y: 38)
            }
        }
    }

    private var mouthWidth: CGFloat {
        switch look {
        case .lyra:
            return 30
        case .sol:
            return 38
        case .nova:
            return 34
        }
    }

    private var mouthHeight: CGFloat {
        let base: CGFloat = 10
        let stretched = base + pose.mouthOpen * 34
        return min(max(stretched, 8), 34)
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
                    colors: [Color.white.opacity(0.24), color.opacity(0.92), Color.white.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: metrics.emphasis == .hero ? 5 : 3, lineCap: .round)
            )
            .frame(width: 258, height: 258)
            .rotationEffect(.degrees(Double(pose.attentionLift * 11)))
            .blur(radius: 0.5)
    }
}

private struct StageBadge: View {
    let text: String
    let palette: CharacterStagePalette

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
                .fill(Color.black.opacity(0.26))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct TorsoShape: Shape {
    let look: CharacterLook

    func path(in rect: CGRect) -> Path {
        switch look {
        case .nova:
            return Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08))
                path.addCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY - rect.height * 0.16),
                    control1: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.02),
                    control2: CGPoint(x: rect.maxX, y: rect.midY)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.maxY - rect.height * 0.10),
                    control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.10)
                )
                path.addCurve(
                    to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08),
                    control1: CGPoint(x: rect.minX, y: rect.midY),
                    control2: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.02)
                )
            }
        case .lyra:
            return Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.maxY - rect.height * 0.14),
                    control1: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.08),
                    control2: CGPoint(x: rect.maxX, y: rect.midY)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.maxY - rect.height * 0.14),
                    control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.06)
                )
                path.addCurve(
                    to: CGPoint(x: rect.midX, y: rect.minY),
                    control1: CGPoint(x: rect.minX, y: rect.midY),
                    control2: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.08)
                )
            }
        case .sol:
            return Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04))
                path.addCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.maxY - rect.height * 0.10),
                    control1: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY),
                    control2: CGPoint(x: rect.maxX, y: rect.midY)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY - rect.height * 0.08),
                    control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.12)
                )
                path.addCurve(
                    to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04),
                    control1: CGPoint(x: rect.minX, y: rect.midY),
                    control2: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY)
                )
            }
        }
    }
}

private struct BackHairShape: Shape {
    let look: CharacterLook

    func path(in rect: CGRect) -> Path {
        switch look {
        case .nova:
            return Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.30))
                path.addQuadCurve(
                    to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04),
                    control: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.02)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.28),
                    control: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.02)
                )
                path.addCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.maxY - rect.height * 0.02),
                    control1: CGPoint(x: rect.maxX, y: rect.midY),
                    control2: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.maxY - rect.height * 0.12)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY - rect.height * 0.06),
                    control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.10)
                )
                path.addCurve(
                    to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.30),
                    control1: CGPoint(x: rect.minX - rect.width * 0.02, y: rect.maxY - rect.height * 0.12),
                    control2: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.midY)
                )
            }
        case .lyra:
            return Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.22))
                path.addQuadCurve(
                    to: CGPoint(x: rect.midX, y: rect.minY),
                    control: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.02)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.18),
                    control: CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.minY + rect.height * 0.02)
                )
                path.addCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.maxY - rect.height * 0.04),
                    control1: CGPoint(x: rect.maxX, y: rect.midY),
                    control2: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY - rect.height * 0.08)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.maxY),
                    control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.08)
                )
                path.addCurve(
                    to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.22),
                    control1: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.maxY - rect.height * 0.10),
                    control2: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.midY)
                )
            }
        case .sol:
            return Path { path in
                path.addEllipse(in: CGRect(
                    x: rect.minX + rect.width * 0.10,
                    y: rect.minY + rect.height * 0.04,
                    width: rect.width * 0.80,
                    height: rect.height * 0.82
                ))
            }
        }
    }
}

private struct FrontHairShape: Shape {
    let look: CharacterLook

    func path(in rect: CGRect) -> Path {
        switch look {
        case .nova:
            return Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.54))
                path.addQuadCurve(
                    to: CGPoint(x: rect.midX - rect.width * 0.04, y: rect.minY + rect.height * 0.08),
                    control: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.10)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY + rect.height * 0.18),
                    control: CGPoint(x: rect.midX + rect.width * 0.06, y: rect.minY + rect.height * 0.04)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.46),
                    control: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.04)
                )
                path.addCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.maxY),
                    control1: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY + rect.height * 0.74),
                    control2: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.maxY - rect.height * 0.14)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.54),
                    control: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.maxY + rect.height * 0.04)
                )
            }
        case .lyra:
            return Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.56))
                path.addQuadCurve(
                    to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.06),
                    control: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.12)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.52),
                    control: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.06)
                )
                path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.maxY))
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.maxY),
                    control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.06)
                )
                path.closeSubpath()
            }
        case .sol:
            return Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.56))
                path.addCurve(
                    to: CGPoint(x: rect.midX, y: rect.minY),
                    control1: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.12),
                    control2: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.minY + rect.height * 0.02)
                )
                path.addCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.54),
                    control1: CGPoint(x: rect.midX + rect.width * 0.16, y: rect.minY + rect.height * 0.02),
                    control2: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.14)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.56),
                    control: CGPoint(x: rect.midX, y: rect.maxY)
                )
            }
        }
    }
}
