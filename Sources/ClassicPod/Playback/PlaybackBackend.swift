import Foundation
import PodCore

@MainActor protocol PlaybackBackend: AnyObject {
    var snapshot: PlaybackSnapshot { get }
    var onChange: ((PlaybackSnapshot) -> Void)? { get set }
    func play(_ tracks: [Track], at index: Int) async throws
    func resume() async throws
    func pause() async throws
    func next() async throws
    func previous() async throws
    func seek(_ seconds: Double) async throws
    func setVolume(_ value: Double) async throws
    func stopObserving()
}
