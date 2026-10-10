import CoreLocation
import Foundation

enum CoreLocationSerialization {
    static func jsonString(from object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CoreLocationProviderError.serializationFailed
        }
        return string
    }

    static func getCurrentLocationResponseJSONObject(location: CLLocation) -> [String: Any] {
        ["location": locationJSONObject(from: location)]
    }

    static func locationJSONObject(from location: CLLocation) -> [String: Any] {
        [
            "coordinate": coordinateJSONObject(from: location.coordinate),
            "altitude": location.altitude,
            "horizontal_accuracy": location.horizontalAccuracy,
            "vertical_accuracy": location.verticalAccuracy,
            "course": location.course,
            "speed": location.speed,
            "timestamp": iso8601String(from: location.timestamp),
            "floor": jsonValueFloor(location.floor),
        ]
    }

    static func coordinateJSONObject(from coordinate: CLLocationCoordinate2D) -> [String: Any] {
        [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
        ]
    }

    private static func jsonValueFloor(_ floor: CLFloor?) -> Any {
        guard let floor else { return NSNull() }
        return [
            "level": floor.level,
        ]
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
