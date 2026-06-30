import Foundation

/// Synchronous FFI entry point from Rust background threads. EventKit types are `@MainActor`;
/// this type is `Sendable` because it stores only a main-actor factory closure and hops to the
/// main thread before touching EventKit.
final class AppleProviderBridge: ProviderBridge, Sendable {
    private let makeEventKitProvider: @MainActor @Sendable () -> EventKitProvider
    private let makeContactsProvider: @MainActor @Sendable () -> ContactsProvider
    private let makeMapKitProvider: @MainActor @Sendable () -> MapKitProvider
    private let makeVisionProvider: @MainActor @Sendable () -> VisionProvider

    init(
        makeEventKitProvider: @escaping @MainActor @Sendable () -> EventKitProvider = {
            LiveEventKitEnvironment.sharedProvider
        },
        makeContactsProvider: @escaping @MainActor @Sendable () -> ContactsProvider = {
            LiveContactsEnvironment.sharedProvider
        },
        makeMapKitProvider: @escaping @MainActor @Sendable () -> MapKitProvider = {
            LiveMapKitEnvironment.sharedProvider
        },
        makeVisionProvider: @escaping @MainActor @Sendable () -> VisionProvider = {
            LiveVisionEnvironment.sharedProvider
        }
    ) {
        self.makeEventKitProvider = makeEventKitProvider
        self.makeContactsProvider = makeContactsProvider
        self.makeMapKitProvider = makeMapKitProvider
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

    /// Test seam: capture the injected MapKit provider on the main actor.
    @MainActor
    convenience init(mapKitProvider: MapKitProvider) {
        self.init(makeMapKitProvider: { [mapKitProvider] in mapKitProvider })
    }

    /// Test seam: capture the injected Vision provider on the main actor.
    @MainActor
    convenience init(visionProvider: VisionProvider) {
        self.init(makeVisionProvider: { [visionProvider] in visionProvider })
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
            return Self.performOnMainActor { [makeMapKitProvider] in
                let provider = makeMapKitProvider()
                return provider.handle(operation: request.operation, payloadJson: request.payloadJson)
            }
        case "vision":
            return Self.performOnMainActor { [makeVisionProvider] in
                let provider = makeVisionProvider()
                return provider.handle(operation: request.operation, payloadJson: request.payloadJson)
            }
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
