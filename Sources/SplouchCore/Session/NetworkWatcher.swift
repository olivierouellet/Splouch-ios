import Foundation
import Observation
#if canImport(Network)
import Network
#endif

/// Network restored is the second C-05 trigger, beside foregrounding. The shell
/// probes every socket when `isOnline` turns true.
@MainActor
@Observable
public final class NetworkWatcher {
    public private(set) var isOnline = true

    #if canImport(Network)
    private var monitor: NWPathMonitor?
    #endif

    public init() {}

    public func start() {
        #if canImport(Network)
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor = m
        m.start(queue: .global(qos: .utility))
        #endif
    }

    public func stop() {
        #if canImport(Network)
        monitor?.cancel()
        monitor = nil
        #endif
    }
}
