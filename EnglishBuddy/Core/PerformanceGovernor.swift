import Combine
import Foundation

@MainActor
final class PerformanceGovernor: ObservableObject {
    @Published private(set) var profile: DevicePerformanceProfile

    init(profile: DevicePerformanceProfile = .default) {
        self.profile = profile
    }

    func apply(settings: CompanionSettings) {
        profile = Self.resolveProfile(
            preferredTier: settings.performanceTier,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    func clampedMemoryContext(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > profile.maximumPromptContextCharacters else { return trimmed }
        return String(trimmed.prefix(profile.maximumPromptContextCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    func trimmedPromptTurns(_ turns: [ConversationTurn]) -> [ConversationTurn] {
        guard turns.count > profile.maximumPromptTurns else { return turns }
        return Array(turns.suffix(profile.maximumPromptTurns))
    }

    static func resolveProfile(
        preferredTier: PerformanceTier,
        lowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> DevicePerformanceProfile {
        let deviceClass = resolvedDeviceClass(lowPowerModeEnabled: lowPowerModeEnabled)
        let thermalPenalty = thermalState == .serious || thermalState == .critical
        let shouldAggressivelyConserve = lowPowerModeEnabled || thermalPenalty || preferredTier == .efficiency

        switch deviceClass {
        case .air:
            return DevicePerformanceProfile(
                deviceClass: deviceClass,
                preferredTier: preferredTier,
                lowPowerModeEnabled: lowPowerModeEnabled,
                thermalState: thermalState,
                allowsContinuousHeroAnimation: shouldAggressivelyConserve == false,
                callHeroFrameRate: shouldAggressivelyConserve ? 15 : 18,
                assistantCaptionCommitInterval: shouldAggressivelyConserve ? 0.12 : 0.09,
                userCaptionCommitInterval: shouldAggressivelyConserve ? 0.08 : 0.06,
                audioLevelQuantizationStep: shouldAggressivelyConserve ? 0.10 : 0.08,
                maximumPromptContextCharacters: shouldAggressivelyConserve ? 360 : 420,
                maximumPromptTurns: shouldAggressivelyConserve ? 5 : 6,
                prefersStaticPreparingCard: true,
                reducesBackdropEffects: true,
                prefersOpaqueSubtitleOverlay: true
            )
        case .balanced:
            return DevicePerformanceProfile(
                deviceClass: deviceClass,
                preferredTier: preferredTier,
                lowPowerModeEnabled: lowPowerModeEnabled,
                thermalState: thermalState,
                allowsContinuousHeroAnimation: thermalPenalty == false,
                callHeroFrameRate: shouldAggressivelyConserve ? 18 : 24,
                assistantCaptionCommitInterval: shouldAggressivelyConserve ? 0.09 : 0.07,
                userCaptionCommitInterval: shouldAggressivelyConserve ? 0.06 : 0.05,
                audioLevelQuantizationStep: shouldAggressivelyConserve ? 0.08 : 0.05,
                maximumPromptContextCharacters: shouldAggressivelyConserve ? 460 : 560,
                maximumPromptTurns: shouldAggressivelyConserve ? 6 : 8,
                prefersStaticPreparingCard: shouldAggressivelyConserve,
                reducesBackdropEffects: shouldAggressivelyConserve,
                prefersOpaqueSubtitleOverlay: shouldAggressivelyConserve
            )
        case .flagship:
            return DevicePerformanceProfile(
                deviceClass: deviceClass,
                preferredTier: preferredTier,
                lowPowerModeEnabled: lowPowerModeEnabled,
                thermalState: thermalState,
                allowsContinuousHeroAnimation: true,
                callHeroFrameRate: preferredTier == .quality ? 30 : 24,
                assistantCaptionCommitInterval: 0.06,
                userCaptionCommitInterval: 0.05,
                audioLevelQuantizationStep: preferredTier == .quality ? 0.04 : 0.05,
                maximumPromptContextCharacters: preferredTier == .quality ? 720 : 620,
                maximumPromptTurns: preferredTier == .quality ? 10 : 8,
                prefersStaticPreparingCard: false,
                reducesBackdropEffects: lowPowerModeEnabled,
                prefersOpaqueSubtitleOverlay: lowPowerModeEnabled
            )
        }
    }

    private static func resolvedDeviceClass(lowPowerModeEnabled: Bool) -> DevicePerformanceClass {
        let environment = ProcessInfo.processInfo.environment
        if let forced = environment["ENGLISHBUDDY_DEVICE_PROFILE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            switch forced {
            case "air":
                return .air
            case "flagship", "pro":
                return .flagship
            case "balanced":
                return .balanced
            default:
                break
            }
        }

        let physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let simulatorDeviceName = environment["SIMULATOR_DEVICE_NAME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let modelIdentifier = currentModelIdentifier(environment: environment)?.lowercased()

        if let simulatorDeviceName {
            if simulatorDeviceName.contains("air") || simulatorDeviceName.hasSuffix(" e") || simulatorDeviceName.hasSuffix("e") {
                return .air
            }
            if simulatorDeviceName.contains("pro max") || simulatorDeviceName.contains(" pro") {
                return .flagship
            }
            if simulatorDeviceName.contains("plus") {
                return lowPowerModeEnabled ? .air : .balanced
            }
        }

        if let modelIdentifier {
            if knownAirIdentifiers.contains(modelIdentifier) {
                return .air
            }
            if knownFlagshipIdentifiers.contains(modelIdentifier) {
                return .flagship
            }
        }

        if lowPowerModeEnabled || physicalMemoryGB < 6.5 {
            return .air
        }

        if physicalMemoryGB <= 6.9 {
            return .air
        }

        if physicalMemoryGB >= 9.5 {
            return .flagship
        }

        return .balanced
    }

    private static func currentModelIdentifier(environment: [String: String]) -> String? {
        if let simulated = environment["SIMULATOR_MODEL_IDENTIFIER"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           simulated.isEmpty == false {
            return simulated
        }

        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        return identifier.isEmpty ? nil : identifier
    }

    private static let knownAirIdentifiers: Set<String> = [
        "iphone18,4"
    ]

    private static let knownFlagshipIdentifiers: Set<String> = [
        "iphone15,2", // iPhone 14 Pro
        "iphone15,3", // iPhone 14 Pro Max
        "iphone16,1", // iPhone 15 Pro
        "iphone16,2", // iPhone 15 Pro Max
        "iphone17,1", // iPhone 16 Pro
        "iphone17,2", // iPhone 16 Pro Max
        "iphone18,1", // iPhone 17 Pro
        "iphone18,2"  // iPhone 17 Pro Max
    ]
}
