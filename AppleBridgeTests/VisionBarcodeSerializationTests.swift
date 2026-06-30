@testable import AppleBridge
import Foundation
import Testing
import Vision

@Suite("VisionBarcodeSerialization")
struct VisionBarcodeSerializationTests {
    private let responseKeys = ["results"]

    private let barcodeObservationKeys = [
        "uuid",
        "confidence",
        "time_range",
        "originating_request_descriptor",
        "payload_string",
        "payload_data",
        "supplemental_payload_string",
        "supplemental_payload_data",
        "supplemental_composite_type",
        "is_gs1_data_carrier",
        "symbology",
        "is_color_inverted",
        "top_left",
        "top_right",
        "bottom_right",
        "bottom_left",
        "bounding_region",
    ]

    @Test
    @MainActor
    func detectBarcodesResponseIncludesTopLevelKeys() throws {
        let observations = try VisionTestFixtures.sampleBarcodeObservations()
        let object = try VisionBarcodeSerialization.detectBarcodesResponseJSONObject(observations: observations)

        for key in responseKeys {
            #expect(object.keys.contains(key), "Missing response key: \(key)")
        }
    }

    @Test
    @MainActor
    func barcodeObservationProjectionIncludesAllKeys() throws {
        let observations = try VisionTestFixtures.sampleBarcodeObservations()
        let observation = try #require(observations.first)
        let object = try VisionBarcodeSerialization.barcodeObservationJSONObject(from: observation)

        for key in barcodeObservationKeys {
            #expect(object.keys.contains(key), "Missing barcode observation key: \(key)")
        }
    }

    @Test
    @MainActor
    func barcodeObservationSymbologyUsesRawValue() throws {
        let observations = try VisionTestFixtures.sampleBarcodeObservations()
        let observation = try #require(observations.first)

        let object = try VisionBarcodeSerialization.barcodeObservationJSONObject(from: observation)
        let symbology = try #require(object["symbology"] as? String)

        let identifier = try VisionDocumentObservationSerialization
            .barcodeSymbologyIdentifier(from: observation.symbology)
        #expect(symbology == identifier)
        #expect(!symbology.contains("(_rawValue:"))
        #expect(!symbology.contains("BarcodeSymbology("))
        #expect(symbology == "qr")
    }

    @Test
    @MainActor
    func barcodeSymbologyIdentifierReturnsCodableKey() throws {
        let observations = try VisionTestFixtures.sampleBarcodeObservations()
        let observation = try #require(observations.first)

        let identifier = try VisionDocumentObservationSerialization.barcodeSymbologyIdentifier(
            from: observation.symbology
        )
        #expect(identifier == "qr")
    }
}
