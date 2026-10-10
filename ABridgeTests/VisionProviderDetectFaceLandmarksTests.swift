@testable import ABridge
import Foundation
import Testing
import Vision

@Suite("VisionProviderDetectFaceLandmarks")
struct VisionProviderDetectFaceLandmarksTests {
    @Test
    @MainActor
    func detectFaceLandmarksRejectsInvalidBase64() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(
            operation: "detect_face_landmarks",
            payloadJson: #"{"image_data":"not-valid-base64!!!"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("base64") == true)
    }

    @Test
    @MainActor
    func detectFaceLandmarksRejectsUnsupportedRevision() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(
            operation: "detect_face_landmarks",
            payloadJson: #"{"image_data":"aGVsbG8=","revision":999}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("revision") == true)
    }

    @Test
    @MainActor
    func detectFaceLandmarksRejectsInvalidRegionOfInterest() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(
            operation: "detect_face_landmarks",
            payloadJson: #"""
            {"image_data":"aGVsbG8=","region_of_interest":{
                "origin":{"x":-0.1,"y":0.2},"size":{"width":0.5,"height":0.6}
            }}
            """#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("region_of_interest") == true)
    }

    @Test
    @MainActor
    func detectFaceLandmarksRejectsInvalidConstellation() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(
            operation: "detect_face_landmarks",
            payloadJson: #"{"image_data":"aGVsbG8=","constellation":"invalid"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("constellation") == true)
    }

    @Test
    @MainActor
    func detectFaceLandmarksReturnsSerializedResults() throws {
        let observations = try VisionTestFixtures.sampleFaceObservations()
        let store = MockVisionStore()
        store.faceObservations = observations
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.samplePortraitImageData()
        let encoded = imageData.base64EncodedString()

        let response = provider.handle(
            operation: "detect_face_landmarks",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )

        #expect(response.ok == true)
        let payloadData = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        let results = decoded?["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
        #expect(results?.first?.keys.contains("bounding_box") == true)
        #expect(results?.first?.keys.contains("landmarks") == true)
    }

    @Test
    @MainActor
    func detectFaceLandmarksForwardsOptionalArgumentsToStore() throws {
        let observations = try VisionTestFixtures.sampleFaceObservations()
        let store = MockVisionStore()
        store.faceObservations = observations
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.samplePortraitImageData()
        let encoded = imageData.base64EncodedString()

        _ = provider.handle(
            operation: "detect_face_landmarks",
            payloadJson: #"""
            {"image_data":"\#(
                encoded
            )","constellation":"65_points","region_of_interest":{
                "origin":{"x":0.1,"y":0.2},"size":{"width":0.5,"height":0.6}
            }}
            """#
        )

        #expect(store.lastDetectFaceLandmarksRequest?.constellation == .constellation65Points)
        #expect(store.lastDetectFaceLandmarksRequest?.regionOfInterest != nil)
    }
}
