import Foundation

struct AppleBridgeLaunchDependencies {
    let singleInstanceChecker: any SingleInstanceChecking
    let storeMaker: any AppleBridgeAppStoreMaking
    let appQuitter: any AppQuitting
}
