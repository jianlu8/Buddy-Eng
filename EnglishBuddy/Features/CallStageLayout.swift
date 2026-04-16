import SwiftUI

struct CallStageLayout: Equatable {
    let stageSpec: CharacterStageLayoutSpec
    let performanceProfile: DevicePerformanceProfile
    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets
    let subtitleMode: SubtitleOverlayMode

    init(
        surfaceKind: CharacterSurfaceKind = .callHero,
        performanceProfile: DevicePerformanceProfile,
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets,
        subtitleMode: SubtitleOverlayMode
    ) {
        stageSpec = surfaceKind.defaultLayoutSpec
        self.performanceProfile = performanceProfile
        self.containerSize = containerSize
        self.safeAreaInsets = safeAreaInsets
        self.subtitleMode = subtitleMode
    }

    var horizontalPadding: CGFloat { 18 }
    var headerTopPadding: CGFloat { max(18, safeAreaInsets.top + 8) }
    var controlsBottomPadding: CGFloat { max(18, safeAreaInsets.bottom + 12) }
    var controlsReservedHeight: CGFloat { 84 + controlsBottomPadding }

    var collapsedSubtitleHeight: CGFloat {
        let minimum = performanceProfile.deviceClass == .air ? 152.0 : 168.0
        return max(minimum, containerSize.height * 0.22)
    }

    var expandedSubtitleHeight: CGFloat {
        min(max(300, containerSize.height * 0.42), containerSize.height * 0.48)
    }

    var activeSubtitleHeight: CGFloat {
        subtitleMode == .collapsed ? collapsedSubtitleHeight : expandedSubtitleHeight
    }

    var subtitleBottomPadding: CGFloat {
        controlsReservedHeight + 10
    }

    var headerReservedHeight: CGFloat {
        performanceProfile.deviceClass == .air ? 108 : 116
    }

    var stageContainerHeight: CGFloat {
        let subtitleReservation = subtitleMode == .collapsed
            ? collapsedSubtitleHeight * 0.72
            : expandedSubtitleHeight * 0.82
        let available = containerSize.height - headerReservedHeight - controlsReservedHeight - subtitleReservation
        return min(max(available, 300), containerSize.height * 0.58)
    }

    var stageContainerSize: CGSize {
        CGSize(width: max(280, containerSize.width - (horizontalPadding * 2)), height: stageContainerHeight)
    }

    var stageSize: CGSize {
        stageSpec.stageSize(in: stageContainerSize)
    }

    var stageVerticalOffset: CGFloat {
        stageSpec.verticalOffset(in: stageContainerSize)
            + (subtitleMode == .expanded ? -12 : 0)
            + (performanceProfile.deviceClass == .air ? -4 : 0)
    }

    func subtitlePanelHeight(dragOffset: CGFloat) -> CGFloat {
        let baseHeight = activeSubtitleHeight
        let draggedHeight = baseHeight - dragOffset
        return min(max(draggedHeight, collapsedSubtitleHeight), expandedSubtitleHeight)
    }

    func overlayRestingOffset(dragOffset: CGFloat) -> CGFloat {
        let clamped = min(
            max(dragOffset, -(expandedSubtitleHeight - collapsedSubtitleHeight)),
            expandedSubtitleHeight - collapsedSubtitleHeight
        )
        return max(0, clamped * 0.08)
    }
}
