import Foundation

struct ABridgeLaunchDependencies {
    let singleInstanceChecker: any SingleInstanceChecking
    let storeMaker: any ABridgeAppStoreMaking
    let appQuitter: any AppQuitting
}
