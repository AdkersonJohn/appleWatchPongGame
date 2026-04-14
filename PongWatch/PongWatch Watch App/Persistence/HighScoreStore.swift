import Foundation

struct HighScoreStore {
    static let userDefaultsKey = "highScore"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: Int {
        defaults.integer(forKey: Self.userDefaultsKey)
    }

    @discardableResult
    func updateIfHigher(newScore: Int) -> Bool {
        guard newScore > current else { return false }
        defaults.set(newScore, forKey: Self.userDefaultsKey)
        return true
    }
}
