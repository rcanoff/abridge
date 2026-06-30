import Foundation

extension VisionProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "recognize_text":
            recognizeText(payloadJson: payloadJson)
        case "scan_document":
            scanDocument(payloadJson: payloadJson)
        case "read_qr_code":
            readQrCode(payloadJson: payloadJson)
        case "detect_barcodes":
            detectBarcodes(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown vision operation: \(operation)")
        }
    }
}