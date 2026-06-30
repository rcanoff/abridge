import DataDetection
import Foundation
import Vision

enum VisionDocumentDataDetectorSerialization {
    static func matchJSONObject(
        from match: DocumentObservation.Container.DataDetectorMatch,
        transcript: String,
        boundingRegion: [String: Any]
    ) -> [String: Any] {
        [
            "match": matchDetailsRootJSONObject(from: match.match, transcript: transcript),
            "bounding_region": boundingRegion,
        ]
    }

    private static func matchDetailsRootJSONObject(
        from match: DataDetector.Match,
        transcript: String
    ) -> [String: Any] {
        [
            "range": stringRangeJSONObject(from: match.range, in: transcript),
            "preferred_highlight_style": highlightStyleString(from: match.preferredHighlightStyle),
            "details": detailsJSONObject(from: match.details),
        ]
    }

    private static func detailsJSONObject(from details: DataDetector.Match.SemanticDetails) -> [String: Any] {
        switch details {
        case let .link(link):
            linkDetailsJSONObject(from: link)
        case let .emailAddress(email):
            emailDetailsJSONObject(from: email)
        case let .phoneNumber(phone):
            phoneDetailsJSONObject(from: phone)
        case let .postalAddress(address):
            postalAddressDetailsJSONObject(from: address)
        case let .calendarEvent(event):
            calendarEventDetailsJSONObject(from: event)
        default:
            trailingDetailsJSONObject(from: details)
        }
    }

    private static func trailingDetailsJSONObject(
        from details: DataDetector.Match.SemanticDetails
    ) -> [String: Any] {
        switch details {
        case let .moneyAmount(amount):
            moneyAmountDetailsJSONObject(from: amount)
        case let .flightNumber(flight):
            flightNumberDetailsJSONObject(from: flight)
        case let .shipmentTrackingNumber(shipment):
            shipmentDetailsJSONObject(from: shipment)
        case let .measurement(measurement):
            measurementDetailsJSONObject(from: measurement)
        case let .paymentIdentifier(payment):
            paymentIdentifierDetailsJSONObject(from: payment)
        default:
            ["type": "unknown"]
        }
    }

    private static func linkDetailsJSONObject(
        from link: DataDetector.Match.SemanticDetails.Link
    ) -> [String: Any] {
        ["type": "link", "url": link.url.absoluteString]
    }

    private static func emailDetailsJSONObject(
        from email: DataDetector.Match.SemanticDetails.EmailAddress
    ) -> [String: Any] {
        [
            "type": "email_address",
            "email_address": email.emailAddress,
            "label": VisionSerialization.jsonValue(email.label),
        ]
    }

    private static func phoneDetailsJSONObject(
        from phone: DataDetector.Match.SemanticDetails.PhoneNumber
    ) -> [String: Any] {
        [
            "type": "phone_number",
            "phone_number": phone.phoneNumber,
            "label": VisionSerialization.jsonValue(phone.label),
        ]
    }

    private static func postalAddressDetailsJSONObject(
        from address: DataDetector.Match.SemanticDetails.PostalAddress
    ) -> [String: Any] {
        [
            "type": "postal_address",
            "full_address": address.fullAddress,
            "street": VisionSerialization.jsonValue(address.street),
            "city": VisionSerialization.jsonValue(address.city),
            "state": VisionSerialization.jsonValue(address.state),
            "postal_code": VisionSerialization.jsonValue(address.postalCode),
            "region": VisionSerialization.jsonValue(address.region),
            "region_code": VisionSerialization.jsonValue(address.regionCode?.identifier),
            "label": VisionSerialization.jsonValue(address.label),
        ]
    }

    private static func calendarEventDetailsJSONObject(
        from event: DataDetector.Match.SemanticDetails.CalendarEvent
    ) -> [String: Any] {
        [
            "type": "calendar_event",
            "all_day": event.allDay,
            "start_date": iso8601String(from: event.startDate),
            "start_time_zone": VisionSerialization.jsonValue(event.startTimeZone?.identifier),
            "end_date": iso8601String(from: event.endDate),
            "end_time_zone": VisionSerialization.jsonValue(event.endTimeZone?.identifier),
        ]
    }

    private static func moneyAmountDetailsJSONObject(
        from amount: DataDetector.Match.SemanticDetails.MoneyAmount
    ) -> [String: Any] {
        [
            "type": "money_amount",
            "currency": amount.currency.identifier,
            "amount": amount.amount,
        ]
    }

    private static func flightNumberDetailsJSONObject(
        from flight: DataDetector.Match.SemanticDetails.FlightNumber
    ) -> [String: Any] {
        [
            "type": "flight_number",
            "airline_code": flight.airlineCode,
            "flight_number": flight.flightNumber,
        ]
    }

    private static func shipmentDetailsJSONObject(
        from shipment: DataDetector.Match.SemanticDetails.ShipmentTrackingNumber
    ) -> [String: Any] {
        [
            "type": "shipment_tracking_number",
            "carrier": shipment.carrier,
            "tracking_number": shipment.trackingNumber,
            "tracking_url": VisionSerialization.jsonValue(shipment.trackingURL?.absoluteString),
        ]
    }

    private static func measurementDetailsJSONObject(
        from measurement: DataDetector.Match.SemanticDetails.Measurement
    ) -> [String: Any] {
        [
            "type": "measurement",
            "value": measurement.value,
            "possible_dimensions": measurement.possibleDimensions.map(\.symbol),
        ]
    }

    private static func paymentIdentifierDetailsJSONObject(
        from payment: DataDetector.Match.SemanticDetails.PaymentIdentifier
    ) -> [String: Any] {
        [
            "type": "payment_identifier",
            "identifier": payment.identifier,
            "payment_system": "unified_payments_interface",
        ]
    }

    private static func stringRangeJSONObject(from range: Range<String.Index>?, in transcript: String) -> Any {
        guard let range else { return NSNull() }
        let location = transcript.distance(from: transcript.startIndex, to: range.lowerBound)
        let length = transcript.distance(from: range.lowerBound, to: range.upperBound)
        return [
            "location": location,
            "length": length,
        ]
    }

    private static func iso8601String(from date: Date?) -> Any {
        guard let date else { return NSNull() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func highlightStyleString(from style: DataDetector.Match.HighlightStyle) -> String {
        switch style {
        case .hidden: "hidden"
        case .url: "url"
        case .regular: "regular"
        @unknown default: "regular"
        }
    }
}
