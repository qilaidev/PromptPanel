import Foundation

@MainActor
final class PanelVisibilityCoordinator {
    enum State {
        case hidden
        case showing
        case visible
        case hiding
    }

    enum ToggleAction {
        case show
        case hide
    }

    private(set) var state: State = .hidden

    func toggleAction() -> ToggleAction {
        switch state {
        case .hidden, .hiding:
            return .show
        case .showing, .visible:
            return .hide
        }
    }

    func beginShow() -> Bool {
        guard state == .hidden else {
            return false
        }
        state = .showing
        return true
    }

    func finishShow() {
        state = .visible
    }

    func beginHide() -> Bool {
        switch state {
        case .hidden, .hiding:
            return false
        case .showing, .visible:
            state = .hiding
            return true
        }
    }

    func finishHide() {
        state = .hidden
    }
}
