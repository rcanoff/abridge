import Foundation

/// Synchronous FFI entry point from Rust background threads. EventKit types are `@MainActor`;
/// this type is `Sendable` because it stores only a main-actor factory closure and hops to the
/// main thread before touching EventKit.
final class AppleProviderBridge: ProviderBridge, Sendable {
    private let makeEventKitProvider: @MainActor @Sendable () -> EventKitProvider
    private let makeContactsProvider: @MainActor @Sendable () -> ContactsProvider
    /// Not MainActor: MapKit handle waits off-main; a full `main.sync` hop deadlocks MapKit network APIs.
    private let makeMapKitProvider: @Sendable () -> MapKitProvider
    /// Not MainActor: Core Location handle waits off-main; a full `main.sync` hop deadlocks delegate callbacks.
    private let makeCoreLocationProvider: @Sendable () -> CoreLocationProvider
    /// Not MainActor: Vision runs on its own worker thread so long requests never block the UI.
    private let makeVisionProvider: @Sendable () -> VisionProvider

    init(
        makeEventKitProvider: @escaping @MainActor @Sendable () -> EventKitProvider = {
            LiveEventKitEnvironment.sharedProvider
        },
        makeContactsProvider: @escaping @MainActor @Sendable () -> ContactsProvider = {
            LiveContactsEnvironment.sharedProvider
        },
        makeMapKitProvider: @escaping @Sendable () -> MapKitProvider = {
            LiveMapKitEnvironment.sharedProvider
        },
        makeCoreLocationProvider: @escaping @Sendable () -> CoreLocationProvider = {
            LiveCoreLocationEnvironment.sharedProvider
        },
        makeVisionProvider: @escaping @Sendable () -> VisionProvider = {
            LiveVisionEnvironment.sharedProvider
        }
    ) {
        self.makeEventKitProvider = makeEventKitProvider
        self.makeContactsProvider = makeContactsProvider
        self.makeMapKitProvider = makeMapKitProvider
        self.makeCoreLocationProvider = makeCoreLocationProvider
        self.makeVisionProvider = makeVisionProvider
    }

    /// Test seam: capture the injected provider on the main actor; the factory runs only inside
    /// `performOnMainActor`, so the `EventKitProvider` reference is never read off the main actor.
    @MainActor
    convenience init(eventKitProvider: EventKitProvider) {
        self.init(makeEventKitProvider: { [eventKitProvider] in eventKitProvider })
    }

    /// Test seam: capture the injected contacts provider on the main actor.
    @MainActor
    convenience init(contactsProvider: ContactsProvider) {
        self.init(makeContactsProvider: { [contactsProvider] in contactsProvider })
    }

    /// Test seam: capture the injected MapKit provider.
    convenience init(mapKitProvider: MapKitProvider) {
        nonisolated(unsafe) let provider = mapKitProvider
        self.init(makeMapKitProvider: { provider })
    }

    /// Test seam: capture the injected Core Location provider.
    convenience init(coreLocationProvider: CoreLocationProvider) {
        nonisolated(unsafe) let provider = coreLocationProvider
        self.init(makeCoreLocationProvider: { provider })
    }

    /// Test seam: capture the injected Vision provider.
    convenience init(visionProvider: VisionProvider) {
        self.init(makeVisionProvider: { visionProvider })
    }

    func callProvider(request: ProviderRequest) -> ProviderResponse {
        switch request.provider {
        case "eventkit":
            return Self.performOnMainActor { [makeEventKitProvider] in
                let provider = makeEventKitProvider()
                return provider.handle(operation: request.operation, payloadJson: request.payloadJson)
            }
        case "contacts":
            return Self.performOnMainActor { [makeContactsProvider] in
                let provider = makeContactsProvider()
                return provider.handle(operation: request.operation, payloadJson: request.payloadJson)
            }
        case "mapkit":
            // Do not use `performOnMainActor` / `main.sync` for the whole call. MapKit network
            // APIs never complete while the main queue is blocked; the store waits off-main.
            let provider = makeMapKitProvider()
            return provider.handle(operation: request.operation, payloadJson: request.payloadJson)
        case "corelocation":
            // Do not use `performOnMainActor` / `main.sync` for the whole call. Core Location
            // delegate callbacks never fire while the main queue is blocked; the store waits off-main.
            let provider = makeCoreLocationProvider()
            return provider.handle(operation: request.operation, payloadJson: request.payloadJson)
        case "vision":
            let provider = makeVisionProvider()
            return provider.handle(operation: request.operation, payloadJson: request.payloadJson)
        default:
            let payload: [String: String] = [
                "code": "unknown_provider",
                "message": "Unknown provider: \(request.provider)",
            ]
            let errorJson = (try? JSONSerialization.data(withJSONObject: payload))
                .flatMap { String(data: $0, encoding: .utf8) } ?? #"{"code":"unknown_provider"}"#
            return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
        }
    }

    /// Hop to the main actor for synchronous FFI callbacks without `DispatchQueue.main.sync` deadlock:
    /// callers already on the main thread run inline; all other threads block on `main.sync`.
    /// `assumeIsolated` is safe in both branches because main-thread execution implies main-actor isolation.
    private static func performOnMainActor<T: Sendable>(_ work: @MainActor @Sendable () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(work)
        }

        return DispatchQueue.main.sync {
            dispatchPrecondition(condition: .onQueue(.main))
            return MainActor.assumeIsolated(work)
        }
    }
}
