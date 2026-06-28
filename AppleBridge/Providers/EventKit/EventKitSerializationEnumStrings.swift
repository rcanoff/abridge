import EventKit
import Foundation

extension EventKitSerialization {
    // MARK: - Enum strings (mechanical)

    static func calendarIdentifierString(_ identifier: Calendar.Identifier) -> String {
        calendarIdentifierStrings[identifier] ?? "unknown"
    }

    private static let calendarIdentifierStrings: [Calendar.Identifier: String] = [
        .gregorian: "gregorian",
        .buddhist: "buddhist",
        .chinese: "chinese",
        .coptic: "coptic",
        .ethiopicAmeteMihret: "ethiopic_amete_mihret",
        .ethiopicAmeteAlem: "ethiopic_amete_alem",
        .hebrew: "hebrew",
        .iso8601: "iso8601",
        .indian: "indian",
        .islamic: "islamic",
        .islamicCivil: "islamic_civil",
        .islamicTabular: "islamic_tabular",
        .islamicUmmAlQura: "islamic_umm_al_qura",
        .japanese: "japanese",
        .persian: "persian",
        .republicOfChina: "republic_of_china",
        .bangla: "bangla",
        .gujarati: "gujarati",
        .kannada: "kannada",
        .malayalam: "malayalam",
        .marathi: "marathi",
        .odia: "odia",
        .tamil: "tamil",
        .telugu: "telugu",
        .vikram: "vikram",
        .dangi: "dangi",
        .vietnamese: "vietnamese",
    ]

    static func colorSpaceModelString(_ model: CGColorSpaceModel) -> String {
        switch model {
        case .unknown: "unknown"
        case .monochrome: "monochrome"
        case .rgb: "rgb"
        case .cmyk: "cmyk"
        case .lab: "lab"
        case .deviceN: "device_n"
        case .indexed: "indexed"
        case .pattern: "pattern"
        case .XYZ: "xyz"
        @unknown default: "unknown"
        }
    }

    static func calendarTypeString(_ type: EKCalendarType) -> String {
        switch type {
        case .local: "local"
        case .calDAV: "cal_dav"
        case .exchange: "exchange"
        case .subscription: "subscription"
        case .birthday: "birthday"
        @unknown default: "unknown"
        }
    }

    static func sourceTypeString(_ type: EKSourceType) -> String {
        switch type {
        case .local: "local"
        case .exchange: "exchange"
        case .calDAV: "cal_dav"
        case .mobileMe: "mobile_me"
        case .subscribed: "subscribed"
        case .birthdays: "birthdays"
        @unknown default: "unknown"
        }
    }

    static func alarmProximityString(_ proximity: EKAlarmProximity) -> String {
        switch proximity {
        case .none: "none"
        case .enter: "enter"
        case .leave: "leave"
        @unknown default: "unknown"
        }
    }

    static func alarmTypeString(_ type: EKAlarmType) -> String {
        switch type {
        case .display: "display"
        case .audio: "audio"
        case .procedure: "procedure"
        case .email: "email"
        @unknown default: "unknown"
        }
    }

    static func recurrenceFrequencyString(_ frequency: EKRecurrenceFrequency) -> String {
        switch frequency {
        case .daily: "daily"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .yearly: "yearly"
        @unknown default: "unknown"
        }
    }

    static func participantStatusString(_ status: EKParticipantStatus) -> String {
        switch status {
        case .unknown: "unknown"
        case .pending: "pending"
        case .accepted: "accepted"
        case .declined: "declined"
        case .tentative: "tentative"
        case .delegated: "delegated"
        case .completed: "completed"
        case .inProcess: "in_process"
        @unknown default: "unknown"
        }
    }

    static func participantRoleString(_ role: EKParticipantRole) -> String {
        switch role {
        case .unknown: "unknown"
        case .required: "required"
        case .optional: "optional"
        case .chair: "chair"
        case .nonParticipant: "non_participant"
        @unknown default: "unknown"
        }
    }

    static func participantTypeString(_ type: EKParticipantType) -> String {
        switch type {
        case .unknown: "unknown"
        case .person: "person"
        case .room: "room"
        case .resource: "resource"
        case .group: "group"
        @unknown default: "unknown"
        }
    }
}
