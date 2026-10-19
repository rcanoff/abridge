//! MCP tool registry — name, capability, provider dispatch.

use crate::capabilities;

pub const TOOL_LIST_CALENDARS: &str = "eventkit_calendars_list_calendars";
pub const TOOL_CREATE_CALENDAR: &str = "eventkit_calendars_create_calendar";
pub const TOOL_UPDATE_CALENDAR: &str = "eventkit_calendars_update_calendar";
pub const TOOL_DELETE_CALENDAR: &str = "eventkit_calendars_delete_calendar";
pub const TOOL_LIST_EVENTS: &str = "eventkit_events_list_events";
pub const TOOL_GET_EVENT: &str = "eventkit_events_get_event";
pub const TOOL_SEARCH_EVENTS: &str = "eventkit_events_search_events";
pub const TOOL_CREATE_EVENT: &str = "eventkit_events_create_event";
pub const TOOL_UPDATE_EVENT: &str = "eventkit_events_update_event";
pub const TOOL_MOVE_EVENT: &str = "eventkit_events_move_event";
pub const TOOL_DELETE_EVENT: &str = "eventkit_events_delete_event";
pub const TOOL_LIST_LISTS: &str = "eventkit_reminders_list_lists";
pub const TOOL_LIST_REMINDERS: &str = "eventkit_reminders_list_reminders";
pub const TOOL_GET_REMINDER: &str = "eventkit_reminders_get_reminder";
pub const TOOL_SEARCH_REMINDERS: &str = "eventkit_reminders_search_reminders";
pub const TOOL_CREATE_REMINDER: &str = "eventkit_reminders_create_reminder";
pub const TOOL_CREATE_LIST: &str = "eventkit_reminders_create_list";
pub const TOOL_UPDATE_REMINDER: &str = "eventkit_reminders_update_reminder";
pub const TOOL_MOVE_REMINDER: &str = "eventkit_reminders_move_reminder";
pub const TOOL_DELETE_REMINDER: &str = "eventkit_reminders_delete_reminder";
pub const TOOL_DELETE_LIST: &str = "eventkit_reminders_delete_list";
pub const TOOL_COMPLETE_REMINDER: &str = "eventkit_reminders_complete_reminder";
pub const TOOL_UNCOMPLETE_REMINDER: &str = "eventkit_reminders_uncomplete_reminder";
pub const TOOL_SET_REMINDER_ALARMS: &str = "eventkit_reminders_set_reminder_alarms";
pub const TOOL_SET_EVENT_ALARMS: &str = "eventkit_events_set_event_alarms";
pub const TOOL_SET_REMINDER_RECURRENCE: &str = "eventkit_reminders_set_reminder_recurrence";
pub const TOOL_SET_EVENT_RECURRENCE: &str = "eventkit_events_set_event_recurrence";
pub const TOOL_ACCEPT_INVITATION: &str = "eventkit_events_accept_invitation";
pub const TOOL_DECLINE_INVITATION: &str = "eventkit_events_decline_invitation";
pub const TOOL_TENTATIVE_INVITATION: &str = "eventkit_events_tentative_invitation";
pub const TOOL_LIST_CONTACTS: &str = "contacts_list_contacts";
pub const TOOL_LIST_GROUPS: &str = "contacts_list_groups";
pub const TOOL_LIST_CONTAINERS: &str = "contacts_list_containers";
pub const TOOL_GET_CONTACT: &str = "contacts_get_contact";
pub const TOOL_SEARCH_CONTACTS: &str = "contacts_search_contacts";
pub const TOOL_CREATE_CONTACT: &str = "contacts_create_contact";
pub const TOOL_CREATE_GROUP: &str = "contacts_create_group";
pub const TOOL_UPDATE_CONTACT: &str = "contacts_update_contact";
pub const TOOL_LINK_CONTACTS: &str = "contacts_link_contacts";
pub const TOOL_UNLINK_CONTACTS: &str = "contacts_unlink_contacts";
pub const TOOL_UPDATE_GROUP: &str = "contacts_update_group";
pub const TOOL_DELETE_CONTACT: &str = "contacts_delete_contact";
pub const TOOL_DELETE_GROUP: &str = "contacts_delete_group";
pub const TOOL_SEARCH_PLACES: &str = "mapkit_search_places";
pub const TOOL_SEARCH_NEARBY: &str = "mapkit_search_nearby";
pub const TOOL_REVERSE_GEOCODE: &str = "mapkit_reverse_geocode";
pub const TOOL_FORWARD_GEOCODE: &str = "mapkit_forward_geocode";
pub const TOOL_CALCULATE_ROUTE: &str = "mapkit_calculate_route";
pub const TOOL_ESTIMATE_TRAVEL_TIME: &str = "mapkit_estimate_travel_time";
pub const TOOL_GET_CURRENT_LOCATION: &str = "corelocation_get_current_location";
pub const TOOL_GET_PLACE: &str = "mapkit_get_place";
pub const TOOL_OPEN_NAVIGATION: &str = "mapkit_open_navigation";
pub const TOOL_GET_USAGE_LOG: &str = "diagnostics_get_usage_log";
pub const TOOL_RECOGNIZE_TEXT: &str = "vision_recognize_text";
pub const TOOL_RECOGNIZE_DOCUMENTS: &str = "vision_recognize_documents";
pub const TOOL_DETECT_BARCODES: &str = "vision_detect_barcodes";
pub const TOOL_DETECT_FACE_LANDMARKS: &str = "vision_detect_face_landmarks";
pub const TOOL_NOTES_LIST_FOLDERS: &str = "notes_list_folders";
pub const TOOL_NOTES_LIST_NOTES: &str = "notes_list_notes";
pub const TOOL_NOTES_GET_NOTE: &str = "notes_get_note";
pub const TOOL_NOTES_GET_ATTACHMENT: &str = "notes_get_attachment";
pub const TOOL_NOTES_SEARCH_NOTES: &str = "notes_search_notes";
pub const TOOL_NOTES_CREATE_NOTE: &str = "notes_create_note";
pub const TOOL_NOTES_UPDATE_NOTE: &str = "notes_update_note";
pub const TOOL_NOTES_MOVE_NOTE: &str = "notes_move_note";
pub const TOOL_NOTES_DELETE_NOTE: &str = "notes_delete_note";
pub const TOOL_NOTES_CREATE_FOLDER: &str = "notes_create_folder";
pub const TOOL_NOTES_DELETE_FOLDER: &str = "notes_delete_folder";
pub const TOOL_SEARCH_ITEMS: &str = "abridge_search_items";

macro_rules! notes_markdown {
  () => {
    "body is Markdown, the same dialect notes_get_note returns. A leading `# Title` is the note title. HTML is \
     converted; warnings name every converted tag and every removed tag. Headings are stored as bold and read \
     back as # / ##; deeper headings read back as bold. A blank line between blocks becomes an empty line, which is how Notes spaces sections. A table becomes a Notes table. \
     `[title](attachment:<id>)` does not attach or keep a file"
  };
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ToolDefinition {
  pub name: &'static str,
  pub capability: &'static str,
  pub provider: &'static str,
  pub operation: &'static str,
  pub description: &'static str,
}
macro_rules! fuzzy_query {
  () => {
    "query is AND across words. `|` is OR (`Lisbon | queijo` is one call). \"buy milk\" is one exact phrase \
     (spaces stay; case and accents are ignored). A leading ' is an exact substring of one word and does not \
     quote spaces. `^` and `$` anchor a word, `!` excludes. An unmatched quote is ignored"
  };
}

macro_rules! event_time_offset {
  () => {
    "Timed start and end carry a numeric offset from the event's time zone, or the server Mac's when the event has none, not the caller's. All-day start_date and end_date are calendar dates YYYY-MM-DD; end_date is exclusive (the day after the last day). The day is the serialized instant in the event's time zone, or this Mac's zone when the event has none."
  };
}

macro_rules! client_resolves_relative_date {
  () => {
    "for example 2026-10-26T09:00:00-04:00, or wall time 2026-10-26T09:00:00 with time_zone \
     America/New_York. This Mac's zone is not applied"
  };
}

/// Wording for fields that take only an absolute instant (no time_zone companion).
macro_rules! absolute_instant {
  () => {
    "Absolute time with a numeric offset (Z or ±HH:MM), for example 2026-10-26T09:00:00-04:00. A wall time \
     without an offset is rejected; this Mac's zone is not applied."
  };
}

/// Reminder dates are calendar components; the client resolves relative dates.
macro_rules! reminder_dates {
  () => {
    "Resolve relative dates such as next Monday on the client, then send due_date_components, for example \
     {\"year\":2026,\"month\":10,\"day\":26,\"hour\":9,\"minute\":0,\"time_zone\":\"America/New_York\"}"
  };
}

const ALL_TOOLS: [ToolDefinition; 69] = [
  ToolDefinition {
    name: TOOL_LIST_CALENDARS,
    capability: capabilities::EVENTKIT_CALENDARS_READ,
    provider: "eventkit",
    operation: "list_calendars",
    description: "List event calendars. Each row has calendar_identifier, title, type, source \
                  {source_identifier, title, type}, and color.",
  },
  ToolDefinition {
    name: TOOL_CREATE_CALENDAR,
    capability: capabilities::EVENTKIT_CALENDARS_CREATE,
    provider: "eventkit",
    operation: "create_calendar",
    description: "Create an event calendar. Requires title. color and source are optional.",
  },
  ToolDefinition {
    name: TOOL_UPDATE_CALENDAR,
    capability: capabilities::EVENTKIT_CALENDARS_EDIT,
    provider: "eventkit",
    operation: "update_calendar",
    description: "Update an event calendar by calendar_identifier. Omitted fields stay unchanged.",
  },
  ToolDefinition {
    name: TOOL_DELETE_CALENDAR,
    capability: capabilities::EVENTKIT_CALENDARS_DELETE,
    provider: "eventkit",
    operation: "delete_calendar",
    description: "Delete an event calendar by calendar_identifier",
  },
  ToolDefinition {
    name: TOOL_LIST_EVENTS,
    capability: capabilities::EVENTKIT_EVENTS_READ,
    provider: "eventkit",
    operation: "list_events",
    description: concat!(
      "List events in a date window. To find one title, call eventkit_events_search_events. ",
      event_time_offset!(),
      " Rows of a series share event_identifier. Pass that row's start_date as occurrence_date to get, update, \
       or delete that occurrence. limit defaults to 50 (max 200); offset pages."
    ),
  },
  ToolDefinition {
    name: TOOL_GET_EVENT,
    capability: capabilities::EVENTKIT_EVENTS_READ,
    provider: "eventkit",
    operation: "get_event",
    description: concat!(
      "Get one event by event_identifier. Pass occurrence_date, that row's start_date, to read one occurrence. ",
      event_time_offset!(),
      " notes is plain text or Markdown."
    ),
  },
  ToolDefinition {
    name: TOOL_SEARCH_EVENTS,
    capability: capabilities::EVENTKIT_EVENTS_SEARCH,
    provider: "eventkit",
    operation: "search_events",
    description: concat!(
      "Search events by title, notes, or location. With no dates, the range is 1 year before through 2 years \
       after the server Mac's current time, not the caller's. ",
      fuzzy_query!(),
      ". Dates and calendar_identifier still filter. Each row is one occurrence. ",
      event_time_offset!(),
      " Rows of a series share event_identifier. Pass a row's start_date as occurrence_date to change that \
       occurrence. limit defaults to 50 (max 200)."
    ),
  },
  ToolDefinition {
    name: TOOL_CREATE_EVENT,
    capability: capabilities::EVENTKIT_EVENTS_CREATE,
    provider: "eventkit",
    operation: "create_event",
    description: "Create an event. Requires calendar_identifier, title, start_date, and end_date. Alarm, recurrence, and \
                  structured_location fields are on those properties.",
  },
  ToolDefinition {
    name: TOOL_UPDATE_EVENT,
    capability: capabilities::EVENTKIT_EVENTS_EDIT,
    provider: "eventkit",
    operation: "update_event",
    description: "Update an event by event_identifier. A recurring event needs occurrence_date and span \
                  this_event (default) or future_events; otherwise the call returns occurrence_required and changes \
                  nothing. Omitted fields stay unchanged. alarms, recurrence_rules, and structured_location replace \
                  the whole value when sent; [] clears alarms or recurrence.",
  },
  ToolDefinition {
    name: TOOL_MOVE_EVENT,
    capability: capabilities::EVENTKIT_EVENTS_EDIT,
    provider: "eventkit",
    operation: "move_event",
    description: "Move an event to another calendar. Requires event_identifier and calendar_identifier. Other \
                  fields stay unchanged.",
  },
  ToolDefinition {
    name: TOOL_DELETE_EVENT,
    capability: capabilities::EVENTKIT_EVENTS_DELETE,
    provider: "eventkit",
    operation: "delete_event",
    description: "Delete an event permanently. Pass exactly one of event_identifier or event_title (exact, \
                  case-insensitive). calendar_identifier limits a title to one calendar. A title uses the same date \
                  window as eventkit_events_search_events. Occurrences of one series count as one event. Several \
                  events return event_title_ambiguous and delete nothing. A recurring event needs occurrence_date \
                  and span this_event (default) or future_events; otherwise the call returns occurrence_required \
                  and deletes nothing.",
  },
  ToolDefinition {
    name: TOOL_LIST_LISTS,
    capability: capabilities::EVENTKIT_REMINDERS_READ,
    provider: "eventkit",
    operation: "list_lists",
    description: "List reminder lists. Each row has calendar_identifier, title, type, source \
                  {source_identifier, title, type}, and color.",
  },
  ToolDefinition {
    name: TOOL_LIST_REMINDERS,
    capability: capabilities::EVENTKIT_REMINDERS_READ,
    provider: "eventkit",
    operation: "list_reminders",
    description: "List reminders. To find one title, call eventkit_reminders_search_reminders. due_date is YYYY-MM-DD when \
                  date-only. A timed due with a components time_zone has that zone's numeric offset. With no components \
                  time_zone a timed due is that wall time with no offset and floating: true (wherever the user is), not \
                  the server Mac's zone. A due window returns only reminders that have a due date. limit defaults to 50 \
                  (max 200).",
  },
  ToolDefinition {
    name: TOOL_GET_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_READ,
    provider: "eventkit",
    operation: "get_reminder",
    description: "Get one reminder by calendar_item_identifier. due_date and start_date are YYYY-MM-DD when \
                  date-only. A timed value with a components time_zone has that zone's numeric offset. With no \
                  components time_zone a timed value is that wall time with no offset and floating: true \
                  (wherever the user is), not the server Mac's zone. The reminder time_zone is separate and does \
                  not stamp the due or start time.",
  },
  ToolDefinition {
    name: TOOL_SEARCH_REMINDERS,
    capability: capabilities::EVENTKIT_REMINDERS_SEARCH,
    provider: "eventkit",
    operation: "search_reminders",
    description: concat!(
      "Search reminders by title, notes, and location. ",
      fuzzy_query!(),
      ". completion_status, due dates, and include_overdue match list reminders. A due window returns only \
       reminders that have a due date. limit defaults to 50 (max 200)."
    ),
  },
  ToolDefinition {
    name: TOOL_CREATE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_CREATE,
    provider: "eventkit",
    operation: "create_reminder",
    description: concat!(
      "Create a reminder. Requires calendar_identifier and title. A due or start time with hour and minute but \
       no components time_zone stays floating on write. ",
      reminder_dates!(),
      ". Date, alarm, and recurrence fields are on those properties."
    ),
  },
  ToolDefinition {
    name: TOOL_CREATE_LIST,
    capability: capabilities::EVENTKIT_REMINDERS_CREATE,
    provider: "eventkit",
    operation: "create_list",
    description: "Create a reminder list. Requires title. color and source are optional.",
  },
  ToolDefinition {
    name: TOOL_UPDATE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_EDIT,
    provider: "eventkit",
    operation: "update_reminder",
    description: concat!(
      "Update a reminder by calendar_item_identifier. Omitted fields stay unchanged. ",
      reminder_dates!(),
      ". A due or start time with hour and minute but no components time_zone stays floating on write. Null \
       due_date_components or start_date_components clears that date. alarms and recurrence_rules \
       replace the whole list when sent."
    ),
  },
  ToolDefinition {
    name: TOOL_MOVE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_EDIT,
    provider: "eventkit",
    operation: "move_reminder",
    description: "Move a reminder to another list. Requires calendar_item_identifier and calendar_identifier. \
                  Other fields stay unchanged.",
  },
  ToolDefinition {
    name: TOOL_DELETE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_DELETE,
    provider: "eventkit",
    operation: "delete_reminder",
    description: "Delete a reminder permanently. Pass exactly one of calendar_item_identifier or reminder_title \
                  (exact, case-insensitive). calendar_identifier limits a title to one list. Several matches return \
                  reminder_title_ambiguous and delete nothing.",
  },
  ToolDefinition {
    name: TOOL_DELETE_LIST,
    capability: capabilities::EVENTKIT_REMINDERS_DELETE,
    provider: "eventkit",
    operation: "delete_list",
    description: "Delete a reminder list by calendar_identifier",
  },
  ToolDefinition {
    name: TOOL_COMPLETE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_COMPLETE,
    provider: "eventkit",
    operation: "complete_reminder",
    description: "Set a reminder complete by calendar_item_identifier. EventKit sets the completion date and \
                  advances a repeating reminder, so the result may be the next occurrence.",
  },
  ToolDefinition {
    name: TOOL_UNCOMPLETE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_COMPLETE,
    provider: "eventkit",
    operation: "uncomplete_reminder",
    description: "Set a reminder incomplete by calendar_item_identifier. EventKit clears the completion date.",
  },
  ToolDefinition {
    name: TOOL_SET_REMINDER_ALARMS,
    capability: capabilities::EVENTKIT_REMINDERS_ALARMS,
    provider: "eventkit",
    operation: "set_reminder_alarms",
    description: "Set a reminder's alarms by calendar_item_identifier. alarms replaces the list; [] removes \
                  all. Other fields stay unchanged. Alarm fields are on alarms.",
  },
  ToolDefinition {
    name: TOOL_SET_EVENT_ALARMS,
    capability: capabilities::EVENTKIT_EVENTS_ALARMS,
    provider: "eventkit",
    operation: "set_event_alarms",
    description: "Set an event's alarms by event_identifier. alarms replaces the list; [] removes all. Other \
                  fields stay unchanged. Alarm fields are on alarms.",
  },
  ToolDefinition {
    name: TOOL_SET_REMINDER_RECURRENCE,
    capability: capabilities::EVENTKIT_REMINDERS_RECURRENCE,
    provider: "eventkit",
    operation: "set_reminder_recurrence",
    description: "Set a reminder's recurrence rules by calendar_item_identifier. recurrence_rules replaces the \
                  list; [] clears it. day_of_the_week is sunday through saturday. A repeating reminder must already \
                  have a due date. Other fields stay unchanged.",
  },
  ToolDefinition {
    name: TOOL_SET_EVENT_RECURRENCE,
    capability: capabilities::EVENTKIT_EVENTS_RECURRENCE,
    provider: "eventkit",
    operation: "set_event_recurrence",
    description: "Set recurrence on one event by event_identifier. recurrence_rules replaces the list; [] \
                  clears it. day_of_the_week is sunday through saturday. Does not return later occurrences.",
  },
  ToolDefinition {
    name: TOOL_ACCEPT_INVITATION,
    capability: capabilities::EVENTKIT_EVENTS_INVITATIONS,
    provider: "eventkit",
    operation: "accept_invitation",
    description: "Set an event invitation to accepted by event_identifier.",
  },
  ToolDefinition {
    name: TOOL_DECLINE_INVITATION,
    capability: capabilities::EVENTKIT_EVENTS_INVITATIONS,
    provider: "eventkit",
    operation: "decline_invitation",
    description: "Set an event invitation to declined by event_identifier.",
  },
  ToolDefinition {
    name: TOOL_TENTATIVE_INVITATION,
    capability: capabilities::EVENTKIT_EVENTS_INVITATIONS,
    provider: "eventkit",
    operation: "tentative_invitation",
    description: "Set an event invitation to tentative by event_identifier.",
  },
  ToolDefinition {
    name: TOOL_LIST_CONTACTS,
    capability: capabilities::CONTACTS_READ,
    provider: "contacts",
    operation: "list_contacts",
    description: "List contacts, optionally in one container. Summaries: identifier, name, nickname, \
                  organization_name, job_title, container_identifier, phone (first, no label), email (first, no \
                  label). No photo bytes. Labels are words (mobile, home, work, home fax); omit a label you do not \
                  know. To change one email, contacts_get_contact first; email_addresses replaces the whole list. \
                  limit defaults to 50 (max 200); offset pages.",
  },
  ToolDefinition {
    name: TOOL_LIST_GROUPS,
    capability: capabilities::CONTACTS_READ,
    provider: "contacts",
    operation: "list_groups",
    description: "List contact groups, optionally in one container. Each has identifier and name. limit defaults \
                  to 50 (max 200); offset pages.",
  },
  ToolDefinition {
    name: TOOL_LIST_CONTAINERS,
    capability: capabilities::CONTACTS_READ,
    provider: "contacts",
    operation: "list_containers",
    description: "List contact containers. Each has identifier, name, and type (local, exchange, or carddav). \
                  is_default marks the container create uses when container_identifier is omitted.",
  },
  ToolDefinition {
    name: TOOL_GET_CONTACT,
    capability: capabilities::CONTACTS_READ,
    provider: "contacts",
    operation: "get_contact",
    description: "Get one contact by contact_identifier. Phone, email, and URL values are strings with an \
                  optional label (plain words such as mobile or home fax; a custom label is unchanged). A postal \
                  address is that same object on read and write. A photo follows the JSON as image content.",
  },
  ToolDefinition {
    name: TOOL_SEARCH_CONTACTS,
    capability: capabilities::CONTACTS_SEARCH,
    provider: "contacts",
    operation: "search_contacts",
    description: concat!(
      "Search contacts by name, nickname, organization, job title, email, phone, and note. ",
      fuzzy_query!(),
      ". Provide at least one of query, name, email_address, or phone_number. name, email_address, and \
       phone_number are Contacts predicates and apply only when query is omitted. container_identifier limits \
       either path. Summaries: identifier, name, nickname, organization_name, job_title, \
       container_identifier, phone (first, no label), email (first, no label). No photo bytes. limit defaults \
       to 50 (max 200)."
    ),
  },
  ToolDefinition {
    name: TOOL_CREATE_CONTACT,
    capability: capabilities::CONTACTS_CREATE,
    provider: "contacts",
    operation: "create_contact",
    description: "Create a contact. Requires at least one of given_name, family_name, or organization_name. \
                  Omit container_identifier for the default container. Labeled values and dates match get; date \
                  fields are on birthday, non_gregorian_birthday, and dates.",
  },
  ToolDefinition {
    name: TOOL_CREATE_GROUP,
    capability: capabilities::CONTACTS_CREATE,
    provider: "contacts",
    operation: "create_group",
    description: "Create a contact group. Requires name. Omit container_identifier for the default container.",
  },
  ToolDefinition {
    name: TOOL_UPDATE_CONTACT,
    capability: capabilities::CONTACTS_EDIT,
    provider: "contacts",
    operation: "update_contact",
    description: "Update a contact by contact_identifier. Omitted fields stay unchanged. Null clears a field. \
                  To change one email or phone, contacts_get_contact first and send the whole list back; \
                  phone_numbers, email_addresses, postal_addresses, url_addresses, contact_relations, \
                  social_profiles, instant_message_addresses, and dates replace the whole list. Labels are words \
                  (mobile, home, work, home fax); omit a label you do not know.",
  },
  ToolDefinition {
    name: TOOL_LINK_CONTACTS,
    capability: capabilities::CONTACTS_EDIT,
    provider: "contacts",
    operation: "link_contacts",
    description: "Link a contact to another by from_contact_identifier and to_contact_identifier.",
  },
  ToolDefinition {
    name: TOOL_UNLINK_CONTACTS,
    capability: capabilities::CONTACTS_EDIT,
    provider: "contacts",
    operation: "unlink_contacts",
    description: "Unlink a contact from its unified card by contact_identifier.",
  },
  ToolDefinition {
    name: TOOL_UPDATE_GROUP,
    capability: capabilities::CONTACTS_EDIT,
    provider: "contacts",
    operation: "update_group",
    description: "Update a contact group by group_identifier. Omit name to leave it unchanged. Null clears the name.",
  },
  ToolDefinition {
    name: TOOL_DELETE_CONTACT,
    capability: capabilities::CONTACTS_DELETE,
    provider: "contacts",
    operation: "delete_contact",
    description: "Delete a contact by contact_identifier",
  },
  ToolDefinition {
    name: TOOL_DELETE_GROUP,
    capability: capabilities::CONTACTS_DELETE,
    provider: "contacts",
    operation: "delete_group",
    description: "Delete a contact group by group_identifier",
  },
  ToolDefinition {
    name: TOOL_SEARCH_PLACES,
    capability: capabilities::MAPKIT_SEARCH,
    provider: "mapkit",
    operation: "search_places",
    description: "Search places with MapKit's natural-language query. For a landmark, pass region and set \
                  region_priority to required. Omitting region biases results near this server Mac, not near the \
                  caller. A street address belongs in mapkit_forward_geocode. Each place has name, identifier, and \
                  coordinate for routing.",
  },
  ToolDefinition {
    name: TOOL_SEARCH_NEARBY,
    capability: capabilities::MAPKIT_SEARCH,
    provider: "mapkit",
    operation: "search_nearby",
    description: "Search for points of interest near the coordinate or region you pass. It is not the caller's location. \
                  Each place matches mapkit_search_places.",
  },
  ToolDefinition {
    name: TOOL_REVERSE_GEOCODE,
    capability: capabilities::MAPKIT_GEOCODE,
    provider: "mapkit",
    operation: "reverse_geocode",
    description: "Get places for a coordinate. Each has name, coordinate, and address.",
  },
  ToolDefinition {
    name: TOOL_FORWARD_GEOCODE,
    capability: capabilities::MAPKIT_GEOCODE,
    provider: "mapkit",
    operation: "forward_geocode",
    description: "Get places for a street address. An optional region biases results toward that region. It is not the \
                  caller's location unless you pass coordinates. For a landmark, use mapkit_search_places with a \
                  region bias.",
  },
  ToolDefinition {
    name: TOOL_CALCULATE_ROUTE,
    capability: capabilities::MAPKIT_ROUTING,
    provider: "mapkit",
    operation: "calculate_route",
    description: "Calculate routes between source and destination. Each endpoint is a MapKit identifier from \
                  mapkit_search_places, or a coordinate. name is a label and does not geocode. A coordinate alone is \
                  reverse-geocoded, and the name is omitted when that fails. Polyline coordinates are omitted. Omitting \
                  departure_date and arrival_date uses the server Mac's current time. A returned time's offset is the \
                  place's time zone, or the server Mac's when the place has none (not the caller's).",
  },
  ToolDefinition {
    name: TOOL_ESTIMATE_TRAVEL_TIME,
    capability: capabilities::MAPKIT_ROUTING,
    provider: "mapkit",
    operation: "estimate_travel_time",
    description: "Travel time between two places. Each of source and destination is a MapKit identifier from \
                  mapkit_search_places, or a coordinate. name is a label and does not geocode. Provide exactly one of \
                  departure_date or arrival_date, or neither (neither uses this Mac's clock). A returned arrival or \
                  departure is local wall time with a numeric offset from the place's time zone, or the server Mac's time \
                  zone when the place has none (not the caller's).",
  },
  ToolDefinition {
    name: TOOL_GET_CURRENT_LOCATION,
    capability: capabilities::CORELOCATION_READ,
    provider: "corelocation",
    operation: "get_current_location",
    description: "Get this server Mac's current location, not the caller's (do not use it to answer where the user \
                  is): coordinate, timestamp, and altitude, accuracy, course, and speed when the sensor has a \
                  reading. Failures are location_services_off, permission_denied \
                  (denied, restricted, or not determined), or location_unknown (no fix or timeout, including \
                  kCLErrorDomain error 0). The message says what to change.",
  },
  ToolDefinition {
    name: TOOL_GET_PLACE,
    capability: capabilities::MAPKIT_READ,
    provider: "mapkit",
    operation: "get_place",
    description: "Get a place by MapKit identifier: name, coordinate, phone, url, time zone, category, and address.",
  },
  ToolDefinition {
    name: TOOL_OPEN_NAVIGATION,
    capability: capabilities::MAPKIT_NAVIGATION,
    provider: "mapkit",
    operation: "open_navigation",
    description: "Open Apple Maps navigation between source and destination. Endpoints match mapkit_calculate_route. \
                  opened is present when Maps opened.",
  },
  ToolDefinition {
    name: TOOL_GET_USAGE_LOG,
    capability: capabilities::DIAGNOSTICS_READ,
    provider: "diagnostics",
    operation: "get_usage_log",
    description: "Get the local usage audit log. Each entry has timestamp_utc, event_type, and success, plus \
                  tool_name and duration_ms when present. success and logging_enabled stay present when false. \
                  No tokens or payloads.",
  },
  ToolDefinition {
    name: TOOL_RECOGNIZE_TEXT,
    capability: capabilities::VISION_TEXT,
    provider: "vision",
    operation: "recognize_text",
    description: "OCR a local image on the server Mac. Pass image_path or base64 image_data, not both. \
                  image_path is an absolute path of a regular file on this Mac (a symlink is followed when the \
                  final target is a regular file), at most 20 MiB. A PDF is accepted by content, not \
                  extension. page selects one page (default 1); a PDF result includes page and page_count. \
                  A page past the end is page_out_of_range. page greater than 1 on an image is \
                  invalid_arguments. An encrypted or unreadable PDF is an error. No pixel buffers or request ids.",
  },
  ToolDefinition {
    name: TOOL_RECOGNIZE_DOCUMENTS,
    capability: capabilities::VISION_DOCUMENT,
    provider: "vision",
    operation: "recognize_documents",
    description: "Recognize a document's text, tables, and lists in a local image on the server Mac. Pass \
                  image_path or base64 image_data, not both. image_path is an absolute path of a regular file on \
                  this Mac (a symlink is followed when the final target is a regular file), at most 20 MiB. A PDF is \
                  accepted by content, not extension. page selects one page (default 1); a PDF result includes \
                  page and page_count. A page past the end is page_out_of_range. page greater than 1 on an image \
                  is invalid_arguments. An encrypted or unreadable PDF is an error. No segmentation masks or \
                  pixel buffers.",
  },
  ToolDefinition {
    name: TOOL_DETECT_BARCODES,
    capability: capabilities::VISION_BARCODES,
    provider: "vision",
    operation: "detect_barcodes",
    description: "Detect barcodes and QR codes in a local image on the server Mac. Pass image_path or base64 \
                  image_data, not both. image_path is an absolute path of a regular file on this Mac (a symlink is \
                  followed when the final target is a regular file), at most 20 MiB. A PDF is accepted by content, \
                  not extension. page selects one page (default 1); a PDF result includes page and page_count. \
                  A page past the end is page_out_of_range. page greater than 1 on an image is invalid_arguments. \
                  An encrypted or unreadable PDF is an error. Each result has symbology, payload_string, and a \
                  bounding region. No raw payload bytes.",
  },
  ToolDefinition {
    name: TOOL_DETECT_FACE_LANDMARKS,
    capability: capabilities::VISION_FACES,
    provider: "vision",
    operation: "detect_face_landmarks",
    description: "Detect faces and facial landmarks in a local image on the server Mac. Pass image_path or \
                  base64 image_data, not both. image_path is an absolute path of a regular file on this Mac (a \
                  symlink is followed when the final target is a regular file), at most 20 MiB. A PDF is accepted \
                  by content, not extension. page selects one page (default 1); a PDF result includes page and \
                  page_count. A page past the end is page_out_of_range. page greater than 1 on an image is \
                  invalid_arguments. An encrypted or unreadable PDF is an error. No segmentation masks.",
  },
  ToolDefinition {
    name: TOOL_NOTES_LIST_FOLDERS,
    capability: capabilities::NOTES_READ,
    provider: "notes",
    operation: "list_folders",
    description: "List Notes folders, sorted by path. Each has identifier, name, path (names from the account \
                  root joined by /), account {identifier, name}, note_count, parent_identifier when nested, and \
                  kind recently_deleted or smart. Folders not yet downloaded are left out. Pass path as \
                  folder_path on other notes tools.",
  },
  ToolDefinition {
    name: TOOL_NOTES_LIST_NOTES,
    capability: capabilities::NOTES_READ,
    provider: "notes",
    operation: "list_notes",
    description: "List notes as short summaries, pinned first, then most recently modified. To find text, call \
                  notes_search_notes. Pass exactly one of folder_identifier or folder_path, or neither. Without a \
                  folder, Recently Deleted and notes not yet downloaded are left out. Each summary has identifier, \
                  title, folder {identifier, path, account}, creation_date and modification_date (UTC instants with \
                  a Z suffix, not the caller's local time and not the server Mac's local zone), attachment_count, \
                  snippet, and true flags. Inline tables stay in the body. limit defaults to 50 (max 200); offset \
                  skips summaries. Get a note for its full body.",
  },
  ToolDefinition {
    name: TOOL_NOTES_GET_NOTE,
    capability: capabilities::NOTES_READ,
    provider: "notes",
    operation: "get_note",
    description: "Read one note's Markdown body. Pass exactly one of note_identifier or note_title (exact, \
                  case-insensitive; live notes only, and Recently Deleted only when the folder is that folder). \
                  Narrow a title with folder_identifier or folder_path. Search or list returns identifiers; this \
                  call returns the body. If a search match names an attachment, call notes_get_attachment \
                  directly. Same fields as a list summary, without snippet, plus body and the attachments it \
                  references, including attachment:<id> links. creation_date and modification_date (UTC instants \
                  with a Z suffix, not the caller's local time and not the server Mac's local zone). Attachment \
                  creation_date and modification_date are the same UTC instants. Inline tables stay in the body.",
  },
  ToolDefinition {
    name: TOOL_NOTES_GET_ATTACHMENT,
    capability: capabilities::NOTES_READ,
    provider: "notes",
    operation: "get_attachment",
    description: "Read one attachment by identifier. Call it directly when a search match names the attachment; \
                  notes_get_note is not required first. format defaults to markdown and may be image or original. \
                  markdown pages content by Unicode characters (offset is not a page or byte offset; \
                  max_characters default 15000, at most 100000). Documents are converted locally. Markdown does not \
                  read a file larger than 50 MiB (error extraction_too_large, no text). Video, audio, and other \
                  unsupported types are recognized from the UTI, the extension, and a short header and are not read \
                  in full. Scans and photos \
                  return OCR Notes has already stored; for a local image with no stored text, use \
                  vision_recognize_text. image returns a viewable JPEG; for a PDF or scan it renders one page \
                  (page, default 1) and sets page and page_count, so ask for the next page while page < page_count \
                  (page_out_of_range past the end). original copies the file to \
                  $TMPDIR/abridge-attachments/<attachment identifier>/<file name> and sets file_path, with no size \
                  cap. source_path is the Notes file when it is on disk. file_size is the size on disk when the \
                  file is present, otherwise the size Notes stored. creation_date and modification_date are the \
                  same UTC instants (Z suffix, not the caller's local time and not the server Mac's local zone). \
                  attachment_not_viewable, attachment_file_unavailable, attachment_locked, attachment_encrypted, \
                  attachment_unreadable, extraction_too_large, page_out_of_range, page_unrendered, and \
                  attachment_has_no_file name why a file was not \
                  returned.",
  },
  ToolDefinition {
    name: TOOL_NOTES_SEARCH_NOTES,
    capability: capabilities::NOTES_SEARCH,
    provider: "notes",
    operation: "search_notes",
    description: concat!(
      "Search notes and attachment text. Attachment files larger than 50 MiB are not read or indexed. Returns \
       identifiers and matches. Get a note for its full body. If matches[].field is `attachment: <id> <title>`, \
       call notes_get_attachment directly. ",
      fuzzy_query!(),
      ". Pass exactly one of folder_identifier or folder_path to search that folder, including Recently \
       Deleted; without either, those notes are left out. modified_after and modified_before are exclusive \
       RFC 3339 bounds. They need a numeric offset; the server's time zone is not used. Hit creation_date and \
       modification_date (UTC instants with a Z suffix, not the caller's local time and not the server Mac's \
       local zone). Best matches first: the summary without body or snippet, plus score and up to 3 matches \
       {field, excerpt}. A match on attachment text also includes attachment_identifier and attachment_title. \
       excerpt is the matched line or table row, capped at 120 characters, with the match inside «». limit \
       defaults to 20 (max 100); offset skips hits."
    ),
  },
  ToolDefinition {
    name: TOOL_NOTES_CREATE_NOTE,
    capability: capabilities::NOTES_CREATE,
    provider: "notes",
    operation: "create_note",
    description: concat!(
      "Create a note in a folder and return it (same shape as notes_get_note). `- [ ]` and `- [x]` are stored \
       as ordinary bullets, not a native Notes checklist, so a later notes_update_note can replace the text. \
       Pass exactly one of folder_identifier or folder_path, plus body. creation_date and modification_date \
       (UTC instants with a Z suffix, not the caller's local time and not the server Mac's local zone). ",
      notes_markdown!()
    ),
  },
  ToolDefinition {
    name: TOOL_NOTES_UPDATE_NOTE,
    capability: capabilities::NOTES_EDIT,
    provider: "notes",
    operation: "update_note",
    description: concat!(
      "Replaces the whole body and returns the note (same shape as notes_get_note). It is not an append or an \
       item patch. Refuses with body_would_drop_content when the note is password protected or already has a \
       native Notes checklist or a non-table attachment, and names each one; nothing is written. Refuses with \
       body_unavailable when the current body is missing, not downloaded, past the inflate limit, or not a note \
       protobuf, including a note_identifier that is still awaiting download; nothing is written. Refuses with \
       note_changed when the live note's modification date is newer than the snapshot just read, or the live \
       attachment count differs; nothing is written, so read the note again and retry. An identical body (the \
       requested Markdown already matches the stored note after normalization) succeeds without waiting. Success \
       confirms note_data changed, not modification_date alone. On write_unconfirmed, or if scripting times out, \
       the change may have happened; read the note before retrying. Resend a Notes \
       table as a Markdown table or it is converted to text. Pass exactly one of note_identifier or note_title, \
       plus body. creation_date and modification_date (UTC instants with a Z suffix, not the caller's local \
       time and not the server Mac's local zone). ",
      notes_markdown!()
    ),
  },
  ToolDefinition {
    name: TOOL_NOTES_MOVE_NOTE,
    capability: capabilities::NOTES_EDIT,
    provider: "notes",
    operation: "move_note",
    description: "Move one note to the destination folder_path or folder_identifier. note_title or \
                  note_identifier finds the source; duplicate titles return note_title_ambiguous and change \
                  nothing. Returns the moved note (same shape as notes_get_note). creation_date and \
                  modification_date (UTC instants with a Z suffix, not the caller's local time and not the server \
                  Mac's local zone).",
  },
  ToolDefinition {
    name: TOOL_NOTES_DELETE_NOTE,
    capability: capabilities::NOTES_DELETE,
    provider: "notes",
    operation: "delete_note",
    description: "Moves the note to Recently Deleted. It is not erased: deletion is recently_deleted. Restore \
                  with notes_move_note. Returns the note there (same shape as notes_get_note) plus deletion. Pass \
                  exactly one of note_identifier or note_title. A note already in Recently Deleted is refused; \
                  permanent deletion is not available. creation_date and modification_date (UTC instants with a Z \
                  suffix, not the caller's local time and not the server Mac's local zone).",
  },
  ToolDefinition {
    name: TOOL_NOTES_CREATE_FOLDER,
    capability: capabilities::NOTES_CREATE,
    provider: "notes",
    operation: "create_folder",
    description: "Create a folder and return it (same shape as notes_list_folders). Pass account_identifier for a \
                  top-level folder, or exactly one of folder_identifier or folder_path as the parent. \
                  account_identifier may accompany folder_path. A sibling name that matches exactly and \
                  case-sensitively fails with folder_name_taken and the existing folder's identifier.",
  },
  ToolDefinition {
    name: TOOL_NOTES_DELETE_FOLDER,
    capability: capabilities::NOTES_DELETE,
    provider: "notes",
    operation: "delete_folder",
    description: "Delete an empty folder and return {folder_identifier}. Pass exactly one of folder_identifier or \
                  folder_path. The script rechecks the live folder immediately before deleting and returns \
                  folder_not_empty if it now holds notes or subfolders. Success is the row gone or marked for \
                  deletion. Refuses folder_not_empty, folder_recently_deleted, folder_smart, and folder_is_default. \
                  If Notes has not saved the delete, the code is folder_delete_unsaved.",
  },
  ToolDefinition {
    name: TOOL_SEARCH_ITEMS,
    // Not a Settings capability. Listing is any of SEARCH_ITEM_CAPABILITIES; the call searches only those.
    capability: "",
    provider: "abridge",
    operation: "search_items",
    description: concat!(
      "Search notes, reminders, and events together. Only stores whose search capability is enabled are queried. \
       ",
      fuzzy_query!(),
      ". stores limits the search to notes, reminders, and/or events. With no event dates, the event range is the \
       same 1 year before through 2 years after the server Mac's current time that eventkit_events_search_events \
       uses, not the caller's. Items are best match first, each with store, the identifier that store's get or \
       delete tool takes (note_identifier, calendar_item_identifier, or event_identifier), title, folder path or \
       list title or calendar, score, and one excerpt. An event item's start_date is the occurrence_date to pass \
       to get, update, and delete. It is local wall time with a numeric offset in the event's time zone, or this \
       Mac's when the event has none, not the caller's. All-day start_date is YYYY-MM-DD and is_all_day is true. \
       limit defaults to 20 (max 100); offset skips merged hits (default 0). A store that fails or is denied is \
       listed in store_errors; the other stores are still returned. \
       Absent keys mean null, false, or empty."
    ),
  },
];

pub fn all_tools() -> &'static [ToolDefinition] {
  &ALL_TOOLS
}

/// Capabilities that list and run `abridge_search_items`. Any one is enough to list it.
pub const SEARCH_ITEM_CAPABILITIES: [&str; 3] = [
  capabilities::NOTES_SEARCH,
  capabilities::EVENTKIT_REMINDERS_SEARCH,
  capabilities::EVENTKIT_EVENTS_SEARCH,
];

pub fn search_items_enabled(enabled: &[String]) -> bool {
  enabled
    .iter()
    .any(|capability| SEARCH_ITEM_CAPABILITIES.contains(&capability.as_str()))
}

pub fn tools_for_capabilities(enabled: &[String]) -> Vec<&'static ToolDefinition> {
  let cross = search_items_enabled(enabled);
  all_tools()
    .iter()
    .filter(|tool| {
      if tool.name == TOOL_SEARCH_ITEMS {
        cross
      } else {
        enabled.iter().any(|capability| capability == tool.capability)
      }
    })
    .collect()
}

/// Resolves a `tools/call` name against the registry.
pub fn resolve_tool(name: &str) -> Option<&'static ToolDefinition> {
  all_tools().iter().find(|tool| tool.name == name)
}

fn coordinate_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "object",
    "properties": {
      "latitude": { "type": "number", "minimum": -90, "maximum": 90 },
      "longitude": { "type": "number", "minimum": -180, "maximum": 180 }
    },
    "required": ["latitude", "longitude"]
  })
}

fn route_endpoint_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "object",
    "properties": {
      "coordinate": coordinate_schema(),
      "name": {
        "type": "string",
        "minLength": 1,
        "description": "Label on the result. It does not geocode. Pass a coordinate or a MapKit identifier from mapkit_search_places."
      },
      "identifier": { "type": "string", "minLength": 1 }
    }
  })
}

/// Optional `transport_type`; Swift treats omitted or null as `.automobile`.
fn nullable_transport_type_schema() -> serde_json::Value {
  serde_json::json!({
    "type": ["string", "null"],
    "enum": ["automobile", "walking", "transit", "cycling", "any", null]
  })
}

fn nullable_string() -> serde_json::Value {
  serde_json::json!({ "type": ["string", "null"] })
}

fn non_whitespace_string() -> serde_json::Value {
  serde_json::json!({ "type": "string", "pattern": r".*\S.*" })
}

fn nullable_string_date_time() -> serde_json::Value {
  serde_json::json!({ "type": ["string", "null"], "format": "date-time" })
}

/// An absolute instant. The server Mac's zone is not applied.
fn offset_date_time_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "string",
    "format": "date-time",
    "description": absolute_instant!()
  })
}

fn occurrence_date_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "string",
    "description": "start_date of one occurrence. Offset form, or YYYY-MM-DD when all-day."
  })
}

fn event_span_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "string",
    "enum": ["this_event", "future_events"],
    "description": "this_event changes that occurrence. future_events also changes later ones. Omit for this_event."
  })
}

fn event_write_date_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "string",
    "description": concat!(
      "Timed value, ",
      client_resolves_relative_date!(),
      ". All-day: 2026-10-26 with is_all_day."
    )
  })
}

fn nullable_integer() -> serde_json::Value {
  serde_json::json!({ "type": ["integer", "null"] })
}

fn nullable_number() -> serde_json::Value {
  serde_json::json!({ "type": ["number", "null"] })
}

fn nullable_integer_array() -> serde_json::Value {
  serde_json::json!({
    "type": ["array", "null"],
    "items": { "type": "integer" }
  })
}

fn alarm_entry_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "object",
    "properties": {
      "absolute_date": with_description(
        nullable_string_date_time(),
        absolute_instant!()
      ),
      "relative_offset": with_description(nullable_number(), "Seconds from the start. Negative is before."),
      "proximity": {
        "type": ["string", "null"],
        "enum": ["none", "enter", "leave", null]
      },
      "email_address": nullable_string(),
      "structured_location": structured_location_schema(true)
    }
  })
}

fn alarms_array_schema(nullable: bool) -> serde_json::Value {
  if nullable {
    serde_json::json!({
      "type": ["array", "null"],
      "items": alarm_entry_schema()
    })
  } else {
    serde_json::json!({
      "type": "array",
      "items": alarm_entry_schema()
    })
  }
}

fn recurrence_rule_entry_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "object",
    "properties": {
      "frequency": {
        "type": "string",
        "enum": ["daily", "weekly", "monthly", "yearly"]
      },
      "interval": nullable_integer(),
      "recurrence_end": {
        "type": ["object", "null"],
        "properties": {
          "end_date": with_description(
            nullable_string_date_time(),
            absolute_instant!()
          ),
          "occurrence_count": nullable_integer()
        }
      },
      "days_of_the_week": {
        "type": ["array", "null"],
        "items": {
          "type": "object",
          "properties": {
            "day_of_the_week": {
              "type": "string",
              "enum": ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            },
            "week_number": nullable_integer()
          },
          "required": ["day_of_the_week"]
        }
      },
      "days_of_the_month": nullable_integer_array(),
      "days_of_the_year": nullable_integer_array(),
      "months_of_the_year": nullable_integer_array(),
      "weeks_of_the_year": nullable_integer_array(),
      "set_positions": nullable_integer_array()
    },
    "required": ["frequency"]
  })
}

fn structured_location_schema(nullable: bool) -> serde_json::Value {
  let schema = serde_json::json!({
    "type": "object",
    "properties": {
      "title": nullable_string(),
      "radius": with_description(nullable_number(), "Meters."),
      "geo_location": {
        "type": ["object", "null"],
        "description": "latitude and longitude.",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"]
      }
    }
  });

  if nullable {
    serde_json::json!({
      "type": ["object", "null"],
      "properties": schema.get("properties").cloned().unwrap_or_default()
    })
  } else {
    schema
  }
}

fn with_description(mut schema: serde_json::Value, description: &str) -> serde_json::Value {
  if let Some(object) = schema.as_object_mut() {
    object.insert("description".to_owned(), serde_json::json!(description));
  }
  schema
}

fn reminder_priority_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "integer",
    "minimum": 0,
    "maximum": 9,
    "description": "0 none (omitted on read), 1-4 high, 5 medium, 6-9 low."
  })
}

fn reminder_date_components_schema(nullable: bool) -> serde_json::Value {
  let type_value = if nullable {
    serde_json::json!(["object", "null"])
  } else {
    serde_json::json!("object")
  };
  serde_json::json!({
    "type": type_value,
    "description": "Omit hour and minute for a date-only value. A clock time with no time_zone stays floating (wall \
     time wherever the user is, returned with floating: true and no offset). For 09:00 in New York on \
     2026-10-26, set year 2026, month 10, day 26, hour 9, minute 0, and time_zone America/New_York. This Mac's \
     zone is not applied.",
    "properties": {
      "year": { "type": "integer" },
      "month": { "type": "integer", "minimum": 1, "maximum": 12 },
      "day": { "type": "integer", "minimum": 1, "maximum": 31 },
      "hour": { "type": "integer", "minimum": 0, "maximum": 23 },
      "minute": { "type": "integer", "minimum": 0, "maximum": 59 },
      "second": { "type": "integer", "minimum": 0, "maximum": 60 },
      "time_zone": {
        "type": "string",
        "description": "IANA zone that stamps this value, not the reminder time_zone."
      }
    }
  })
}

fn cg_color_schema(nullable: bool) -> serde_json::Value {
  let type_value = if nullable {
    serde_json::json!(["object", "null"])
  } else {
    serde_json::json!("object")
  };
  serde_json::json!({
    "type": type_value,
    "properties": {
      "components": {
        "type": "array",
        "items": { "type": "number" },
        "minItems": 1
      },
      "alpha": { "type": "number" },
      "color_space_model": { "type": "string" }
    }
  })
}

fn recurrence_rules_array_schema(nullable: bool) -> serde_json::Value {
  if nullable {
    serde_json::json!({
      "type": ["array", "null"],
      "items": recurrence_rule_entry_schema()
    })
  } else {
    serde_json::json!({
      "type": "array",
      "items": recurrence_rule_entry_schema()
    })
  }
}

fn contact_date_components_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "object",
    "description": "year, month, and day are enough for a birthday. time_zone is an IANA name.",
    "properties": {
      "era": nullable_integer(),
      "year": nullable_integer(),
      "month": nullable_integer(),
      "day": nullable_integer(),
      "hour": nullable_integer(),
      "minute": nullable_integer(),
      "second": nullable_integer(),
      "nanosecond": nullable_integer(),
      "weekday": nullable_integer(),
      "weekday_ordinal": nullable_integer(),
      "quarter": nullable_integer(),
      "week_of_month": nullable_integer(),
      "week_of_year": nullable_integer(),
      "year_for_week_of_year": nullable_integer(),
      "is_leap_month": { "type": ["boolean", "null"] },
      "time_zone": nullable_string(),
      "calendar": {
        "type": ["object", "null"],
        "properties": {
          "identifier": nullable_string(),
          "locale": nullable_string(),
          "time_zone": nullable_string(),
          "first_weekday": nullable_integer(),
          "minimum_days_in_first_week": nullable_integer()
        }
      }
    }
  })
}

fn contact_labeled_value_schema(value_schema: serde_json::Value) -> serde_json::Value {
  serde_json::json!({
    "type": "object",
    "properties": {
      "label": with_description(
        nullable_string(),
        "Word: mobile, home, work, or home fax. Omit when unknown. A custom label is kept."
      ),
      "value": value_schema
    },
    "required": ["value"]
  })
}

fn contact_phone_numbers_schema() -> serde_json::Value {
  contact_string_labeled_values_schema()
}

fn contact_postal_addresses_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(serde_json::json!({
      "type": "object",
      "properties": {
        "street": { "type": "string" },
        "sub_locality": { "type": "string" },
        "city": { "type": "string" },
        "sub_administrative_area": { "type": "string" },
        "state": { "type": "string" },
        "postal_code": { "type": "string" },
        "country": { "type": "string" },
        "iso_country_code": { "type": "string" }
      }
    }))
  })
}

fn contact_string_labeled_values_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(serde_json::json!({ "type": "string" }))
  })
}

fn contact_relations_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(serde_json::json!({
      "type": "object",
      "properties": {
        "name": { "type": "string" }
      },
      "required": ["name"]
    }))
  })
}

fn contact_social_profiles_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(serde_json::json!({
      "type": "object",
      "properties": {
        "url_string": nullable_string(),
        "username": nullable_string(),
        "user_identifier": nullable_string(),
        "service": nullable_string()
      }
    }))
  })
}

fn contact_instant_message_addresses_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(serde_json::json!({
      "type": "object",
      "properties": {
        "username": { "type": "string" },
        "service": { "type": "string" }
      },
      "required": ["username", "service"]
    }))
  })
}

fn contact_dates_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(contact_date_components_schema())
  })
}

fn nullable_contact_date_components_schema() -> serde_json::Value {
  let mut base = contact_date_components_schema();
  if let Some(schema) = base.as_object_mut() {
    schema.insert("type".to_owned(), serde_json::json!(["object", "null"]));
  }
  base
}

fn nullable_contact_array_schema(base: &serde_json::Value) -> serde_json::Value {
  serde_json::json!({
    "type": ["array", "null"],
    "items": base.get("items").cloned().unwrap_or_default()
  })
}

fn contact_writable_fields_schema() -> serde_json::Map<String, serde_json::Value> {
  serde_json::json!({
    "contact_type": {
      "type": "string",
      "enum": ["person", "organization"]
    },
    "given_name": nullable_string(),
    "family_name": nullable_string(),
    "middle_name": nullable_string(),
    "name_prefix": nullable_string(),
    "name_suffix": nullable_string(),
    "nickname": nullable_string(),
    "organization_name": nullable_string(),
    "department_name": nullable_string(),
    "job_title": nullable_string(),
    "phonetic_given_name": nullable_string(),
    "phonetic_middle_name": nullable_string(),
    "phonetic_family_name": nullable_string(),
    "phonetic_organization_name": nullable_string(),
    "previous_family_name": nullable_string(),
    "note": nullable_string(),
    "image_data": nullable_string(),
    "birthday": nullable_contact_date_components_schema(),
    "non_gregorian_birthday": nullable_contact_date_components_schema(),
    "phone_numbers": nullable_contact_array_schema(&contact_phone_numbers_schema()),
    "email_addresses": nullable_contact_array_schema(&contact_string_labeled_values_schema()),
    "postal_addresses": nullable_contact_array_schema(&contact_postal_addresses_schema()),
    "url_addresses": nullable_contact_array_schema(&contact_string_labeled_values_schema()),
    "contact_relations": nullable_contact_array_schema(&contact_relations_schema()),
    "social_profiles": nullable_contact_array_schema(&contact_social_profiles_schema()),
    "instant_message_addresses": nullable_contact_array_schema(&contact_instant_message_addresses_schema()),
    "dates": nullable_contact_array_schema(&contact_dates_schema())
  })
  .as_object()
  .cloned()
  .unwrap_or_default()
}

fn note_text(description: &str) -> serde_json::Value {
  with_description(non_whitespace_string(), description)
}

fn note_account_schema() -> serde_json::Value {
  note_text(
    "Account identifier from notes_list_folders. With folder_path, pass it when that path exists in more than one account.",
  )
}

fn note_folder_path_schema() -> serde_json::Value {
  note_text(
    "Exact path from notes_list_folders, case-insensitive, without the account name. Example: Work or Work/Projects. Pass account_identifier when that path exists in two accounts.",
  )
}

fn note_folder_destination_schema() -> serde_json::Value {
  note_text(
    "Destination path from notes_list_folders, case-insensitive. Example: Work or Work/Projects. It does not find the source note.",
  )
}

fn note_folder_parent_schema() -> serde_json::Value {
  note_text(
    "Parent path from notes_list_folders, case-insensitive. Omit it and pass account_identifier for a top-level folder.",
  )
}

fn note_title_schema() -> serde_json::Value {
  note_text(
    "Exact case-insensitive title. folder_path narrows the match. Several matches return note_title_ambiguous and change nothing.",
  )
}

fn note_title_source_schema() -> serde_json::Value {
  note_text(
    "Finds the source note by exact case-insensitive title. Several matches return note_title_ambiguous and change nothing. folder_path is the destination, not a source filter.",
  )
}

fn note_body_schema(description: &str) -> serde_json::Value {
  with_description(serde_json::json!({ "type": "string" }), description)
}

fn vision_image_data_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "string",
    "minLength": 1,
    "description": "Base64 image or PDF. Pass exactly one of image_data or image_path."
  })
}

fn vision_image_path_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "string",
    "minLength": 1,
    "description": "Absolute path of a regular image or PDF file on this Mac, at most 20 MiB. A symlink is followed when the final target is a regular file."
  })
}

fn vision_page_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "integer",
    "minimum": 1,
    "description": "1-based PDF page. Defaults to 1. A page past the end is page_out_of_range. Greater than 1 on an image is invalid_arguments."
  })
}

pub fn input_schema(tool: &ToolDefinition) -> serde_json::Value {
  match tool.name {
    TOOL_LIST_CALENDARS | TOOL_LIST_LISTS => serde_json::json!({
      "type": "object",
      "properties": {}
    }),
    TOOL_LIST_EVENTS => serde_json::json!({
      "type": "object",
      "properties": {
        "start_date": offset_date_time_schema(),
        "end_date": offset_date_time_schema(),
        "calendar_identifier": { "type": "string" },
        "limit": { "type": "integer", "minimum": 1, "maximum": 200 },
        "offset": { "type": "integer", "minimum": 0 }
      },
      "required": ["start_date", "end_date"]
    }),
    TOOL_GET_EVENT => serde_json::json!({
      "type": "object",
      "properties": {
        "event_identifier": non_whitespace_string(),
        "occurrence_date": occurrence_date_schema()
      },
      "required": ["event_identifier"]
    }),
    TOOL_SEARCH_EVENTS => serde_json::json!({
      "type": "object",
      "properties": {
        "start_date": offset_date_time_schema(),
        "end_date": offset_date_time_schema(),
        "calendar_identifier": { "type": "string" },
        "query": non_whitespace_string(),
        "limit": { "type": "integer", "minimum": 1, "maximum": 200 },
        "offset": { "type": "integer", "minimum": 0 }
      },
      "required": ["query"]
    }),
    TOOL_CREATE_EVENT => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_identifier": non_whitespace_string(),
        "title": non_whitespace_string(),
        "notes": { "type": "string" },
        "location": { "type": "string" },
        "url": { "type": "string" },
        "time_zone": { "type": "string" },
        "start_date": event_write_date_schema(),
        "end_date": event_write_date_schema(),
        "is_all_day": { "type": "boolean" },
        "availability": {
          "type": "string",
          "enum": ["not_supported", "busy", "free", "tentative", "unavailable"]
        },
        "structured_location": structured_location_schema(true),
        "alarms": with_description(alarms_array_schema(false), "Omit for none."),
        "recurrence_rules": with_description(recurrence_rules_array_schema(false), "Omit for none.")
      },
      "required": ["calendar_identifier", "title", "start_date", "end_date"]
    }),
    TOOL_ACCEPT_INVITATION | TOOL_DECLINE_INVITATION | TOOL_TENTATIVE_INVITATION => {
      serde_json::json!({
        "type": "object",
        "properties": {
          "event_identifier": { "type": "string" }
        },
        "required": ["event_identifier"]
      })
    }
    TOOL_DELETE_EVENT => serde_json::json!({
      "type": "object",
      "properties": {
        "event_identifier": non_whitespace_string(),
        "event_title": non_whitespace_string(),
        "calendar_identifier": { "type": "string" },
        "start_date": offset_date_time_schema(),
        "end_date": offset_date_time_schema(),
        "occurrence_date": occurrence_date_schema(),
        "span": event_span_schema()
      }
    }),
    TOOL_MOVE_EVENT => serde_json::json!({
      "type": "object",
      "properties": {
        "event_identifier": { "type": "string" },
        "calendar_identifier": { "type": "string" }
      },
      "required": ["event_identifier", "calendar_identifier"]
    }),
    TOOL_UPDATE_EVENT => serde_json::json!({
      "type": "object",
      "properties": {
        "event_identifier": { "type": "string" },
        "calendar_identifier": { "type": "string" },
        "title": { "type": "string" },
        "notes": { "type": ["string", "null"] },
        "location": { "type": ["string", "null"] },
        "url": { "type": ["string", "null"] },
        "time_zone": { "type": ["string", "null"] },
        "start_date": event_write_date_schema(),
        "end_date": event_write_date_schema(),
        "is_all_day": { "type": "boolean" },
        "availability": {
          "type": ["string", "null"],
          "enum": ["not_supported", "busy", "free", "tentative", "unavailable", null]
        },
        "structured_location": structured_location_schema(true),
        "alarms": with_description(alarms_array_schema(true), "Replaces the list. [] or null clears. Omit to leave unchanged."),
        "recurrence_rules": with_description(recurrence_rules_array_schema(true), "Replaces the list. [] or null clears. Omit to leave unchanged."),
        "occurrence_date": occurrence_date_schema(),
        "span": event_span_schema()
      },
      "required": ["event_identifier"]
    }),
    TOOL_CREATE_CALENDAR | TOOL_CREATE_LIST => serde_json::json!({
      "type": "object",
      "properties": {
        "title": non_whitespace_string(),
        "cg_color": cg_color_schema(false),
        "source_identifier": { "type": "string" }
      },
      "required": ["title"]
    }),
    TOOL_UPDATE_CALENDAR => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_identifier": { "type": "string" },
        "title": { "type": "string" },
        "cg_color": cg_color_schema(true),
        "source_identifier": { "type": "string" }
      },
      "required": ["calendar_identifier"]
    }),
    TOOL_LIST_REMINDERS => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_identifier": { "type": "string" },
        "completion_status": {
          "type": "string",
          "enum": ["incomplete", "completed", "all"],
          "description": "incomplete, completed, or all. Omit to list every reminder. A due window without this field is treated as incomplete."
        },
        "due_date_starting": {
          "type": "string",
          "format": "date-time",
          "description": "Start of an incomplete due window, for example 2026-10-26T09:00:00-04:00. This Mac's zone is not applied. A due window returns only reminders that have a due date; undated reminders are included only when this window is omitted. Dropped when include_overdue is true."
        },
        "due_date_ending": {
          "type": "string",
          "format": "date-time",
          "description": "End of an incomplete due window, for example 2026-10-26T17:00:00-04:00. This Mac's zone is not applied. A due window returns only reminders that have a due date."
        },
        "completion_date_starting": offset_date_time_schema(),
        "completion_date_ending": offset_date_time_schema(),
        "include_overdue": {
          "type": "boolean",
          "description": "With an incomplete due window, drop due_date_starting so reminders due before that start are included. due_date_ending still applies."
        },
        "limit": { "type": "integer", "minimum": 1, "maximum": 200 },
        "offset": { "type": "integer", "minimum": 0 }
      }
    }),
    TOOL_GET_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_item_identifier": { "type": "string" }
      },
      "required": ["calendar_item_identifier"]
    }),
    TOOL_SEARCH_REMINDERS => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_identifier": { "type": "string" },
        "completion_status": {
          "type": "string",
          "enum": ["incomplete", "completed", "all"],
          "description": "incomplete, completed, or all. Omit for all. Due dates apply only when incomplete; completion dates only when completed."
        },
        "due_date_starting": {
          "type": "string",
          "format": "date-time",
          "description": "Incomplete due-window start, for example 2026-10-26T09:00:00-04:00. This Mac's zone is not applied. A due window returns only reminders that have a due date; undated reminders are included only when this window is omitted. Dropped when include_overdue is true."
        },
        "due_date_ending": offset_date_time_schema(),
        "completion_date_starting": offset_date_time_schema(),
        "completion_date_ending": offset_date_time_schema(),
        "include_overdue": {
          "type": "boolean",
          "description": "Drop due_date_starting so earlier incomplete reminders are included. due_date_ending still applies."
        },
        "query": non_whitespace_string(),
        "limit": { "type": "integer", "minimum": 1, "maximum": 200 },
        "offset": { "type": "integer", "minimum": 0 }
      }
    }),
    TOOL_CREATE_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_identifier": non_whitespace_string(),
        "title": non_whitespace_string(),
        "notes": { "type": "string" },
        "location": { "type": "string" },
        "url": { "type": "string" },
        "priority": reminder_priority_schema(),
        "due_date_components": reminder_date_components_schema(false),
        "start_date_components": reminder_date_components_schema(false),
        "time_zone": {
          "type": "string",
          "description": "The reminder's time zone. It does not stamp the due time; due_date_components.time_zone does."
        },
        "is_completed": { "type": "boolean" },
        "completion_date": offset_date_time_schema(),
        "alarms": with_description(alarms_array_schema(false), "Omit for none."),
        "recurrence_rules": with_description(recurrence_rules_array_schema(false), "Omit for none.")
      },
      "required": ["calendar_identifier", "title"]
    }),
    TOOL_UPDATE_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_item_identifier": { "type": "string" },
        "calendar_identifier": { "type": "string" },
        "title": { "type": "string" },
        "notes": { "type": ["string", "null"] },
        "location": { "type": ["string", "null"] },
        "url": { "type": ["string", "null"] },
        "priority": reminder_priority_schema(),
        "due_date_components": reminder_date_components_schema(true),
        "start_date_components": reminder_date_components_schema(true),
        "time_zone": {
          "type": ["string", "null"],
          "description": "The reminder's time zone. It does not stamp the due time; due_date_components.time_zone does. Null clears it."
        },
        "is_completed": { "type": "boolean" },
        "completion_date": with_description(
          nullable_string_date_time(),
          absolute_instant!()
        ),
        "alarms": with_description(alarms_array_schema(true), "Replaces the list. [] or null clears. Omit to leave unchanged."),
        "recurrence_rules": with_description(recurrence_rules_array_schema(true), "Replaces the list. [] or null clears. Omit to leave unchanged.")
      },
      "required": ["calendar_item_identifier"]
    }),
    TOOL_MOVE_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_item_identifier": { "type": "string" },
        "calendar_identifier": { "type": "string" }
      },
      "required": ["calendar_item_identifier", "calendar_identifier"]
    }),
    TOOL_DELETE_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_item_identifier": non_whitespace_string(),
        "reminder_title": non_whitespace_string(),
        "calendar_identifier": { "type": "string" }
      }
    }),
    TOOL_DELETE_LIST | TOOL_DELETE_CALENDAR => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_identifier": { "type": "string" }
      },
      "required": ["calendar_identifier"]
    }),
    TOOL_COMPLETE_REMINDER | TOOL_UNCOMPLETE_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_item_identifier": { "type": "string" }
      },
      "required": ["calendar_item_identifier"]
    }),
    TOOL_LIST_CONTAINERS => serde_json::json!({
      "type": "object",
      "additionalProperties": false
    }),
    TOOL_LIST_CONTACTS | TOOL_LIST_GROUPS => serde_json::json!({
      "type": "object",
      "properties": {
        "container_identifier": { "type": "string" },
        "limit": { "type": "integer", "minimum": 1, "maximum": 200 },
        "offset": { "type": "integer", "minimum": 0 }
      }
    }),
    TOOL_GET_CONTACT | TOOL_DELETE_CONTACT => serde_json::json!({
      "type": "object",
      "properties": {
        "contact_identifier": non_whitespace_string()
      },
      "required": ["contact_identifier"]
    }),
    TOOL_DELETE_GROUP => serde_json::json!({
      "type": "object",
      "properties": {
        "group_identifier": non_whitespace_string()
      },
      "required": ["group_identifier"]
    }),
    TOOL_SEARCH_CONTACTS => serde_json::json!({
      "type": "object",
      "properties": {
        "name": { "type": "string", "minLength": 1 },
        "email_address": { "type": "string", "minLength": 1 },
        "phone_number": { "type": "string", "minLength": 1 },
        "container_identifier": { "type": "string" },
        "query": {
          "type": "string",
          "minLength": 1,
          "description": "Provide at least one of query, name, email_address, or phone_number."
        },
        "limit": { "type": "integer", "minimum": 1, "maximum": 200 },
        "offset": { "type": "integer", "minimum": 0 }
      }
    }),
    TOOL_CREATE_GROUP => serde_json::json!({
      "type": "object",
      "properties": {
        "container_identifier": non_whitespace_string(),
        "name": non_whitespace_string()
      },
      "required": ["name"]
    }),
    TOOL_CREATE_CONTACT => serde_json::json!({
      "type": "object",
      "properties": {
        "container_identifier": non_whitespace_string(),
        "contact_type": {
          "type": "string",
          "enum": ["person", "organization"]
        },
        "given_name": {
          "type": "string",
          "pattern": r".*\S.*",
          "description": "Provide at least one of given_name, family_name, or organization_name."
        },
        "family_name": { "type": "string", "pattern": r".*\S.*" },
        "middle_name": { "type": "string" },
        "name_prefix": { "type": "string" },
        "name_suffix": { "type": "string" },
        "nickname": { "type": "string" },
        "organization_name": { "type": "string", "pattern": r".*\S.*" },
        "department_name": { "type": "string" },
        "job_title": { "type": "string" },
        "phonetic_given_name": { "type": "string" },
        "phonetic_middle_name": { "type": "string" },
        "phonetic_family_name": { "type": "string" },
        "phonetic_organization_name": { "type": "string" },
        "previous_family_name": { "type": "string" },
        "note": { "type": "string" },
        "image_data": { "type": "string" },
        "birthday": contact_date_components_schema(),
        "non_gregorian_birthday": contact_date_components_schema(),
        "phone_numbers": contact_phone_numbers_schema(),
        "email_addresses": contact_string_labeled_values_schema(),
        "postal_addresses": contact_postal_addresses_schema(),
        "url_addresses": contact_string_labeled_values_schema(),
        "contact_relations": contact_relations_schema(),
        "social_profiles": contact_social_profiles_schema(),
        "instant_message_addresses": contact_instant_message_addresses_schema(),
        "dates": contact_dates_schema()
      }
    }),
    TOOL_UPDATE_CONTACT => {
      let mut properties = contact_writable_fields_schema();
      properties.insert("contact_identifier".to_owned(), serde_json::json!({ "type": "string" }));
      serde_json::json!({
        "type": "object",
        "properties": properties,
        "required": ["contact_identifier"]
      })
    }
    TOOL_LINK_CONTACTS => serde_json::json!({
      "type": "object",
      "properties": {
        "from_contact_identifier": non_whitespace_string(),
        "to_contact_identifier": non_whitespace_string()
      },
      "required": ["from_contact_identifier", "to_contact_identifier"]
    }),
    TOOL_UNLINK_CONTACTS => serde_json::json!({
      "type": "object",
      "properties": {
        "contact_identifier": non_whitespace_string()
      },
      "required": ["contact_identifier"]
    }),
    TOOL_UPDATE_GROUP => serde_json::json!({
      "type": "object",
      "properties": {
        "group_identifier": { "type": "string" },
        "name": {
          "type": ["string", "null"],
          "pattern": r".*\S.*"
        }
      },
      "required": ["group_identifier"],
      "additionalProperties": false
    }),
    TOOL_SEARCH_PLACES => serde_json::json!({
      "type": "object",
      "properties": {
        "query": { "type": "string", "minLength": 1 },
        "region": {
          "type": "object",
          "properties": {
            "center": {
              "type": "object",
              "properties": {
                "latitude": { "type": "number", "minimum": -90, "maximum": 90 },
                "longitude": { "type": "number", "minimum": -180, "maximum": 180 }
              },
              "required": ["latitude", "longitude"]
            },
            "span": {
              "type": "object",
              "properties": {
                "latitude_delta": { "type": "number", "exclusiveMinimum": 0 },
                "longitude_delta": { "type": "number", "exclusiveMinimum": 0 }
              },
              "required": ["latitude_delta", "longitude_delta"]
            }
          },
          "required": ["center", "span"]
        },
        "region_priority": {
          "type": "string",
          "enum": ["default", "required"]
        },
        "result_types": {
          "type": "array",
          "items": {
            "type": "string",
            "enum": [
              "address",
              "point_of_interest",
              "physical_feature"
            ]
          }
        }
      },
      "required": ["query"]
    }),
    TOOL_SEARCH_NEARBY => serde_json::json!({
      "type": "object",
      "properties": {
        "region": {
          "type": "object",
          "properties": {
            "center": {
              "type": "object",
              "properties": {
                "latitude": { "type": "number", "minimum": -90, "maximum": 90 },
                "longitude": { "type": "number", "minimum": -180, "maximum": 180 }
              },
              "required": ["latitude", "longitude"]
            },
            "span": {
              "type": "object",
              "properties": {
                "latitude_delta": { "type": "number", "exclusiveMinimum": 0 },
                "longitude_delta": { "type": "number", "exclusiveMinimum": 0 }
              },
              "required": ["latitude_delta", "longitude_delta"]
            }
          },
          "required": ["center", "span"]
        },
        "coordinate": {
          "type": "object",
          "properties": {
            "latitude": { "type": "number", "minimum": -90, "maximum": 90 },
            "longitude": { "type": "number", "minimum": -180, "maximum": 180 }
          },
          "required": ["latitude", "longitude"]
        },
        "radius_meters": { "type": "number", "exclusiveMinimum": 0 },
        "including_categories": {
          "type": "array",
          "items": { "type": "string", "minLength": 1 }
        },
        "excluding_categories": {
          "type": "array",
          "items": { "type": "string", "minLength": 1 }
        }
      }
    }),
    TOOL_REVERSE_GEOCODE => serde_json::json!({
      "type": "object",
      "properties": {
        "coordinate": {
          "type": "object",
          "properties": {
            "latitude": { "type": "number", "minimum": -90, "maximum": 90 },
            "longitude": { "type": "number", "minimum": -180, "maximum": 180 }
          },
          "required": ["latitude", "longitude"]
        }
      },
      "required": ["coordinate"]
    }),
    TOOL_FORWARD_GEOCODE => serde_json::json!({
      "type": "object",
      "properties": {
        "address": { "type": "string", "minLength": 1 },
        "region": {
          "type": "object",
          "properties": {
            "center": {
              "type": "object",
              "properties": {
                "latitude": { "type": "number", "minimum": -90, "maximum": 90 },
                "longitude": { "type": "number", "minimum": -180, "maximum": 180 }
              },
              "required": ["latitude", "longitude"]
            },
            "span": {
              "type": "object",
              "properties": {
                "latitude_delta": { "type": "number", "exclusiveMinimum": 0 },
                "longitude_delta": { "type": "number", "exclusiveMinimum": 0 }
              },
              "required": ["latitude_delta", "longitude_delta"]
            }
          },
          "required": ["center", "span"]
        },
        "preferred_locale": { "type": "string", "minLength": 1 }
      },
      "required": ["address"]
    }),
    TOOL_GET_CURRENT_LOCATION => serde_json::json!({
      "type": "object"
    }),
    TOOL_CALCULATE_ROUTE => serde_json::json!({
      "type": "object",
      "properties": {
        "source": route_endpoint_schema(),
        "destination": route_endpoint_schema(),
        "transport_type": {
          "type": "string",
          "enum": ["automobile", "walking", "transit", "cycling", "any"]
        },
        "requests_alternate_routes": { "type": "boolean" },
        "departure_date": offset_date_time_schema(),
        "arrival_date": offset_date_time_schema(),
        "toll_preference": {
          "type": "string",
          "enum": ["any", "avoid"]
        },
        "highway_preference": {
          "type": "string",
          "enum": ["any", "avoid"]
        }
      },
      "required": ["source", "destination"]
    }),
    TOOL_ESTIMATE_TRAVEL_TIME => serde_json::json!({
      "type": "object",
      "properties": {
        "source": route_endpoint_schema(),
        "destination": route_endpoint_schema(),
        "transport_type": {
          "type": "string",
          "enum": ["automobile", "walking", "transit", "cycling", "any"]
        },
        "departure_date": {
          "type": "string",
          "format": "date-time",
          "description": "Provide exactly one of departure_date or arrival_date, or neither."
        },
        "arrival_date": {
          "type": "string",
          "format": "date-time",
          "description": "Provide exactly one of departure_date or arrival_date, or neither."
        }
      },
      "required": ["source", "destination"]
    }),
    TOOL_GET_PLACE => serde_json::json!({
      "type": "object",
      "properties": {
        "identifier": { "type": "string", "minLength": 1 }
      },
      "required": ["identifier"]
    }),
    TOOL_OPEN_NAVIGATION => serde_json::json!({
      "type": "object",
      "properties": {
        "source": route_endpoint_schema(),
        "destination": route_endpoint_schema(),
        "transport_type": nullable_transport_type_schema()
      },
      "required": ["source", "destination"]
    }),
    TOOL_GET_USAGE_LOG => serde_json::json!({
      "type": "object",
      "properties": {
        "limit": { "type": "integer", "minimum": 0 }
      }
    }),
    TOOL_RECOGNIZE_DOCUMENTS => serde_json::json!({
      "type": "object",
      "properties": {
        "image_data": vision_image_data_schema(),
        "image_path": vision_image_path_schema(),
        "page": vision_page_schema(),
        "orientation": { "type": "integer", "minimum": 1, "maximum": 8 },
        "revision": { "type": "string", "enum": ["revision1"] },
        "region_of_interest": {
          "type": "object",
          "description": "Normalized crop region. Per-field bounds are 0...1 for origin and (0,1] for size; the rectangle must also satisfy origin.x + size.width <= 1 and origin.y + size.height <= 1.",
          "properties": {
            "origin": {
              "type": "object",
              "properties": {
                "x": { "type": "number", "minimum": 0, "maximum": 1 },
                "y": { "type": "number", "minimum": 0, "maximum": 1 }
              },
              "required": ["x", "y"]
            },
            "size": {
              "type": "object",
              "properties": {
                "width": { "type": "number", "exclusiveMinimum": 0, "maximum": 1 },
                "height": { "type": "number", "exclusiveMinimum": 0, "maximum": 1 }
              },
              "required": ["width", "height"]
            }
          },
          "required": ["origin", "size"]
        },
        "text_recognition_options": {
          "type": "object",
          "properties": {
            "minimum_text_height_fraction": { "type": "number", "minimum": 0 },
            "automatically_detect_language": { "type": "boolean" },
            "recognition_languages": {
              "type": "array",
              "items": { "type": "string", "minLength": 1 }
            },
            "use_language_correction": { "type": "boolean" },
            "custom_words": {
              "type": "array",
              "items": { "type": "string" }
            },
            "maximum_candidate_count": { "type": "integer", "minimum": 1, "maximum": 10 }
          }
        },
        "barcode_detection_options": {
          "type": "object",
          "properties": {
            "enabled": { "type": "boolean" },
            "symbologies": {
              "type": "array",
              "items": { "type": "string" }
            },
            "coalesce_composite_symbologies": { "type": "boolean" }
          }
        },
        "include_segmentation": { "type": "boolean" }
      },
    }),
    TOOL_DETECT_BARCODES => serde_json::json!({
      "type": "object",
      "properties": {
        "image_data": vision_image_data_schema(),
        "image_path": vision_image_path_schema(),
        "page": vision_page_schema(),
        "orientation": { "type": "integer", "minimum": 1, "maximum": 8 },
        "revision": { "type": "string", "enum": ["revision1", "revision4"] },
        "region_of_interest": {
          "type": "object",
          "properties": {
            "origin": {
              "type": "object",
              "properties": {
                "x": { "type": "number" },
                "y": { "type": "number" }
              },
              "required": ["x", "y"]
            },
            "size": {
              "type": "object",
              "properties": {
                "width": { "type": "number" },
                "height": { "type": "number" }
              },
              "required": ["width", "height"]
            }
          },
          "required": ["origin", "size"]
        },
        "symbologies": {
          "type": "array",
          "items": { "type": "string" }
        },
        "coalesce_composite_symbologies": { "type": "boolean" }
      },
    }),
    TOOL_DETECT_FACE_LANDMARKS => serde_json::json!({
      "type": "object",
      "properties": {
        "image_data": vision_image_data_schema(),
        "image_path": vision_image_path_schema(),
        "page": vision_page_schema(),
        "orientation": { "type": "integer", "minimum": 1, "maximum": 8 },
        "revision": { "type": "integer", "enum": [1, 2, 3] },
        "region_of_interest": {
          "type": "object",
          "properties": {
            "origin": {
              "type": "object",
              "properties": {
                "x": { "type": "number", "minimum": 0, "maximum": 1 },
                "y": { "type": "number", "minimum": 0, "maximum": 1 }
              },
              "required": ["x", "y"]
            },
            "size": {
              "type": "object",
              "properties": {
                "width": { "type": "number", "exclusiveMinimum": 0, "maximum": 1 },
                "height": { "type": "number", "exclusiveMinimum": 0, "maximum": 1 }
              },
              "required": ["width", "height"]
            }
          },
          "required": ["origin", "size"]
        },
        "constellation": {
          "type": "string",
          "enum": ["not_defined", "65_points", "76_points"]
        }
      },
    }),
    TOOL_RECOGNIZE_TEXT => serde_json::json!({
      "type": "object",
      "properties": {
        "image_data": vision_image_data_schema(),
        "image_path": vision_image_path_schema(),
        "page": vision_page_schema(),
        "orientation": { "type": "integer", "minimum": 1, "maximum": 8 },
        "recognition_languages": {
          "type": "array",
          "items": { "type": "string" }
        },
        "custom_words": {
          "type": "array",
          "items": { "type": "string" }
        },
        "recognition_level": {
          "type": "string",
          "enum": ["accurate", "fast"]
        },
        "uses_language_correction": { "type": "boolean" },
        "automatically_detects_language": { "type": "boolean" },
        "minimum_text_height": { "type": "number", "minimum": 0 },
        "revision": { "type": "integer" },
        "prefer_background_processing": { "type": "boolean" },
        "region_of_interest": {
          "type": "object",
          "properties": {
            "origin": {
              "type": "object",
              "properties": {
                "x": { "type": "number" },
                "y": { "type": "number" }
              },
              "required": ["x", "y"]
            },
            "size": {
              "type": "object",
              "properties": {
                "width": { "type": "number" },
                "height": { "type": "number" }
              },
              "required": ["width", "height"]
            }
          },
          "required": ["origin", "size"]
        },
        "max_candidate_count": { "type": "integer", "minimum": 1, "maximum": 10 }
      },
    }),
    TOOL_SET_REMINDER_ALARMS => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_item_identifier": { "type": "string" },
        "alarms": with_description(
          alarms_array_schema(false),
          "Replaces the list. [] removes all."
        )
      },
      "required": ["calendar_item_identifier", "alarms"]
    }),
    TOOL_SET_EVENT_ALARMS => serde_json::json!({
      "type": "object",
      "properties": {
        "event_identifier": { "type": "string" },
        "alarms": with_description(
          alarms_array_schema(false),
          "Replaces the list. [] removes all."
        )
      },
      "required": ["event_identifier", "alarms"]
    }),
    TOOL_SET_REMINDER_RECURRENCE => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_item_identifier": { "type": "string" },
        "recurrence_rules": with_description(
          recurrence_rules_array_schema(false),
          "Replaces the list. [] clears."
        )
      },
      "required": ["calendar_item_identifier", "recurrence_rules"]
    }),
    TOOL_SET_EVENT_RECURRENCE => serde_json::json!({
      "type": "object",
      "properties": {
        "event_identifier": { "type": "string" },
        "recurrence_rules": with_description(
          recurrence_rules_array_schema(false),
          "Replaces the list. [] clears."
        )
      },
      "required": ["event_identifier", "recurrence_rules"]
    }),
    TOOL_NOTES_LIST_FOLDERS => serde_json::json!({
      "type": "object",
      "properties": {
        "account_identifier": note_account_schema()
      }
    }),
    TOOL_NOTES_LIST_NOTES => serde_json::json!({
      "type": "object",
      "properties": {
        "folder_identifier": non_whitespace_string(),
        "folder_path": note_folder_path_schema(),
        "account_identifier": note_account_schema(),
        "limit": {
          "type": "integer",
          "minimum": 1,
          "maximum": 200,
          "description": "Defaults to 50. Maximum 200."
        },
        "offset": {
          "type": "integer",
          "minimum": 0,
          "description": "Skips this many summaries."
        }
      }
    }),
    TOOL_NOTES_GET_NOTE | TOOL_NOTES_DELETE_NOTE => serde_json::json!({
      "type": "object",
      "properties": {
        "note_identifier": non_whitespace_string(),
        "note_title": note_title_schema(),
        "folder_identifier": non_whitespace_string(),
        "folder_path": note_folder_path_schema(),
        "account_identifier": note_account_schema()
      }
    }),
    TOOL_NOTES_GET_ATTACHMENT => serde_json::json!({
      "type": "object",
      "properties": {
        "attachment_identifier": non_whitespace_string(),
        "format": { "type": "string", "enum": ["markdown", "image", "original"] },
        "max_characters": { "type": "integer", "minimum": 1, "maximum": 100000 },
        "page": {
          "type": "integer",
          "minimum": 1,
          "description": "1-based page of a PDF or scan for format image; default 1."
        },
        "offset": {
          "type": "integer",
          "minimum": 0,
          "description": "Unicode-character offset into markdown content, not a page or a byte offset. Continue from next_offset while content_truncated is true."
        }
      },
      "required": ["attachment_identifier"]
    }),
    TOOL_NOTES_SEARCH_NOTES => serde_json::json!({
      "type": "object",
      "properties": {
        "query": non_whitespace_string(),
        "folder_identifier": non_whitespace_string(),
        "folder_path": note_folder_path_schema(),
        "account_identifier": note_account_schema(),
        "modified_after": { "type": "string", "format": "date-time" },
        "modified_before": { "type": "string", "format": "date-time" },
        "limit": {
          "type": "integer",
          "minimum": 1,
          "maximum": 100,
          "description": "Defaults to 20. Maximum 100."
        },
        "offset": {
          "type": "integer",
          "minimum": 0,
          "description": "Skips this many hits."
        }
      },
      "required": ["query"]
    }),
    TOOL_NOTES_CREATE_NOTE => serde_json::json!({
      "type": "object",
      "properties": {
        "folder_identifier": non_whitespace_string(),
        "folder_path": note_folder_path_schema(),
        "account_identifier": note_account_schema(),
        "body": note_body_schema("Whole Markdown body. The first line `# Title` is the title. There is no separate title field. `- [ ]` and `- [x]` become ordinary bullets.")
      },
      "required": ["body"]
    }),
    TOOL_NOTES_UPDATE_NOTE => serde_json::json!({
      "type": "object",
      "properties": {
        "note_identifier": non_whitespace_string(),
        "note_title": note_title_schema(),
        "folder_identifier": non_whitespace_string(),
        "folder_path": note_folder_path_schema(),
        "account_identifier": note_account_schema(),
        "body": note_body_schema("Replaces the whole body, including the title as the first `# Title` line. It does not append.")
      },
      "required": ["body"]
    }),
    TOOL_NOTES_MOVE_NOTE => serde_json::json!({
      "type": "object",
      "properties": {
        "note_identifier": non_whitespace_string(),
        "note_title": note_title_source_schema(),
        "folder_identifier": with_description(non_whitespace_string(), "Destination folder identifier. It does not find the source note."),
        "folder_path": note_folder_destination_schema(),
        "account_identifier": note_account_schema()
      }
    }),
    TOOL_NOTES_CREATE_FOLDER => serde_json::json!({
      "type": "object",
      "properties": {
        "name": non_whitespace_string(),
        "account_identifier": note_account_schema(),
        "folder_identifier": non_whitespace_string(),
        "folder_path": note_folder_parent_schema()
      },
      "required": ["name"]
    }),
    TOOL_NOTES_DELETE_FOLDER => serde_json::json!({
      "type": "object",
      "properties": {
        "folder_identifier": non_whitespace_string(),
        "folder_path": note_folder_path_schema(),
        "account_identifier": note_account_schema()
      }
    }),
    TOOL_SEARCH_ITEMS => serde_json::json!({
      "type": "object",
      "properties": {
        "query": with_description(non_whitespace_string(), fuzzy_query!()),
        "stores": {
          "type": "array",
          "minItems": 1,
          "uniqueItems": true,
          "items": { "type": "string", "enum": ["notes", "reminders", "events"] },
          "description": "Omit to search every enabled store. notes, reminders, and/or events."
        },
        "start_date": offset_date_time_schema(),
        "end_date": offset_date_time_schema(),
        "limit": { "type": "integer", "minimum": 1, "maximum": 100 },
        "offset": {
          "type": "integer",
          "minimum": 0,
          "description": "Skips this many merged hits."
        }
      },
      "required": ["query"]
    }),
    _ => serde_json::json!({ "type": "object" }),
  }
}

#[cfg(test)]
mod tests {
  use super::{
    TOOL_ACCEPT_INVITATION, TOOL_CALCULATE_ROUTE, TOOL_COMPLETE_REMINDER, TOOL_CREATE_CALENDAR, TOOL_CREATE_CONTACT,
    TOOL_CREATE_EVENT, TOOL_CREATE_GROUP, TOOL_CREATE_LIST, TOOL_CREATE_REMINDER, TOOL_DECLINE_INVITATION,
    TOOL_DELETE_CALENDAR, TOOL_DELETE_CONTACT, TOOL_DELETE_EVENT, TOOL_DELETE_GROUP, TOOL_DELETE_LIST,
    TOOL_DELETE_REMINDER, TOOL_DETECT_BARCODES, TOOL_DETECT_FACE_LANDMARKS, TOOL_ESTIMATE_TRAVEL_TIME,
    TOOL_FORWARD_GEOCODE, TOOL_GET_CONTACT, TOOL_GET_CURRENT_LOCATION, TOOL_GET_EVENT, TOOL_GET_PLACE,
    TOOL_GET_REMINDER, TOOL_GET_USAGE_LOG, TOOL_LINK_CONTACTS, TOOL_LIST_CALENDARS, TOOL_LIST_CONTACTS,
    TOOL_LIST_CONTAINERS, TOOL_LIST_EVENTS, TOOL_LIST_GROUPS, TOOL_LIST_LISTS, TOOL_LIST_REMINDERS, TOOL_MOVE_EVENT,
    TOOL_MOVE_REMINDER, TOOL_OPEN_NAVIGATION, TOOL_RECOGNIZE_DOCUMENTS, TOOL_RECOGNIZE_TEXT, TOOL_REVERSE_GEOCODE,
    TOOL_SEARCH_CONTACTS, TOOL_SEARCH_EVENTS, TOOL_SEARCH_ITEMS, TOOL_SEARCH_NEARBY, TOOL_SEARCH_PLACES,
    TOOL_SEARCH_REMINDERS, TOOL_SET_EVENT_ALARMS, TOOL_SET_EVENT_RECURRENCE, TOOL_SET_REMINDER_ALARMS,
    TOOL_SET_REMINDER_RECURRENCE, TOOL_TENTATIVE_INVITATION, TOOL_UNCOMPLETE_REMINDER, TOOL_UNLINK_CONTACTS,
    TOOL_UPDATE_CALENDAR, TOOL_UPDATE_CONTACT, TOOL_UPDATE_EVENT, TOOL_UPDATE_GROUP, TOOL_UPDATE_REMINDER, all_tools,
    input_schema, resolve_tool, tools_for_capabilities,
  };

  /// Claude Code exposes `mcp__<server>__<tool>` and rejects names over 64; 50 leaves room for `mcp__abridge__`.
  const MAX_TOOL_NAME_LEN: usize = 50;

  fn array_items_type(schema: &serde_json::Value, property: &str) -> Option<String> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("items"))
      .and_then(|items| items.get("type"))
      .and_then(|value| value.as_str())
      .map(str::to_owned)
  }

  fn array_item_properties(
    schema: &serde_json::Value,
    property: &str,
  ) -> Option<serde_json::Map<String, serde_json::Value>> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("items"))
      .and_then(|items| items.get("properties"))
      .and_then(|value| value.as_object())
      .cloned()
  }

  /// `^[a-z0-9]+(_[a-z0-9]+)*$` without a regex crate.
  fn is_snake_tool_name(name: &str) -> bool {
    let bytes = name.as_bytes();
    if bytes.is_empty() || bytes.len() > MAX_TOOL_NAME_LEN {
      return false;
    }
    let mut started = false;
    let mut prev_underscore = false;
    for &b in bytes {
      match b {
        b'a'..=b'z' | b'0'..=b'9' => {
          started = true;
          prev_underscore = false;
        }
        b'_' if started && !prev_underscore => prev_underscore = true,
        _ => return false,
      }
    }
    started && !prev_underscore
  }

  fn name_matches_provider_operation(tool: &super::ToolDefinition) -> bool {
    let mut direct = String::with_capacity(tool.provider.len() + 1 + tool.operation.len());
    direct.push_str(tool.provider);
    direct.push('_');
    direct.push_str(tool.operation);
    if tool.name == direct {
      return true;
    }
    let Some(rest) = tool.name.strip_prefix(tool.provider).and_then(|s| s.strip_prefix('_')) else {
      return false;
    };
    let Some((domain, operation)) = rest.split_once('_') else {
      return false;
    };
    !domain.is_empty() && domain.bytes().all(|b| b.is_ascii_lowercase()) && operation == tool.operation
  }

  #[test]
  fn tool_names_follow_client_safe_naming_rules() {
    let mut names = std::collections::HashSet::new();
    let mut pairs = std::collections::HashSet::new();
    for tool in all_tools() {
      assert!(
        is_snake_tool_name(tool.name),
        "{} is not ^[a-z0-9]+(_[a-z0-9]+)*$ or exceeds {MAX_TOOL_NAME_LEN} chars",
        tool.name
      );
      assert!(
        name_matches_provider_operation(tool),
        "{} is not {{provider}}_{{operation}} or {{provider}}_{{domain}}_{{operation}}",
        tool.name
      );
      if tool.provider == "abridge" {
        assert!(
          tool.capability.is_empty(),
          "{} is a cross-provider tool and must not claim one capability",
          tool.name
        );
      } else {
        let capability = tool.capability.as_bytes();
        let provider = tool.provider.as_bytes();
        assert!(
          capability.starts_with(provider) && capability.get(provider.len()) == Some(&b'.'),
          "{} capability {} is not namespaced by {}",
          tool.name,
          tool.capability,
          tool.provider
        );
      }
      assert!(names.insert(tool.name), "duplicate tool name {}", tool.name);
      assert!(
        pairs.insert((tool.provider, tool.operation)),
        "duplicate (provider, operation) ({}, {})",
        tool.provider,
        tool.operation
      );
      assert_eq!(resolve_tool(tool.name).map(|resolved| resolved.name), Some(tool.name));
      if tool.name.contains('_') {
        assert!(resolve_tool(&tool.name.replace('_', ".")).is_none());
      }
    }
  }

  #[test]
  fn set_reminder_alarms_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SET_REMINDER_ALARMS)
      .expect("set_reminder_alarms tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
  }

  #[test]
  fn set_event_alarms_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SET_EVENT_ALARMS)
      .expect("set_event_alarms tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
  }

  #[test]
  fn set_reminder_recurrence_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SET_REMINDER_RECURRENCE)
      .expect("set_reminder_recurrence tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn set_event_recurrence_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SET_EVENT_RECURRENCE)
      .expect("set_event_recurrence tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn create_reminder_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_CREATE_REMINDER)
      .expect("create_reminder tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn update_reminder_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_UPDATE_REMINDER)
      .expect("update_reminder tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn lists_create_calendar_tool_when_calendars_create_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.calendars.create".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_CREATE_CALENDAR]);
  }

  #[test]
  fn lists_update_calendar_tool_when_calendars_edit_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.calendars.edit".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_UPDATE_CALENDAR]);
  }

  #[test]
  fn lists_delete_calendar_tool_when_calendars_delete_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.calendars.delete".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_DELETE_CALENDAR]);
  }

  #[test]
  fn lists_events_tool_when_events_read_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_LIST_EVENTS, TOOL_GET_EVENT]);
  }

  #[test]
  fn lists_search_events_tool_when_events_search_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.search".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SEARCH_EVENTS, TOOL_SEARCH_ITEMS]);
  }

  #[test]
  fn lists_create_event_tool_when_events_create_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.create".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_CREATE_EVENT]);
  }

  #[test]
  fn create_event_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_CREATE_EVENT)
      .expect("create_event tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn lists_update_event_tool_when_events_edit_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.edit".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_UPDATE_EVENT, TOOL_MOVE_EVENT]);
  }

  #[test]
  fn lists_delete_event_tool_when_events_delete_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.delete".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_DELETE_EVENT]);
  }

  #[test]
  fn update_event_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_UPDATE_EVENT)
      .expect("update_event tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn lists_calendars_tool_when_calendars_read_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.calendars.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_LIST_CALENDARS]);
  }

  #[test]
  fn lists_read_tools_when_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_LIST_LISTS, TOOL_LIST_REMINDERS, TOOL_GET_REMINDER]);
  }

  #[test]
  fn lists_no_tools_when_capability_empty() {
    assert!(tools_for_capabilities(&[]).is_empty());
  }

  #[test]
  fn lists_search_tool_when_search_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.search".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SEARCH_REMINDERS, TOOL_SEARCH_ITEMS]);
  }

  #[test]
  fn lists_create_tools_when_create_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.create".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_CREATE_REMINDER, TOOL_CREATE_LIST]);
  }

  #[test]
  fn lists_edit_tools_when_edit_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.edit".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_UPDATE_REMINDER, TOOL_MOVE_REMINDER]);
  }

  #[test]
  fn lists_delete_tools_when_delete_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.delete".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_DELETE_REMINDER, TOOL_DELETE_LIST]);
  }

  #[test]
  fn lists_complete_tools_when_complete_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.complete".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_COMPLETE_REMINDER, TOOL_UNCOMPLETE_REMINDER]);
  }

  #[test]
  fn lists_alarms_tool_when_alarms_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.alarms".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SET_REMINDER_ALARMS]);
  }

  #[test]
  fn lists_event_alarms_tool_when_events_alarms_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.alarms".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SET_EVENT_ALARMS]);
  }

  #[test]
  fn lists_recurrence_tool_when_recurrence_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.recurrence".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SET_REMINDER_RECURRENCE]);
  }

  #[test]
  fn lists_event_recurrence_tool_when_events_recurrence_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.recurrence".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SET_EVENT_RECURRENCE]);
  }

  #[test]
  fn lists_invitation_tools_when_events_invitations_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.invitations".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(
      names,
      vec![
        TOOL_ACCEPT_INVITATION,
        TOOL_DECLINE_INVITATION,
        TOOL_TENTATIVE_INVITATION
      ]
    );
  }

  #[test]
  fn lists_contacts_tool_when_contacts_read_capability_enabled() {
    let tools = tools_for_capabilities(&["contacts.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(
      names,
      vec![
        TOOL_LIST_CONTACTS,
        TOOL_LIST_GROUPS,
        TOOL_LIST_CONTAINERS,
        TOOL_GET_CONTACT
      ]
    );
  }

  #[test]
  fn lists_notes_tools_by_capability() {
    let names = |capability: &str| -> Vec<&str> {
      tools_for_capabilities(&[capability.into()])
        .iter()
        .map(|tool| tool.name)
        .collect()
    };
    assert_eq!(
      names("notes.read"),
      vec![
        super::TOOL_NOTES_LIST_FOLDERS,
        super::TOOL_NOTES_LIST_NOTES,
        super::TOOL_NOTES_GET_NOTE,
        super::TOOL_NOTES_GET_ATTACHMENT
      ]
    );
    assert_eq!(
      names("notes.search"),
      vec![super::TOOL_NOTES_SEARCH_NOTES, super::TOOL_SEARCH_ITEMS]
    );
    assert_eq!(
      names("notes.create"),
      vec![super::TOOL_NOTES_CREATE_NOTE, super::TOOL_NOTES_CREATE_FOLDER]
    );
    assert_eq!(
      names("notes.edit"),
      vec![super::TOOL_NOTES_UPDATE_NOTE, super::TOOL_NOTES_MOVE_NOTE]
    );
    assert_eq!(
      names("notes.delete"),
      vec![super::TOOL_NOTES_DELETE_NOTE, super::TOOL_NOTES_DELETE_FOLDER]
    );
  }

  #[test]
  fn notes_schemas_reject_blank_ids_bad_paging_and_folder_xor() {
    use crate::arg_validation::validate_tool_arguments;

    let tool = |name: &str| *resolve_tool(name).expect(name);
    let delete = tool(super::TOOL_NOTES_DELETE_NOTE);
    assert!(validate_tool_arguments(&delete, &serde_json::json!({ "note_identifier": "   " })).is_err());
    assert!(validate_tool_arguments(&delete, &serde_json::json!({})).is_err());
    assert!(
      validate_tool_arguments(
        &delete,
        &serde_json::json!({ "note_identifier": "abc", "note_title": "Abc" })
      )
      .is_err()
    );
    assert!(validate_tool_arguments(&delete, &serde_json::json!({ "note_identifier": "abc" })).is_ok());
    assert!(validate_tool_arguments(&delete, &serde_json::json!({ "note_title": "Abc" })).is_ok());

    let list = tool(super::TOOL_NOTES_LIST_NOTES);
    assert!(validate_tool_arguments(&list, &serde_json::json!({ "limit": 0 })).is_err());
    assert!(validate_tool_arguments(&list, &serde_json::json!({ "limit": 201 })).is_err());
    assert!(validate_tool_arguments(&list, &serde_json::json!({ "offset": -1 })).is_err());
    assert!(validate_tool_arguments(&list, &serde_json::json!({ "limit": 50, "offset": 0 })).is_ok());
    assert!(validate_tool_arguments(&list, &serde_json::json!({ "folder_path": "Work/Clients" })).is_ok());
    assert!(
      validate_tool_arguments(
        &list,
        &serde_json::json!({ "folder_identifier": "fold-1", "folder_path": "Notes" })
      )
      .is_err()
    );

    let update = tool(super::TOOL_NOTES_UPDATE_NOTE);
    assert!(validate_tool_arguments(&update, &serde_json::json!({ "note_identifier": "abc" })).is_err());
    assert!(validate_tool_arguments(&update, &serde_json::json!({ "body": "x" })).is_err());
    assert!(
      validate_tool_arguments(
        &update,
        &serde_json::json!({ "note_identifier": "abc", "body": "<p>x</p>" })
      )
      .is_ok()
    );
    assert!(validate_tool_arguments(&update, &serde_json::json!({ "note_title": "Abc", "body": "x" })).is_ok());

    let folder = tool(super::TOOL_NOTES_CREATE_FOLDER);
    assert!(validate_tool_arguments(&folder, &serde_json::json!({ "name": "Inbox" })).is_err());
    assert!(
      validate_tool_arguments(
        &folder,
        &serde_json::json!({ "name": "Inbox", "account_identifier": "a", "folder_identifier": "b" })
      )
      .is_err()
    );
    assert!(
      validate_tool_arguments(
        &folder,
        &serde_json::json!({ "name": "Inbox", "folder_identifier": "b", "folder_path": "Notes" })
      )
      .is_err()
    );
    assert!(
      validate_tool_arguments(
        &folder,
        &serde_json::json!({ "name": "Inbox", "folder_path": "Work/Clients", "account_identifier": "a" })
      )
      .is_ok()
    );
    assert!(
      validate_tool_arguments(
        &folder,
        &serde_json::json!({ "name": "   ", "account_identifier": "a" })
      )
      .is_err()
    );
    assert!(
      validate_tool_arguments(
        &folder,
        &serde_json::json!({ "name": "Inbox", "account_identifier": "a" })
      )
      .is_ok()
    );
    assert!(
      validate_tool_arguments(
        &folder,
        &serde_json::json!({ "name": "Inbox", "folder_identifier": "parent" })
      )
      .is_ok()
    );

    let attachment = tool(super::TOOL_NOTES_GET_ATTACHMENT);
    assert!(validate_tool_arguments(&attachment, &serde_json::json!({ "attachment_identifier": "att" })).is_ok());
    assert!(
      validate_tool_arguments(
        &attachment,
        &serde_json::json!({ "attachment_identifier": "att", "format": "image" })
      )
      .is_ok()
    );
    assert!(
      validate_tool_arguments(
        &attachment,
        &serde_json::json!({ "attachment_identifier": "att", "format": "binary" })
      )
      .is_err()
    );
    assert!(
      validate_tool_arguments(
        &attachment,
        &serde_json::json!({ "attachment_identifier": "att", "max_characters": 15000, "offset": 0 })
      )
      .is_ok()
    );
    assert!(
      validate_tool_arguments(
        &attachment,
        &serde_json::json!({ "attachment_identifier": "att", "max_characters": 100001 })
      )
      .is_err()
    );
  }

  #[test]
  fn list_groups_schema_allows_optional_container_identifier() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_LIST_GROUPS)
      .expect("list_groups tool");
    let schema = input_schema(tool);

    assert_eq!(schema.get("type").and_then(|value| value.as_str()), Some("object"));
    assert_eq!(
      schema
        .get("properties")
        .and_then(|properties| properties.get("container_identifier"))
        .and_then(|property| property.get("type"))
        .and_then(|value| value.as_str()),
      Some("string")
    );
    assert_eq!(schema.get("required"), None);
  }

  #[test]
  fn get_contact_schema_requires_contact_identifier() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_GET_CONTACT)
      .expect("get_contact tool");
    let schema = input_schema(tool);

    assert_eq!(
      schema.get("required").and_then(|value| value.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|field| field.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec!["contact_identifier".to_owned()])
    );
  }

  #[test]
  fn lists_search_contacts_tool_when_contacts_search_capability_enabled() {
    let tools = tools_for_capabilities(&["contacts.search".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SEARCH_CONTACTS]);
  }

  #[test]
  fn lists_create_contact_tool_when_contacts_create_capability_enabled() {
    let tools = tools_for_capabilities(&["contacts.create".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_CREATE_CONTACT, TOOL_CREATE_GROUP]);
  }

  #[test]
  fn create_group_schema_requires_name_and_allows_optional_container() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_CREATE_GROUP)
      .expect("create_group tool");
    let schema = input_schema(tool);

    assert_eq!(
      schema.get("required").and_then(|value| value.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|field| field.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec!["name".to_owned()])
    );
    assert_eq!(
      string_property_pattern(&schema, "container_identifier").as_deref(),
      Some(r".*\S.*")
    );
    assert_eq!(string_property_pattern(&schema, "name").as_deref(), Some(r".*\S.*"));
  }

  #[test]
  fn lists_update_contact_tool_when_contacts_edit_capability_enabled() {
    let tools = tools_for_capabilities(&["contacts.edit".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(
      names,
      vec![
        TOOL_UPDATE_CONTACT,
        TOOL_LINK_CONTACTS,
        TOOL_UNLINK_CONTACTS,
        TOOL_UPDATE_GROUP
      ]
    );
  }

  #[test]
  fn link_contacts_schema_requires_from_and_to_contact_identifiers() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_LINK_CONTACTS)
      .expect("link_contacts tool");
    let schema = input_schema(tool);

    assert_eq!(
      schema.get("required").and_then(|value| value.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|field| field.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec![
        "from_contact_identifier".to_owned(),
        "to_contact_identifier".to_owned()
      ])
    );
    let properties = schema
      .get("properties")
      .and_then(|value| value.as_object())
      .expect("link_contacts properties");
    assert!(properties.contains_key("from_contact_identifier"));
    assert!(properties.contains_key("to_contact_identifier"));
  }

  #[test]
  fn unlink_contacts_schema_requires_contact_identifier() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_UNLINK_CONTACTS)
      .expect("unlink_contacts tool");
    let schema = input_schema(tool);

    assert_eq!(
      schema.get("required").and_then(|value| value.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|field| field.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec!["contact_identifier".to_owned()])
    );
    let properties = schema
      .get("properties")
      .and_then(|value| value.as_object())
      .expect("unlink_contacts properties");
    assert!(properties.contains_key("contact_identifier"));
  }

  #[test]
  fn update_group_schema_requires_group_identifier_and_allows_optional_name() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_UPDATE_GROUP)
      .expect("update_group tool");
    let schema = input_schema(tool);

    assert_eq!(
      schema.get("required").and_then(|value| value.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|field| field.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec!["group_identifier".to_owned()])
    );
    assert_eq!(
      nullable_property_types(&schema, "name"),
      vec!["string".to_owned(), "null".to_owned()]
    );
    assert_eq!(string_property_pattern(&schema, "name").as_deref(), Some(r".*\S.*"));
    assert_eq!(
      schema.get("additionalProperties").and_then(|value| value.as_bool()),
      Some(false)
    );
  }

  #[test]
  fn lists_delete_contact_and_delete_group_tools_when_contacts_delete_capability_enabled() {
    let tools = tools_for_capabilities(&["contacts.delete".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_DELETE_CONTACT, TOOL_DELETE_GROUP]);
  }

  #[test]
  fn delete_contact_schema_requires_contact_identifier() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_DELETE_CONTACT)
      .expect("delete_contact tool");
    let schema = input_schema(tool);

    assert_eq!(
      schema.get("required").and_then(|value| value.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|field| field.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec!["contact_identifier".to_owned()])
    );
  }

  #[test]
  fn delete_group_schema_requires_group_identifier() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_DELETE_GROUP)
      .expect("delete_group tool");
    let schema = input_schema(tool);

    assert_eq!(
      schema.get("required").and_then(|value| value.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|field| field.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec!["group_identifier".to_owned()])
    );
  }

  #[test]
  fn update_contact_schema_requires_contact_identifier_and_allows_nullable_fields() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_UPDATE_CONTACT)
      .expect("update_contact tool");
    let schema = input_schema(tool);

    assert_eq!(
      schema.get("required").and_then(|value| value.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|field| field.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec!["contact_identifier".to_owned()])
    );
    assert_eq!(
      nullable_property_types(&schema, "note"),
      vec!["string".to_owned(), "null".to_owned()]
    );
    assert_eq!(
      nullable_property_types(&schema, "phone_numbers"),
      vec!["array".to_owned(), "null".to_owned()]
    );
    assert_eq!(
      nullable_property_types(&schema, "birthday"),
      vec!["object".to_owned(), "null".to_owned()]
    );
    let create_schema = input_schema(
      all_tools()
        .iter()
        .find(|tool| tool.name == TOOL_CREATE_CONTACT)
        .expect("create_contact tool"),
    );
    for property in ["birthday", "non_gregorian_birthday"] {
      assert!(
        nullable_date_component_schema_matches_create(&schema, &create_schema, property),
        "{property} must preserve the shared date component schema and only widen type to include null"
      );
    }
    assert_eq!(array_items_type(&schema, "phone_numbers").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "postal_addresses").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "dates").as_deref(), Some("object"));
    let properties = schema
      .get("properties")
      .and_then(|value| value.as_object())
      .expect("update_contact properties");
    assert!(properties.contains_key("image_data"));
    assert!(!properties.contains_key("container_identifier"));
    assert!(!properties.contains_key("thumbnail_image_data"));
  }

  #[test]
  fn create_contact_schema_allows_optional_container_and_requires_a_name_field() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_CREATE_CONTACT)
      .expect("create_contact tool");
    let schema = input_schema(tool);

    assert_eq!(
      schema.get("required").and_then(|value| value.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|field| field.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      None
    );
    assert_eq!(
      property_description(&schema, "given_name"),
      Some("Provide at least one of given_name, family_name, or organization_name.")
    );
    assert!(schema.get("anyOf").is_none());
    assert_eq!(
      string_property_pattern(&schema, "container_identifier").as_deref(),
      Some(r".*\S.*")
    );
    assert_eq!(
      string_property_pattern(&schema, "given_name").as_deref(),
      Some(r".*\S.*")
    );
    assert_eq!(
      string_property_pattern(&schema, "family_name").as_deref(),
      Some(r".*\S.*")
    );
    assert_eq!(
      string_property_pattern(&schema, "organization_name").as_deref(),
      Some(r".*\S.*")
    );
    assert_eq!(array_items_type(&schema, "phone_numbers").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "postal_addresses").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "dates").as_deref(), Some("object"));
    let properties = schema
      .get("properties")
      .and_then(|value| value.as_object())
      .expect("create_contact properties");
    assert!(properties.contains_key("image_data"));
    assert!(!properties.contains_key("thumbnail_image_data"));
    assert_eq!(
      array_item_properties(&schema, "phone_numbers")
        .as_ref()
        .and_then(|properties| properties.get("value"))
        .and_then(|value| value.get("type"))
        .and_then(|value| value.as_str()),
      Some("string")
    );
    for property in [
      "phone_numbers",
      "email_addresses",
      "postal_addresses",
      "url_addresses",
      "contact_relations",
      "social_profiles",
      "instant_message_addresses",
      "dates",
    ] {
      let item_properties =
        array_item_properties(&schema, property).unwrap_or_else(|| panic!("{property} labeled-value item properties"));
      assert!(
        !item_properties.contains_key("identifier"),
        "{property} must not advertise labeled-value identifier on create"
      );
      assert!(item_properties.contains_key("label"));
      assert!(item_properties.contains_key("value"));
    }
  }

  fn nullable_date_component_schema_matches_create(
    update_schema: &serde_json::Value,
    create_schema: &serde_json::Value,
    property: &str,
  ) -> bool {
    let create_property = create_schema
      .get("properties")
      .and_then(|properties| properties.get(property));
    let update_property = update_schema
      .get("properties")
      .and_then(|properties| properties.get(property));
    match (create_property, update_property) {
      (Some(create_property), Some(update_property)) => {
        nullable_property_types(update_schema, property) == vec!["object".to_owned(), "null".to_owned()]
          && update_property.get("properties") == create_property.get("properties")
          && {
            let mut normalized = update_property.clone();
            if let Some(schema) = normalized.as_object_mut() {
              schema.insert("type".to_owned(), serde_json::json!("object"));
            }
            normalized == *create_property
          }
      }
      _ => false,
    }
  }

  fn nullable_property_types(schema: &serde_json::Value, property: &str) -> Vec<String> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("type"))
      .and_then(|value| value.as_array())
      .map(|types| {
        types
          .iter()
          .filter_map(|entry| entry.as_str().map(str::to_owned))
          .collect()
      })
      .unwrap_or_default()
  }

  fn number_property_minimum(schema: &serde_json::Value, property: &str) -> Option<f64> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("minimum"))
      .and_then(|value| value.as_f64())
  }

  fn number_property_maximum(schema: &serde_json::Value, property: &str) -> Option<f64> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("maximum"))
      .and_then(|value| value.as_f64())
  }

  fn number_property_exclusive_minimum(schema: &serde_json::Value, property: &str) -> Option<f64> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("exclusiveMinimum"))
      .and_then(|value| value.as_f64())
  }

  fn string_property_min_length(schema: &serde_json::Value, property: &str) -> Option<u64> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("minLength"))
      .and_then(|value| value.as_u64())
  }

  fn string_property_pattern(schema: &serde_json::Value, property: &str) -> Option<String> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("pattern"))
      .and_then(|value| value.as_str())
      .map(str::to_owned)
  }

  fn array_property_items_enum(schema: &serde_json::Value, property: &str) -> Vec<String> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("items"))
      .and_then(|items_schema| items_schema.get("enum"))
      .and_then(|value| value.as_array())
      .map(|values| {
        values
          .iter()
          .filter_map(|entry| entry.as_str().map(str::to_owned))
          .collect()
      })
      .unwrap_or_default()
  }

  fn property_description<'a>(schema: &'a serde_json::Value, property: &str) -> Option<&'a str> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("description"))
      .and_then(|value| value.as_str())
  }

  #[test]
  fn search_contacts_schema_requires_non_empty_search_strings() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SEARCH_CONTACTS)
      .expect("search_contacts tool");
    let schema = input_schema(tool);

    assert_eq!(string_property_min_length(&schema, "name"), Some(1));
    assert_eq!(string_property_min_length(&schema, "email_address"), Some(1));
    assert_eq!(string_property_min_length(&schema, "phone_number"), Some(1));
    assert_eq!(
      property_description(&schema, "query"),
      Some("Provide at least one of query, name, email_address, or phone_number.")
    );
    assert!(schema.get("anyOf").is_none());
  }

  fn combinator_paths(schema: &serde_json::Value, path: &str, found: &mut Vec<String>) {
    match schema {
      serde_json::Value::Object(object) => {
        for key in ["oneOf", "anyOf", "allOf", "not"] {
          if object.contains_key(key) {
            found.push(format!("{path}.{key}"));
          }
        }
        for (key, value) in object {
          combinator_paths(value, &format!("{path}.{key}"), found);
        }
      }
      serde_json::Value::Array(items) => {
        for (index, item) in items.iter().enumerate() {
          combinator_paths(item, &format!("{path}[{index}]"), found);
        }
      }
      _ => {}
    }
  }

  #[test]
  fn input_schemas_have_no_top_level_combinator() {
    for tool in all_tools() {
      let schema = input_schema(tool);
      for key in ["oneOf", "anyOf", "allOf", "not"] {
        assert!(
          schema.get(key).is_none(),
          "{} inputSchema has top-level {key}",
          tool.name
        );
      }
      let mut nested = Vec::new();
      combinator_paths(&schema, "$", &mut nested);
      assert!(
        nested.is_empty(),
        "{} inputSchema still has combinators: {}",
        tool.name,
        nested.join(", ")
      );
    }
  }

  #[test]
  fn lists_mapkit_search_tools_when_mapkit_search_capability_enabled() {
    let tools = tools_for_capabilities(&["mapkit.search".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SEARCH_PLACES, TOOL_SEARCH_NEARBY]);
  }

  #[test]
  fn lists_geocode_tools_when_mapkit_geocode_capability_enabled() {
    let tools = tools_for_capabilities(&["mapkit.geocode".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_REVERSE_GEOCODE, TOOL_FORWARD_GEOCODE]);
  }

  #[test]
  fn forward_geocode_schema_requires_address() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_FORWARD_GEOCODE)
      .expect("forward_geocode tool");
    let schema = input_schema(tool);
    assert_eq!(
      schema
        .get("required")
        .and_then(|value| value.as_array())
        .map(|items| items.iter().filter_map(|item| item.as_str()).collect::<Vec<_>>()),
      Some(vec!["address"])
    );
    assert!(schema.get("properties").and_then(|p| p.get("address")).is_some());
  }

  #[test]
  fn reverse_geocode_schema_requires_coordinate() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_REVERSE_GEOCODE)
      .expect("reverse_geocode tool");
    let schema = input_schema(tool);
    assert_eq!(
      schema
        .get("required")
        .and_then(|value| value.as_array())
        .map(|items| items.iter().filter_map(|item| item.as_str()).collect::<Vec<_>>()),
      Some(vec!["coordinate"])
    );
    assert!(schema.get("properties").and_then(|p| p.get("coordinate")).is_some());
  }

  #[test]
  fn lists_routing_tools_when_mapkit_routing_capability_enabled() {
    let tools = tools_for_capabilities(&["mapkit.routing".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_CALCULATE_ROUTE, TOOL_ESTIMATE_TRAVEL_TIME]);
  }

  #[test]
  fn lists_get_current_location_tool_when_corelocation_read_capability_enabled() {
    let tools = tools_for_capabilities(&["corelocation.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_GET_CURRENT_LOCATION]);
  }

  #[test]
  fn get_current_location_schema_has_no_required_fields() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_GET_CURRENT_LOCATION)
      .expect("get_current_location tool");
    let schema = input_schema(tool);
    assert_eq!(
      schema
        .get("required")
        .and_then(|value| value.as_array())
        .map(|items| items.iter().filter_map(|item| item.as_str()).collect::<Vec<_>>()),
      None
    );
    assert!(
      schema
        .get("properties")
        .and_then(|value| value.as_object())
        .is_none_or(|properties| properties.is_empty())
    );
  }

  #[test]
  fn lists_get_place_tool_when_mapkit_read_capability_enabled() {
    let tools = tools_for_capabilities(&["mapkit.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_GET_PLACE]);
  }

  #[test]
  fn get_place_schema_requires_identifier() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_GET_PLACE)
      .expect("get_place tool");
    let schema = input_schema(tool);
    assert_eq!(string_property_min_length(&schema, "identifier"), Some(1));
    assert_eq!(
      schema.get("required").and_then(|v| v.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|f| f.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec!["identifier".to_owned()])
    );
  }

  #[test]
  fn lists_open_navigation_tool_when_mapkit_navigation_capability_enabled() {
    let tools = tools_for_capabilities(&["mapkit.navigation".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_OPEN_NAVIGATION]);
  }

  #[test]
  fn calculate_route_schema_requires_source_and_destination() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_CALCULATE_ROUTE)
      .expect("calculate_route tool");
    let schema = input_schema(tool);
    assert_eq!(
      schema
        .get("required")
        .and_then(|value| value.as_array())
        .map(|items| items.iter().filter_map(|item| item.as_str()).collect::<Vec<_>>()),
      Some(vec!["source", "destination"])
    );
    assert!(schema.get("properties").and_then(|p| p.get("source")).is_some());
    assert!(schema.get("properties").and_then(|p| p.get("destination")).is_some());
    assert!(schema.get("properties").and_then(|p| p.get("transport_type")).is_some());
  }

  #[test]
  fn estimate_travel_time_schema_requires_source_and_destination() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_ESTIMATE_TRAVEL_TIME)
      .expect("estimate_travel_time tool");
    let schema = input_schema(tool);
    assert_eq!(
      schema
        .get("required")
        .and_then(|value| value.as_array())
        .map(|items| items.iter().filter_map(|item| item.as_str()).collect::<Vec<_>>()),
      Some(vec!["source", "destination"])
    );
    assert!(schema.get("properties").and_then(|p| p.get("source")).is_some());
    assert!(schema.get("properties").and_then(|p| p.get("destination")).is_some());
    assert!(schema.get("properties").and_then(|p| p.get("transport_type")).is_some());
    assert!(
      schema
        .get("properties")
        .and_then(|p| p.get("requests_alternate_routes"))
        .is_none()
    );
  }

  #[test]
  fn estimate_travel_time_schema_describes_exclusive_dates() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_ESTIMATE_TRAVEL_TIME)
      .expect("estimate_travel_time tool");
    let schema = input_schema(tool);
    assert!(schema.get("oneOf").is_none());
    assert_eq!(
      property_description(&schema, "departure_date"),
      Some("Provide exactly one of departure_date or arrival_date, or neither.")
    );
    assert_eq!(
      property_description(&schema, "arrival_date"),
      Some("Provide exactly one of departure_date or arrival_date, or neither.")
    );
  }

  #[test]
  fn open_navigation_schema_requires_source_and_destination() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_OPEN_NAVIGATION)
      .expect("open_navigation tool");
    let schema = input_schema(tool);
    assert_eq!(
      schema
        .get("required")
        .and_then(|value| value.as_array())
        .map(|items| items.iter().filter_map(|item| item.as_str()).collect::<Vec<_>>()),
      Some(vec!["source", "destination"])
    );
    assert!(schema.get("properties").and_then(|p| p.get("source")).is_some());
    assert!(schema.get("properties").and_then(|p| p.get("destination")).is_some());
    assert!(schema.get("properties").and_then(|p| p.get("transport_type")).is_some());
  }

  #[test]
  fn open_navigation_schema_allows_null_transport_type() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_OPEN_NAVIGATION)
      .expect("open_navigation tool");
    let schema = input_schema(tool);
    let transport_type = schema
      .get("properties")
      .and_then(|properties| properties.get("transport_type"))
      .expect("transport_type property");
    assert_eq!(
      transport_type
        .get("type")
        .and_then(|value| value.as_array())
        .map(|types| {
          types
            .iter()
            .filter_map(|entry| entry.as_str().map(str::to_owned))
            .collect::<Vec<_>>()
        }),
      Some(vec!["string".to_owned(), "null".to_owned()])
    );
    assert!(
      transport_type
        .get("enum")
        .and_then(|value| value.as_array())
        .is_some_and(|values| values.iter().any(|entry| entry.is_null()))
    );
  }

  #[test]
  fn search_nearby_schema_has_region_and_coordinate_properties() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SEARCH_NEARBY)
      .expect("search_nearby tool");
    let schema = input_schema(tool);
    assert!(schema.get("properties").and_then(|p| p.get("region")).is_some());
    assert!(schema.get("properties").and_then(|p| p.get("coordinate")).is_some());
    assert!(
      schema
        .get("properties")
        .and_then(|p| p.get("including_categories"))
        .is_some()
    );
  }

  #[test]
  fn search_places_schema_requires_query() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SEARCH_PLACES)
      .expect("search_places tool");
    let schema = input_schema(tool);
    assert_eq!(string_property_min_length(&schema, "query"), Some(1));
    assert_eq!(
      schema.get("required").and_then(|v| v.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|f| f.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec!["query".to_owned()])
    );
  }

  #[test]
  fn search_places_schema_result_types_match_swift_support() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SEARCH_PLACES)
      .expect("search_places tool");
    let schema = input_schema(tool);
    assert_eq!(
      array_property_items_enum(&schema, "result_types"),
      vec![
        "address".to_owned(),
        "point_of_interest".to_owned(),
        "physical_feature".to_owned()
      ]
    );
  }

  #[test]
  fn lists_diagnostics_tool_when_diagnostics_read_capability_enabled() {
    let tools = tools_for_capabilities(&["diagnostics.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_GET_USAGE_LOG]);
  }

  #[test]
  fn lists_recognize_text_tool_when_vision_text_capability_enabled() {
    let tools = tools_for_capabilities(&["vision.text".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_RECOGNIZE_TEXT]);
  }

  #[test]
  fn recognize_text_accepts_image_data_or_image_path() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_RECOGNIZE_TEXT)
      .expect("recognize_text tool");
    assert_vision_image_alternative(&input_schema(tool));
  }

  #[test]
  fn lists_recognize_documents_tool_when_vision_document_capability_enabled() {
    let tools = tools_for_capabilities(&["vision.document".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_RECOGNIZE_DOCUMENTS]);
  }

  #[test]
  fn recognize_documents_accepts_image_data_or_image_path() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_RECOGNIZE_DOCUMENTS)
      .expect("recognize_documents tool");
    assert_vision_image_alternative(&input_schema(tool));
  }

  #[test]
  fn recognize_documents_schema_requires_non_empty_recognition_languages() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_RECOGNIZE_DOCUMENTS)
      .expect("recognize_documents tool");
    let schema = input_schema(tool);
    let min_length = schema
      .get("properties")
      .and_then(|properties| properties.get("text_recognition_options"))
      .and_then(|options| options.get("properties"))
      .and_then(|properties| properties.get("recognition_languages"))
      .and_then(|languages| languages.get("items"))
      .and_then(|items| items.get("minLength"))
      .and_then(|value| value.as_u64());
    assert_eq!(min_length, Some(1));
  }

  #[test]
  fn recognize_documents_schema_constrains_normalized_region_of_interest() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_RECOGNIZE_DOCUMENTS)
      .expect("recognize_documents tool");
    let schema = input_schema(tool);
    let region = schema
      .get("properties")
      .and_then(|properties| properties.get("region_of_interest"))
      .expect("region_of_interest schema");
    let origin = region
      .get("properties")
      .and_then(|properties| properties.get("origin"))
      .expect("origin schema");
    let size = region
      .get("properties")
      .and_then(|properties| properties.get("size"))
      .expect("size schema");

    assert_eq!(number_property_minimum(origin, "x"), Some(0.0));
    assert_eq!(number_property_maximum(origin, "x"), Some(1.0));
    assert_eq!(number_property_minimum(origin, "y"), Some(0.0));
    assert_eq!(number_property_maximum(origin, "y"), Some(1.0));
    assert_eq!(number_property_exclusive_minimum(size, "width"), Some(0.0));
    assert_eq!(number_property_maximum(size, "width"), Some(1.0));
    assert_eq!(number_property_exclusive_minimum(size, "height"), Some(0.0));
    assert_eq!(number_property_maximum(size, "height"), Some(1.0));
  }

  #[test]
  fn recognize_documents_schema_documents_region_of_interest_fit_constraint() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_RECOGNIZE_DOCUMENTS)
      .expect("recognize_documents tool");
    let schema = input_schema(tool);
    let description = schema
      .get("properties")
      .and_then(|properties| properties.get("region_of_interest"))
      .and_then(|region| region.get("description"))
      .and_then(|value| value.as_str())
      .unwrap_or("");
    assert!(description.contains("origin.x + size.width <= 1"));
    assert!(description.contains("origin.y + size.height <= 1"));
    assert!(!recognize_documents_region_of_interest_fits_normalized_space(
      0.6, 0.2, 0.5, 0.5
    ));
    assert!(recognize_documents_region_of_interest_fits_normalized_space(
      0.1, 0.2, 0.5, 0.6
    ));
  }

  fn recognize_documents_region_of_interest_fits_normalized_space(
    origin_x: f64,
    origin_y: f64,
    width: f64,
    height: f64,
  ) -> bool {
    (0.0..=1.0).contains(&origin_x)
      && (0.0..=1.0).contains(&origin_y)
      && width > 0.0
      && width <= 1.0
      && height > 0.0
      && height <= 1.0
      && origin_x + width <= 1.0
      && origin_y + height <= 1.0
  }

  #[test]
  fn lists_vision_barcode_tools_when_vision_barcodes_capability_enabled() {
    let tools = tools_for_capabilities(&["vision.barcodes".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_DETECT_BARCODES]);
  }

  #[test]
  fn detect_barcodes_accepts_image_data_or_image_path() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_DETECT_BARCODES)
      .expect("detect_barcodes tool");
    assert_vision_image_alternative(&input_schema(tool));
  }

  #[test]
  fn lists_detect_face_landmarks_tool_when_vision_faces_capability_enabled() {
    let tools = tools_for_capabilities(&["vision.faces".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_DETECT_FACE_LANDMARKS]);
  }

  #[test]
  fn detect_face_landmarks_accepts_image_data_or_image_path() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_DETECT_FACE_LANDMARKS)
      .expect("detect_face_landmarks tool");
    assert_vision_image_alternative(&input_schema(tool));
  }

  #[test]
  fn vision_page_schema_starts_at_one() {
    for name in [
      TOOL_RECOGNIZE_TEXT,
      TOOL_RECOGNIZE_DOCUMENTS,
      TOOL_DETECT_BARCODES,
      TOOL_DETECT_FACE_LANDMARKS,
    ] {
      let tool = all_tools().iter().find(|tool| tool.name == name).expect(name);
      let schema = input_schema(tool);
      assert_eq!(
        schema.pointer("/properties/page/type").and_then(|value| value.as_str()),
        Some("integer")
      );
      assert_eq!(
        schema
          .pointer("/properties/page/minimum")
          .and_then(|value| value.as_i64()),
        Some(1)
      );
      assert!(tool.description.contains("PDF"), "{name}");
      assert!(tool.description.contains("page"), "{name}");
      assert!(tool.description.contains("page_out_of_range"), "{name}");
    }
  }

  fn assert_vision_image_alternative(schema: &serde_json::Value) {
    assert_eq!(string_property_min_length(schema, "image_data"), Some(1));
    assert_eq!(string_property_min_length(schema, "image_path"), Some(1));
    assert!(schema.get("oneOf").is_none());
    let required = schema.get("required").and_then(|value| value.as_array());
    assert!(required.is_none_or(|fields| {
      !fields
        .iter()
        .any(|field| field.as_str() == Some("image_data") || field.as_str() == Some("image_path"))
    }));
  }

  #[test]
  fn detect_face_landmarks_schema_constrains_revision_and_region_of_interest() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_DETECT_FACE_LANDMARKS)
      .expect("detect_face_landmarks tool");
    let schema = input_schema(tool);
    let revision_enum = schema
      .pointer("/properties/revision/enum")
      .and_then(|value| value.as_array())
      .expect("revision enum");
    assert_eq!(
      revision_enum
        .iter()
        .filter_map(|value| value.as_i64())
        .collect::<Vec<_>>(),
      vec![1, 2, 3]
    );

    let region_schema = schema
      .pointer("/properties/region_of_interest")
      .expect("region_of_interest schema");
    assert_eq!(
      region_schema
        .pointer("/properties/origin/properties/x/minimum")
        .and_then(|value| value.as_f64()),
      Some(0.0)
    );
    assert_eq!(
      region_schema
        .pointer("/properties/size/properties/width/exclusiveMinimum")
        .and_then(|value| value.as_f64()),
      Some(0.0)
    );
  }
}
