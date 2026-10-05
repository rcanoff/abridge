import Contacts
import Foundation

enum ContactsPermissionError: LocalizedError, Equatable {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case let .requestFailed(message):
            message
        }
    }
}

@MainActor
final class ContactsPermissionService: ContactsPermissionChecking {
    typealias AuthorizationStatusProvider = @MainActor () -> CNAuthorizationStatus
    typealias RequestAccessHandler = @MainActor () async throws -> ContactsPermissionStatus

    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let requestAccessHandler: RequestAccessHandler
    private var sessionStatus: ContactsPermissionStatus?

    init(
        authorizationStatusProvider: AuthorizationStatusProvider? = nil,
        requestAccessHandler: RequestAccessHandler? = nil
    ) {
        self.authorizationStatusProvider = authorizationStatusProvider ?? {
            CNContactStore.authorizationStatus(for: .contacts)
        }
        self.requestAccessHandler = requestAccessHandler ?? {
            try await Self.requestAccess()
        }
    }

    func currentStatus() -> ContactsPermissionStatus {
        let mapped = ContactsPermissionStatusMapper.map(authorizationStatusProvider())
        if mapped != .notDetermined {
            sessionStatus = nil
            return mapped
        }
        return sessionStatus ?? mapped
    }

    func requestAccess() async throws -> ContactsPermissionStatus {
        let result = try await requestAccessHandler()
        if result.grantsReadAccess {
            sessionStatus = result
        } else {
            sessionStatus = nil
        }
        return result
    }

    private static func requestAccess() async throws -> ContactsPermissionStatus {
        try await withCheckedThrowingContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(
                        throwing: ContactsPermissionError.requestFailed(error.localizedDescription)
                    )
                    return
                }

                if granted {
                    continuation.resume(returning: .authorized)
                } else {
                    continuation.resume(returning: .denied)
                }
            }
        }
    }
}
