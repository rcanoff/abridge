<br/>
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="icon/mark-dark.png">
    <img src="icon/mark.png" width="200px" alt="ABridge"></img>
  </picture>
</p>

<h1 align="center">ABridge</h1>

<p align="center">
  <strong>Apple frameworks on your Mac, one local MCP endpoint.</strong><br/>
  Reminders, Calendar, Contacts, Maps, Location, Vision, and Notes for AI agents.
</p>

<p align="center">
  <a href="https://github.com/rcanoff/abridge/releases">Download</a> ·
  <a href="#connect-your-mcp-client">Connect</a> ·
  <a href="#mcp-tools">Tools</a> ·
  <a href="CONTRIBUTING.md">Build</a>
</p>

<p align="center">
  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/settings-mcp-dark.png"><img src="docs/screenshots/settings-mcp.png" width="32%" alt="MCP settings: server status, endpoint, and bearer token"></picture>
  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/settings-permissions-dark.png"><img src="docs/screenshots/settings-permissions.png" width="32%" alt="Permissions settings: per-provider macOS access, including Notes, and MCP toggles"></picture>
  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/settings-diagnostics-dark.png"><img src="docs/screenshots/settings-diagnostics.png" width="32%" alt="Diagnostics settings: recent tool usage events"></picture>
</p>

ABridge is a macOS menu bar app that serves your Apple data to MCP clients on `127.0.0.1`. Apple stays the system of record: ABridge keeps no database of its own, and every read and write goes through Apple's frameworks or, for Notes, the Notes app itself.

- **Local only.** Binds to loopback and requires a bearer token.
- **You choose what agents see.** Each provider needs its macOS privacy permission, then a per-capability toggle in Settings. Only enabled capabilities appear in `tools/list`. Reminder lists and calendars can be limited to a subset.
- **Built for agents.** Compact summaries for choosing an item, full detail for acting on it, rich text as Markdown, fuzzy search with match excerpts, and files as MCP content items instead of base64.

## Install

Requires macOS 26 or later on Apple silicon.

```sh
brew install --cask rcanoff/tap/abridge
```

Or download `ABridge-<version>.dmg` from [Releases](https://github.com/rcanoff/abridge/releases) and drag ABridge to Applications. Builds are Developer ID signed and notarized, and update themselves through Sparkle (**Check for Updates…** in the menu bar).

## Connect your MCP client

|Setting|Value|
|---|---|
|Endpoint|`http://127.0.0.1:3020/mcp` (port configurable in Settings)|
|Auth|`Authorization: Bearer <token>` (copy the token from the menu bar)|

ABridge must be running before the client connects. For Claude Code:

```sh
claude mcp add --transport http abridge http://127.0.0.1:3020/mcp \
  --header "Authorization: Bearer <token>"
```

## MCP tools

|Provider|What agents can do|
|---|---|
|**Reminders** (EventKit)|List, search, create, update, move, complete, and delete reminders and lists; set alarms and recurrence|
|**Calendar** (EventKit)|List, search, create, update, move, and delete events and calendars; edit one occurrence or the rest of a series; set alarms and recurrence|
|**Contacts**|List, search, create, update, link, and delete contacts and groups|
|**MapKit**|Search places, geocode, calculate routes and travel times, open navigation in Maps|
|**Core Location**|Get this Mac's current location|
|**Vision**|Recognize text and documents, detect barcodes and face landmarks in an image or PDF page|
|**Notes**|Browse folders, read notes as Markdown, read attachments (text, image, or original file), search note and attachment text, create, update, move, and delete notes and folders|
|**Cross-provider**|`abridge_search_items` searches notes, reminders, and events in one call|
|**Diagnostics**|Read the local usage log|

Names follow `<provider>_<domain>_<operation>` (`eventkit_reminders_create_reminder`), or `<provider>_<operation>` when the provider has no domain (`mapkit_search_places`). Each tool's description in `tools/list` documents its arguments, errors, and response fields.

<details>
<summary><strong>All tools</strong></summary>

|Provider|Tools|
|---|---|
|Reminders|`eventkit_reminders_list_lists`, `eventkit_reminders_create_list`, `eventkit_reminders_delete_list`, `eventkit_reminders_list_reminders`, `eventkit_reminders_search_reminders`, `eventkit_reminders_get_reminder`, `eventkit_reminders_create_reminder`, `eventkit_reminders_update_reminder`, `eventkit_reminders_delete_reminder`, `eventkit_reminders_move_reminder`, `eventkit_reminders_complete_reminder`, `eventkit_reminders_uncomplete_reminder`, `eventkit_reminders_set_reminder_alarms`, `eventkit_reminders_set_reminder_recurrence`|
|Calendar|`eventkit_calendars_list_calendars`, `eventkit_calendars_create_calendar`, `eventkit_calendars_update_calendar`, `eventkit_calendars_delete_calendar`, `eventkit_events_list_events`, `eventkit_events_search_events`, `eventkit_events_get_event`, `eventkit_events_create_event`, `eventkit_events_update_event`, `eventkit_events_delete_event`, `eventkit_events_move_event`, `eventkit_events_set_event_alarms`, `eventkit_events_set_event_recurrence`|
|Contacts|`contacts_list_contacts`, `contacts_list_containers`, `contacts_search_contacts`, `contacts_get_contact`, `contacts_create_contact`, `contacts_update_contact`, `contacts_delete_contact`, `contacts_link_contacts`, `contacts_unlink_contacts`, `contacts_list_groups`, `contacts_create_group`, `contacts_update_group`, `contacts_delete_group`|
|MapKit|`mapkit_search_places`, `mapkit_search_nearby`, `mapkit_reverse_geocode`, `mapkit_forward_geocode`, `mapkit_calculate_route`, `mapkit_estimate_travel_time`, `mapkit_open_navigation`, `mapkit_get_place`|
|Core Location|`corelocation_get_current_location`|
|Vision|`vision_recognize_text`, `vision_recognize_documents`, `vision_detect_barcodes`, `vision_detect_face_landmarks`|
|Notes|`notes_list_folders`, `notes_list_notes`, `notes_get_note`, `notes_get_attachment`, `notes_search_notes`, `notes_create_note`, `notes_update_note`, `notes_move_note`, `notes_delete_note`, `notes_create_folder`, `notes_delete_folder`|
|Cross-provider|`abridge_search_items`|
|Diagnostics|`diagnostics_get_usage_log`|

</details>

### Search syntax

Notes, reminders, events, contacts, and `abridge_search_items` share one fuzzy query syntax. Matching is case- and accent-insensitive (`acao` matches `ação`), and hits come back best first with `score` and excerpts marking the match with `«»`.

|Query|Matches|
|---|---|
|`buy milk`|Both words, in any order|
|`"buy milk"`|The exact phrase|
|`'milk`|An exact substring of one word|
|`^mil` / `ilk$`|A word starting or ending with the term|
|`!milk`|Items without the term|
|`milk \| bread`|Either term|

MapKit uses Apple's own query syntax. Core Location and Vision take no query.

### Notes

Apple Notes has no public framework, so ABridge reads its database (`NoteStore.sqlite`) read-only and makes every change through Notes' scripting interface, so Notes owns the edit and iCloud sync. Reads need **Full Disk Access**; writes also need **Automation** access to Notes. Settings → Permissions shows both.

Deleting a note moves it to Recently Deleted; ABridge never erases notes. `notes_update_note` refuses, and changes nothing, when replacing the body would drop a checklist, a file, or a locked note's content.

### Not supported

Invitation RSVP, LocalAuthentication, AVFoundation, CoreBluetooth, HealthKit, PhotoKit, UserNotifications, HomeKit, MusicKit, and Shortcuts.

Response shapes, time zones, paging, and binary limits are specified in [docs/conventions.md](docs/conventions.md#json-and-payloads).

## Contributing

Building from source, the project layout, and development commands are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

Report vulnerabilities privately. See [SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE.md).
