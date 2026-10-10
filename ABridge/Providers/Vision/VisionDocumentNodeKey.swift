import Vision

/// Identity of a document list or table as it appears on the page: its region plus its text.
///
/// Vision can report a list item's or table cell's content as containing the enclosing list or table
/// again, an endless self-similar chain, and it builds a fresh value on every read, so the values
/// themselves never compare equal. Serialization writes each node once per path and stops when a
/// node repeats one that is still open above it.
struct VisionDocumentNodeKey: Equatable {
    let boundingBox: NormalizedRect
    let text: [String]

    init(_ list: DocumentObservation.Container.List) {
        boundingBox = list.boundingRegion.boundingBox
        text = list.items.map(\.itemString)
    }

    init(_ table: DocumentObservation.Container.Table) {
        boundingBox = table.boundingRegion.boundingBox
        text = table.rows.flatMap { row in row.map(\.content.text.transcript) }
    }
}
