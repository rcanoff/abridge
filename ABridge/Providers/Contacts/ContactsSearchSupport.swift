@preconcurrency import Contacts
import Foundation

enum ContactsSearchSupport {
    static func intersectContacts(_ contactSets: [[CNContact]]) -> [CNContact] {
        guard let firstSet = contactSets.first else {
            return []
        }

        if contactSets.count == 1 {
            return firstSet
        }

        var commonIdentifiers = Set(firstSet.map(\.identifier))
        for contactSet in contactSets.dropFirst() {
            commonIdentifiers.formIntersection(Set(contactSet.map(\.identifier)))
        }

        return firstSet.filter { commonIdentifiers.contains($0.identifier) }
    }
}
