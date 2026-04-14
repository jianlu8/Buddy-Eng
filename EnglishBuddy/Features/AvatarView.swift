import SwiftUI

enum AvatarEmphasis {
    case compact
    case hero
}

struct MiraAvatarView: View {
    let state: AvatarState
    let audioLevel: Double
    var emphasis: AvatarEmphasis = .compact
    var characterID: String? = nil
    var sceneID: String? = nil

    var body: some View {
        CharacterStageView(
            state: state,
            audioLevel: audioLevel,
            emphasis: emphasis,
            characterID: characterID,
            sceneID: sceneID
        )
    }
}
