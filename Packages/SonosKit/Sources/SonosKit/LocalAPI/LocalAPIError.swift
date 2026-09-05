import Foundation

public enum LocalAPIError: Error, Hashable, Sendable {
    /// The placeholder key was rejected (HTTP 400, ERROR_API_KEY_VALIDATION_FAILED).
    case invalidAPIKey
    /// "Authentication" is switched on in the Sonos app (HTTP 401 / ERROR_NOT_AUTHORIZED).
    case unauthorized
    /// The call went to a player that is no longer the group's coordinator.
    case coordinatorMoved(newCoordinatorID: String?)
    /// The group id no longer exists.
    case groupGone
    case http(status: Int)
    case decoding(String)

    static func from(status: Int, body: Data) -> LocalAPIError {
        let decoder = JSONDecoder()
        if let typed = try? decoder.decode(WireObjectType.self, from: body) {
            switch typed.objectType {
            case "groupCoordinatorChanged":
                if let changed = try? decoder.decode(WireCoordinatorChanged.self, from: body) {
                    return changed.groupStatus == "GROUP_STATUS_GONE" ? .groupGone : .coordinatorMoved(newCoordinatorID: changed.playerId)
                }
            case "globalError":
                if let error = try? decoder.decode(WireGlobalError.self, from: body) {
                    if error.errorCode == "ERROR_API_KEY_VALIDATION_FAILED" { return .invalidAPIKey }
                    if error.errorCode == "ERROR_NOT_AUTHORIZED" { return .unauthorized }
                }
            default:
                break
            }
        }
        if status == 401 { return .unauthorized }
        return .http(status: status)
    }
}
