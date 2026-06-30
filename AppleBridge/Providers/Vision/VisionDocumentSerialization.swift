import Foundation
import Vision

enum VisionDocumentSerialization {
    static func scanDocumentResponseJSONObject(
        observations: [DocumentObservation],
        segmentation: DetectedDocumentObservation?,
        maximumCandidateCount: Int
    ) -> [String: Any] {
        [
            "results": observations.map {
                documentObservationJSONObject(from: $0, maximumCandidateCount: maximumCandidateCount)
            },
            "segmentation": segmentation.map(
                VisionDocumentObservationSerialization.detectedDocumentObservationJSONObject(from:)
            ) ?? NSNull(),
        ]
    }

    static func documentObservationJSONObject(
        from observation: DocumentObservation,
        maximumCandidateCount: Int
    ) -> [String: Any] {
        [
            "uuid": observation.uuid.uuidString,
            "confidence": observation.confidence,
            "time_range": VisionSerialization.cmTimeRangeJSONObject(from: observation.timeRange),
            "originating_request_descriptor": VisionDocumentObservationSerialization.requestDescriptorJSONObject(
                from: observation.originatingRequestDescriptor
            ),
            "document": documentContainerJSONObject(
                from: observation.document,
                maximumCandidateCount: maximumCandidateCount
            ),
        ]
    }

    private static func documentContainerJSONObject(
        from container: DocumentObservation.Container,
        maximumCandidateCount: Int
    ) -> [String: Any] {
        [
            "title": container.title.map {
                documentTextJSONObject(from: $0, maximumCandidateCount: maximumCandidateCount)
            } ?? NSNull(),
            "text": documentTextJSONObject(from: container.text, maximumCandidateCount: maximumCandidateCount),
            "paragraphs": container.paragraphs.map {
                documentTextJSONObject(from: $0, maximumCandidateCount: maximumCandidateCount)
            },
            "tables": container.tables.map {
                documentTableJSONObject(from: $0, maximumCandidateCount: maximumCandidateCount)
            },
            "lists": container.lists.map {
                documentListJSONObject(from: $0, maximumCandidateCount: maximumCandidateCount)
            },
            "barcodes": container.barcodes.map { observation in
                VisionDocumentObservationSerialization.barcodeObservationJSONObject(
                    from: observation,
                    boundingRegion: VisionDocumentObservationSerialization.normalizedRegionJSONObject(
                        from: observation.boundingRegion
                    )
                )
            },
            "bounding_region": VisionDocumentObservationSerialization.normalizedRegionJSONObject(
                from: container.boundingRegion
            ),
        ]
    }

    private static func documentTextJSONObject(
        from text: DocumentObservation.Container.Text,
        maximumCandidateCount: Int
    ) -> [String: Any] {
        let boundingRegion = VisionDocumentObservationSerialization.normalizedRegionJSONObject(
            from: text.boundingRegion
        )
        return [
            "transcript": text.transcript,
            "text_alignment": textAlignmentString(from: text.textAlignment) ?? NSNull(),
            "detected_data": text.detectedData.map {
                VisionDocumentDataDetectorSerialization.matchJSONObject(
                    from: $0,
                    transcript: text.transcript,
                    boundingRegion: VisionDocumentObservationSerialization.normalizedRegionJSONObject(
                        from: $0.boundingRegion
                    )
                )
            },
            "lines": text.lines.map {
                VisionDocumentObservationSerialization.recognizedTextObservationJSONObject(
                    from: $0,
                    maximumCandidateCount: maximumCandidateCount,
                    boundingRegion: VisionDocumentObservationSerialization.normalizedRegionJSONObject(
                        from: $0.boundingRegion
                    )
                )
            },
            "words": text.words?.map {
                VisionDocumentObservationSerialization.recognizedTextObservationJSONObject(
                    from: $0,
                    maximumCandidateCount: maximumCandidateCount,
                    boundingRegion: VisionDocumentObservationSerialization.normalizedRegionJSONObject(
                        from: $0.boundingRegion
                    )
                )
            } ?? NSNull(),
            "bounding_region": boundingRegion,
        ]
    }

    private static func documentTableJSONObject(
        from table: DocumentObservation.Container.Table,
        maximumCandidateCount: Int
    ) -> [String: Any] {
        [
            "rows": table.rows.map { row in
                row.map { documentTableCellJSONObject(from: $0, maximumCandidateCount: maximumCandidateCount) }
            },
            "columns": table.columns.map { column in
                column.map { documentTableCellJSONObject(from: $0, maximumCandidateCount: maximumCandidateCount) }
            },
            "bounding_region": VisionDocumentObservationSerialization.normalizedRegionJSONObject(
                from: table.boundingRegion
            ),
        ]
    }

    private static func documentTableCellJSONObject(
        from cell: DocumentObservation.Container.Table.Cell,
        maximumCandidateCount: Int
    ) -> [String: Any] {
        [
            "content": documentContainerJSONObject(from: cell.content, maximumCandidateCount: maximumCandidateCount),
            "row_range": closedRangeJSONObject(from: cell.rowRange),
            "column_range": closedRangeJSONObject(from: cell.columnRange),
        ]
    }

    private static func documentListJSONObject(
        from list: DocumentObservation.Container.List,
        maximumCandidateCount: Int
    ) -> [String: Any] {
        [
            "items": list.items.map {
                documentListItemJSONObject(from: $0, maximumCandidateCount: maximumCandidateCount)
            },
            "bounding_region": VisionDocumentObservationSerialization.normalizedRegionJSONObject(
                from: list.boundingRegion
            ),
        ]
    }

    private static func documentListItemJSONObject(
        from item: DocumentObservation.Container.List.Item,
        maximumCandidateCount: Int
    ) -> [String: Any] {
        [
            "content": documentContainerJSONObject(from: item.content, maximumCandidateCount: maximumCandidateCount),
            "marker_type": listMarkerString(from: item.markerType) ?? NSNull(),
            "marker_string": item.markerString,
            "item_string": item.itemString,
        ]
    }

    private static func closedRangeJSONObject(from range: ClosedRange<Int>) -> [String: Any] {
        [
            "lower": range.lowerBound,
            "upper": range.upperBound,
        ]
    }

    private static func textAlignmentString(
        from alignment: DocumentObservation.Container.Text.Alignment?
    ) -> String? {
        switch alignment {
        case .center: "center"
        case .leading: "leading"
        case .trailing: "trailing"
        case nil: nil
        @unknown default: nil
        }
    }

    private static func listMarkerString(from marker: DocumentObservation.Container.List.Marker?) -> String? {
        switch marker {
        case .bullet: "bullet"
        case .hyphen: "hyphen"
        case .lowercaseLatin: "lowercase_latin"
        case .uppercaseLatin: "uppercase_latin"
        case .decimal: "decimal"
        case .decorativeDecimal: "decorative_decimal"
        case .compositeDecimal: "composite_decimal"
        case nil: nil
        @unknown default: nil
        }
    }
}
