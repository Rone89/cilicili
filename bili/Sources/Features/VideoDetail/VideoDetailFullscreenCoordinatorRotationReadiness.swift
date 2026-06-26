import UIKit

extension VideoDetailFullscreenCoordinator {
    func canResolveRotationDecodePath(_ decodePath: PlayerEngineDiagnostics.DecodePath?) -> Bool {
        guard let decodePath else { return false }
        return decodePath != .unknown
    }

    func canUseInlineRotation(_ allowsInlineRotation: Bool) -> Bool {
        allowsInlineRotation
    }
}
