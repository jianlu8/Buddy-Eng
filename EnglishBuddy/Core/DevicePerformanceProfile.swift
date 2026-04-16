import Foundation

enum DevicePerformanceClass: String, Equatable, Sendable {
    case air
    case balanced
    case flagship
}

struct DevicePerformanceProfile: Equatable, Sendable {
    var deviceClass: DevicePerformanceClass
    var preferredTier: PerformanceTier
    var lowPowerModeEnabled: Bool
    var thermalState: ProcessInfo.ThermalState
    var allowsContinuousHeroAnimation: Bool
    var callHeroFrameRate: Double
    var assistantCaptionCommitInterval: TimeInterval
    var userCaptionCommitInterval: TimeInterval
    var audioLevelQuantizationStep: Double
    var maximumPromptContextCharacters: Int
    var maximumPromptTurns: Int
    var prefersStaticPreparingCard: Bool
    var reducesBackdropEffects: Bool
    var prefersOpaqueSubtitleOverlay: Bool

    static let `default` = DevicePerformanceProfile(
        deviceClass: .balanced,
        preferredTier: .balanced,
        lowPowerModeEnabled: false,
        thermalState: .nominal,
        allowsContinuousHeroAnimation: true,
        callHeroFrameRate: 24,
        assistantCaptionCommitInterval: 0.06,
        userCaptionCommitInterval: 0.05,
        audioLevelQuantizationStep: 0.05,
        maximumPromptContextCharacters: 560,
        maximumPromptTurns: 8,
        prefersStaticPreparingCard: false,
        reducesBackdropEffects: false,
        prefersOpaqueSubtitleOverlay: false
    )
}
