import AppKit
@testable import AppleBridge
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

enum VisionTestFixtures {
    static let sampleText = "TEST"

    static func sampleTextImageData() throws -> Data {
        let width = 240
        let height = 80
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VisionProviderError.visionError("Failed to create sample image context")
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let attributed = NSAttributedString(string: sampleText, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 24, y: 16)
        CTLineDraw(line, context)

        guard let cgImage = context.makeImage() else {
            throw VisionProviderError.visionError("Failed to render sample image")
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw VisionProviderError.visionError("Failed to create PNG destination")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VisionProviderError.visionError("Failed to finalize sample PNG")
        }
        return data as Data
    }

    /// Pre-archived `VNRecognizedTextObservation` fixture generated from a sample image.
    /// Unit tests load this deterministically instead of invoking live Vision OCR.
    private static let archivedRecognizedTextObservationsBase64 =
        // swiftlint:disable:next line_length
        "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEDgLDBI1O0JGSVJTVGBhYmNkZWZpdXaDiZGSOJaanqKjp6qrr7Kzt7q7v8PEyMvM0NPU2Nvc4OPk51UkbnVsbNINDg8RWk5TLm9iamVjdHNWJGNsYXNzoRCAAoA23xASExQVFhcYGRoOGxwdHh8gISIjJCUmJygpKissLS4vMDExMjM0VHV1aWRTVFJYWmNvbmZpZGVuY2VTQkxZU0JSWFNUUllbdGV4dE9iamVjdHNTVExYU0JSWVl0aW1lUmFuZ2VUdGV4dFNCTFhdVk5PYnNlcnZhdGlvbl8QG1ZORGV0ZWN0ZWRPYmplY3RPYnNlcnZhdGlvbldyZXF1ZXN0U1RMWVdncm91cElkgAUjP993d3laI6EiP4AAACM/mZmZqnkcQCM/33d3eVojoSM/3MzMzdrE9oAUIz4eKsKZmZmagDcjP5mZmap5HECAB4ATIz4eKsKZmZmaEACAAyM/3MzMzdrE9oAA0zYONzg5OlNyZXZUY29kZRADgAQSUlR4dNI8PT4/WiRjbGFzc25hbWVYJGNsYXNzZXNfEBJWTlJlcXVlc3RTcGVjaWZpZXKiQEFfEBJWTlJlcXVlc3RTcGVjaWZpZXJYTlNPYmplY3TSQw5ERVxOUy51dWlkYnl0ZXNPEBCGjB3ZWANI14mubIQGaCRagAbSPD1HSFZOU1VVSUSiR0HTSg0OS05RV05TLmtleXOiTE2ACIAJok9QgAqAEoARVXN0YXJ0WGR1cmF0aW9u00oNDlVaUaRWV1hZgAuADIANgA6kW1xbXIAPgBCAD4AQgBFVZmxhZ3NVdmFsdWVZdGltZXNjYWxlVWVwb2NoEAEQANI8PWdoXE5TRGljdGlvbmFyeaJnQdNKDQ5qb1GkVldYWYALgAyADYAOpFtcW1yAD4AQgA+AEIARVFRFU1TSDQ53Eap4eXp7fH1+f4CBgBWAG4AegCGAJIAngCqALYAwgDOANtOEDoWGh4hYY3JPdXRwdXRfEA9yZXF1ZXN0UmV2aXNpb26AFoAagBnUDoqLjI2Oj5BfEBRDUk91dHB1dEVuY29kaW5nRGF0YV8QJENST3V0cHV0RW5jb2RpbmdVbmNvbXByZXNzZWREYXRhU2l6ZV8QF0NST3V0cHV0RW5jb2RpbmdWZXJzaW9ugBiAFxEBcxACTxCcYnZ4bnMBAACMAAAAyAEAEADy4ANDUk91dHB1dFR5cGVUZXh0AAQA9uZURVNUAgD265qZmZnCKi4+XzrjAArgAuE/JB+yc3d33z/Lv/AvMzPbPzgg9lABd5gQ3z/650Wa2zEzM+8wMCgQGGaYCG5AVlTkgADGABgBngEA8Z61APE4vfCI5AEACAA4AfLjAAABBgAAAAAAAABidngk0jw9k5RfEBNDUkltYWdlUmVhZGVyT3V0cHV0opVBXxATQ1JJbWFnZVJlYWRlck91dHB1dNI8PZeYXxAQVk5SZWNvZ25pemVkVGV4dKKZQV8QEFZOUmVjb2duaXplZFRleHTThA6Fm4eIgByAGoAZ1A6Ki4yNoKGQgBiAHREBcU8QnmJ2eG5xAQAAjgAAAMgBABAA8uADQ1JPdXRwdXRUeXBlVGV4dAADAPbkVEVTAPfrmpmZmcIqLj5fOuMACuAC4T8kH7Jzd3ffP8u/8C8zM9s/OCD2UAF3mBDfP/rnRZrbMTMz7zAwKBAYZpgIbkBWVOSAAMUAGAGeAQDxnrQA8Ti88ApuAvBk5AEACAA4AfLjAAABBgAAAAAAAABidngk04QOhaSHiIAfgBqAGdQOiouMjamhkIAYgCBPEJ5idnhucQEAAI4AAADIAQAQAPLgA0NST3V0cHV0VHlwZVRleHQAAwD25EVTVAD365qZmZnCKi4+XzrjAArgAuE/JB+yc3d33z/Lv/AvMzPbPzgg9lABd5gQ3z/650Wa2zEzM+8wMCgQGGaYCG5AVlTkgADFABgBngEA8Z60APE4vPAKbgLwZOQBAAgAOAHy4wAAAQYAAAAAAAAAYnZ4JNOEDoWsh4iAIoAagBnUDoqLjI2xoZCAGIAjTxCeYnZ4bnEBAACOAAAAyAEAEADy4ANDUk91dHB1dFR5cGVUZXh0AAMA9uRURVQA9+uamZmZwiouPl864wAK4ALhPyQfsnN3d98/y7/wLzMz2z84IPZQAXeYEN8/+udFmtsxMzPvMDAoEBhmmAhuQFZU5IAAxQAYAZ4BAPGetADxOLzwCm4C8GTkAQAIADgB8uMAAAEGAAAAAAAAAGJ2eCTThA6FtIeIgCWAGoAZ1A6Ki4yNuaGQgBiAJk8QnmJ2eG5xAQAAjgAAAMgBABAA8uADQ1JPdXRwdXRUeXBlVGV4dAADAPbkVFNUAPfrmpmZmcIqLj5fOuMACuAC4T8kH7Jzd3ffP8u/8C8zM9s/OCD2UAF3mBDfP/rnRZrbMTMz7zAwKBAYZpgIbkBWVOSAAMUAGAGeAQDxnrQA8Ti88ApuAvBk5AEACAA4AfLjAAABBgAAAAAAAABidngk04QOhbyHiIAogBqAGdQOiouMjcHCkIAYgCkRAW9PEJ1idnhubwEAAI0AAADIAQAQAPLgA0NST3V0cHV0VHlwZVRleHQAAgD2zlRFAPPrmpmZmcIqLj5fOuMACuAC4T8kH7Jzd3ffP8u/8C8zM9s/OCD2UAF3mBDfP/rnRZrbMTMz7zAwKBAYZpgIbkBWVOSAAMQAGAGeAQDxnrMA8Ti78AluAvBk5AEACAA4AfLjAAABBgAAAAAAAABidngk04QOhcWHiIArgBqAGdQOiouMjcrCkIAYgCxPEJ1idnhubwEAAI0AAADIAQAQAPLgA0NST3V0cHV0VHlwZVRleHQAAgD2zlNUAPPrmpmZmcIqLj5fOuMACuAC4T8kH7Jzd3ffP8u/8C8zM9s/OCD2UAF3mBDfP/rnRZrbMTMz7zAwKBAYZpgIbkBWVOSAAMQAGAGeAQDxnrMA8Ti78AluAvBk5AEACAA4AfLjAAABBgAAAAAAAABidngk04QOhc2HiIAugBqAGdQOiouMjdLCkIAYgC9PEJ1idnhubwEAAI0AAADIAQAQAPLgA0NST3V0cHV0VHlwZVRleHQAAgD2zlRTAPPrmpmZmcIqLj5fOuMACuAC4T8kH7Jzd3ffP8u/8C8zM9s/OCD2UAF3mBDfP/rnRZrbMTMz7zAwKBAYZpgIbkBWVOSAAMQAGAGeAQDxnrMA8Ti78AluAvBk5AEACAA4AfLjAAABBgAAAAAAAABidngk04QOhdWHiIAxgBqAGdQOiouMjdrCkIAYgDJPEJ1idnhubwEAAI0AAADIAQAQAPLgA0NST3V0cHV0VHlwZVRleHQAAgD2zkVTAPPrmpmZmcIqLj5fOuMACuAC4T8kH7Jzd3ffP8u/8C8zM9s/OCD2UAF3mBDfP/rnRZrbMTMz7zAwKBAYZpgIbkBWVOSAAMQAGAGeAQDxnrMA8Ti78AluAvBk5AEACAA4AfLjAAABBgAAAAAAAABidngk04QOhd2HiIA0gBqAGdQOiouMjeLCkIAYgDVPEJ1idnhubwEAAI0AAADIAQAQAPLgA0NST3V0cHV0VHlwZVRleHQAAgD2zkVUAPPrmpmZmcIqLj5fOuMACuAC4T8kH7Jzd3ffP8u/8C8zM9s/OCD2UAF3mBDfP/rnRZrbMTMz7zAwKBAYZpgIbkBWVOSAAMQAGAGeAQDxnrMA8Ti78AluAvBk5AEACAA4AfLjAAABBgAAAAAAAABidngk0jw95eZXTlNBcnJheaLlQdI8PejpXxAbVk5SZWNvZ25pemVkVGV4dE9ic2VydmF0aW9uperr7O1BXxAbVk5SZWNvZ25pemVkVGV4dE9ic2VydmF0aW9uXxAWVk5SZWN0YW5nbGVPYnNlcnZhdGlvbl8QG1ZORGV0ZWN0ZWRPYmplY3RPYnNlcnZhdGlvbl1WTk9ic2VydmF0aW9uAAgAEQAaACQAKQAyADcASQBMAFEAUwCOAJQAmQCkAKsArQCvALEA2ADdAOEA7ADwAPQA+AEEAQgBDAEWARsBHwEtAUsBUwFXAV8BYQFqAW8BeAGBAYoBjAGVAZcBoAGiAaQBrQGvAbEBugG8AcMBxwHMAc4B0AHVAdoB5QHuAgMCBgIbAiQCKQI2AkkCSwJQAlcCWgJhAmkCbAJuAnACcwJ1AncCeQJ/AogCjwKUApYCmAKaApwCoQKjAqUCpwKpAqsCsQK3AsECxwLJAssC0ALdAuAC5wLsAu4C8ALyAvQC+QL7Av0C/wMBAwMDCAMNAxgDGgMcAx4DIAMiAyQDJgMoAyoDLAMuAzUDPgNQA1IDVANWA18DdgOdA7cDuQO7A74DwARfBGQEegR9BJMEmASrBK4EwQTIBMoEzATOBNcE2QTbBN4FfwWGBYgFigWMBZUFlwWZBjoGQQZDBkUGRwZQBlIGVAb1BvwG/gcABwIHCwcNBw8HsAe3B7kHuwe9B8YHyAfKB80IbQh0CHYIeAh6CIMIhQiHCScJLgkwCTIJNAk9CT8JQQnhCegJ6gnsCe4J9wn5CfsKmwqiCqQKpgqoCrEKswq1C1ULWgtiC2ULaguIC44LrAvFC+MAAAAAAAACAQAAAAAAAADuAAAAAAAAAAAAAAAAAAAL8Q=="

    /// Pre-encoded `DocumentObservation` fixture from a sample document image.
    private static let archivedDocumentObservationBase64 =
        "eyJkb2N1bWVudCI6eyJyZWdpb24iOnsiYmFyY29kZXMiOltdLCJyZWdpb24iOiJZbkJzYVhOME1ERFVBUUlEQkFVR0J3cFlKSFps" +
        "Y25OcGIyNVpKR0Z5WTJocGRtVnlWQ1IwYjNCWUpHOWlhbVZqZEhNU0FBR0dvRjhRRDA1VFMyVjVaV1JCY21Ob2FYWmxjdEVJQ1ZS" +
        "eWIyOTBnQUdrQ3d3VEZGVWtiblZzYk5NTkRnOFFFUkpXSkdOc1lYTnpYeEFUYTBOU1QzVjBjSFYwVW1WbmFXOXVSR0YwWVY4UUky" +
        "dERVazkxZEhCMWRGSmxaMmx2YmxWdVkyOXRjSEpsYzNObFpFUmhkR0ZUYVhwbGdBT0FBaEZRU2s4UkNldGlkbmd5U2xBQUFPQUhr" +
        "RlFBbkFGUUhqQ2dRcVwvckEyQ3pBQUFBSkNRQUFXXC9BWEkycXFtSVdBazFQVmx2Vmc1dnR5UTNvMmVRcTZjVmdPYkp1ajVNSElP" +
        "N3B1RHk2eUVyV3JobEdBQUFBZ0x1UnFLb3FxRFVxSWhnaEJnMThEZklRUEFRXC93VVwvd0hud0RiOEJYOEJ0OEJhREp3Vlwvd0hI" +
        "d0RcLzhCUDhCVWdxcXBWTVdyQXhMcE1sNDZNSm1VR0RRQXNBRUVWMUtnS3FFaU1DaW9DSWdnaXFBMENLS0NxcUFnS2FCUUZRRkJV" +
        "Q1JoN0FnQUFBRUVRaElqbzk1alNCSlpHODdueno3S0tJbDFIWFJGMzUxZ0J0MzV5bk5cLzdkQmF1c1hhNWVkVkpcL2tBb0E3eVRi" +
        "MTc5Z0JtR21IeVNJY0luZTJ1UjRiMjdmcWxTbFl5WkJ1MDNkVnM1T2JvTHFFZE53NmVaT2U1RVwvVEg2aDBndHBcL3hnUlNwYmlS" +
        "cnZ6UFRlV0RlNlFJaFNpcHdlZU94UmN5Vzc4bmtvVWZwczEyaHZ5bHYyNGFwSVk2VEhUbjJiRnFYZVpNMm96VFVnNjdUNGVnd2xm" +
        "RHhKUkF5d3dQcHVzR3VFaG1nN2NXNVdqT043SStXS21oVzJNdlpSbTl5Tk91RFRQTzJnc1Q1ZWQraGhPWkdrSWMyRnVUUnJhNjUw" +
        "RFwvY2FZbk9oQTVIcHVDakhqVG9SNXJXNHJGcXB6aWRUVDc3THdyXC9IS0htZ3prRlFPOTg4R2draEpDdHNrSlhoTVpxeVp6c0NC" +
        "MCt2b3EyVUxmNnZYZFVDcEtpN0lpMDVJV0NOOEFMYmdjQmVRNzBlNW9WQmlIaGVDMEpMYks4KzdmMzh2MzgyUEtwNnVKbE5iUmhz" +
        "VXJDa3FRUW1tQXdiVmZLS20rdGI2QVZ6QzhUNWdHZTBkeUFJYUJYMHdlQldKR2VFNkRyNHRRZWR2dFBSWFI5cG0zUFUyZDJwK3lI" +
        "SktpXC9GKzdBVDdzUkJ6dzA2ZkRFTjFvXC9Dc2VUNzR3K0VtZWgrZmIwRGNkQ1FyXC9mZmY3NkxyeUZcLzdiXC9mdllhSVZMbDlp" +
        "VlljQUhTNGpVbmxBZmRRclZjbXRuakpVRDdDbVJ2TG9kK0d2YmtiaEJqQU81dWwyV0I3K0xEaU5oZGtaXC81TlMrenFPbGtYdTJO" +
        "ZlVyeGNxa2lBRnpCWGtMWUtHVDBGYUsrUEE5QjNKUWtRb1Rrd3pIV2RuVWRIbWc4TDh1TVFPXC9VSzBYZmNLSDBIeDNJVmNOMGJZ" +
        "aytuWHd6OXNQV2RGK2xaWWlVbk4xRDhjOVdtalVLSkRHc2NUaXA3bXhSY2JMT3FGdlJRR2tleHdoVVY4N3I1dEdxdkNyY0JHV1Ny" +
        "TjZ6T2d3VSs2M0VjMGtrMTlESEVncnc1d1l4OW1mbDNaSkNBQ1Y5ZkxaY3BTSXZDRHZ0aUprUEVcLzJiN2dVTmNrdmdIXC9Ceitn" +
        "clBUK1BBbk9LUllTczNoNEtvNngydEg0eElMcE9DSVg3NzhUTTk5cG5QN1l4UUt5N1BKVmtvenlXNGtNRGxmbG8rT0VhdXRBVk9t" +
        "TXlwS080aUFtVzRIK0tDYVFBRmF0b2pvanY4S2M4OTBBT2pxcjh4blNTS1paeWlhQlh6dlB3Y3lcL3BvZ1BkbkZtTTZ0TUU0eGV2" +
        "TVhpNWMrMm43ODl2QllZdTVYdlwvYzlmbE9uQVpOeUVQcVAxV1lmS3BsUmQybWFRZVZ0elpvYkpHejg4TDArc09LSHBsUDNQcXNh" +
        "TnFEOXFwMHJuNnNrRUlXTnZaQVwvMmxQMlpBN1VoamVGRFRnZ0pSOXBwVFBLTW1yV2JhajJyTFh5dlwvOThcL2xPb1EzSk5sdW94" +
        "UEN6dDhDbDBHWmVGUExmWmo2YlVIQTUza04xV1dnZlhQSEtkalBcL2VlUjZwVGdTcVJcL043aVIxVGhOdEV4eWRcL0xyMmtKNUVs" +
        "ZlhqRVRFTjdCZVJSVHZRYm5aMzBKNkRxVUJMNDhGNGNuSzcyWWkwMXBWa1hmWEU5NFZJaUtxMGZnMVhxVzUxQzVlc01UZ200aHJc" +
        "L0I5aEVuOWFmK3QyWFN2WGlSZUk3MG5XT0Q5QnVvQmtKaGg1cUtTdVwvXC81MmZZWkgwaDJYdit3MG1cL0hUZ1ZKRjdzV0pPK2JW" +
        "WHRQU2k1eGZPZ05mVmRURXhJTG1sZ1BmK0E1d01ZMHNRVVdrWmd1b1JKZkJOazdPQTBqUWJON0ZVT0U2OXpMSDRyUmlEeWdrekVv" +
        "U0ZVbjA5cFJsdlB6V05xczN6YTFLV3RQOVNLZXZ1MlR3aXpoWGoxYXFGRU0wM0VTQkwrd1pONTQwZTlkVmhKXC9xU29Fc3pCajZx" +
        "XC8zZWV1dWcxTmR5Z2RLTFRiZ1U4eTFqeEFOXC8zSEtpNFVlUjJkMjRzQ3NLUDhUOVFPNzI3WnQ5elBTVU1ncnJLR0NkMHdFQ0JK" +
        "Z0J3R1wvcWZIWHlGK2puTVVhcEFlc3VteUdTOGltSitEMXIyd2tlREFXc2dUV29NUkFLRHZNdUtsZ1V6dnZ6XC8rdUpseHVrRUhn" +
        "T0lhMXVLeDQ5NmZ5MzB5WkhnSEFIQ2lEVmI5N2NuYmFlcVBDR0d2cFhLZkI0VDJURjRldHkyRXNhTkZmXC9WUTlaVjBubk1OVU1B" +
        "YjRPRmNBcUk4aDBlQXc4UjZjdDFTVGM2Y2NUSXo2dVREYmtkbWhIaElOUUFBQUFBQUFBQUFBQUQ3Z0VuWVYxZFY1MmJURFBEXC9I" +
        "XC9cL1wvZ1E1REdYMFMyNUhWUG51Z3BXdnh1aCtENkJVSUxaQkloTkg4YW9QTUMrd2d4TWFVSk01WXk0UGFLUXp3R1VSTytvNkhG" +
        "MytoWmtaMVhNNFFQczB2dEVIS21nNTJXWW9ia3R6dG9XZStNOFZrN1BcL0RBY0czUUhCdm02TFpEQlwvZ0VOVmsybVRuaFNsQ2lI" +
        "T2VXUm9rbTg0aXdrZnY3NFFIZ2VQdVB0c29DSWU5dkhmZUZpUFBLK0tyYmwwNGh6RHFWc0V2eG5jaDNsbk9vV0xCelE4NW5ZU1dc" +
        "L2hYVEUyMEkrSEZNODNidlp3VGdTY3lHUm5NV1V6RnpIc1ZZNGp0eE1LUFNEVFhZQW1QNHc1YnpKWGhmNU5sR1ptcm1TcHpDQVQ3" +
        "WTNwT1wvR29uSEZVcUp1RG5SWkM2QlhXXC9mS2VFTDUxZHVSQ1prQ0JCTTM0SFA4WkZOdnJNZytHUERVM3hZOUNXdXIrREttcDdY" +
        "NkdoT25icUJMNE5tNk5WRmhPSjdwOXBwMnE5M3F1SWZFbjFxMGVIMVZ3ZzI5WE94bnBKdHZYc2RGNENsSlpjZ2xWb2RFZG9wR3dK" +
        "bWkrUHljTFVPdVN4bVVwNEsrblc3emJVRlZBcGExWjFMYTdpZDVDbUhNU2EwdnRCUm1jaUFPQ29Fem1qRzRrQXo1NEs1NG9mYjMx" +
        "bnRFVXBoRHZCUktNdzI4XC9GRjBMV1ozV21zSktxc2JjM0luVkVWODVXS0tleVJpQ3d4SGFTUkFcL0w1MUJUSDRWWkUrRTB3Rnpt" +
        "UHBCUm5WVFlydDhjUFwvU3VCcjBDbEp3OXd6dVlQMEdtRjAwTUhESTh2eHdseFwvTEk3V0t4eWVuelFpeHN6czY0VDFEQWw5S1wv" +
        "VE52RVwvS3VCbnB3c0N2c2RIT1NYZWR1cDFlVWZSQXZQeFUxSCtaZ2h0VkRxUGhtYkZVOE1YdWU2Rm1zbkRick5wZzhnTnpZYThr" +
        "XC9YOHB5YUxpbis3YVRwd1JjR3NKaU9ldjdLWTdyXC9JczVvMysrRFpFWm1RUVRtcmVLZDJHb3pSQmRvSzhEdnpaOXNncTNmeVZ0" +
        "c3JNeUlUTW9nUW9PUDZwV1U2SmtReEFUcmdWRWxZN2xnd2JzOTdPenFZYzZadWdHWGdERDNCY2R5V2VYK1REN3cwNmdRUVo1TFhV" +
        "U1ErR1gyWmtDM0tOckxFN2wxSDJcL2psc2x6bm9FTUtVaWsyTUVkR1FLd2s2cUMwajQwZm11QW9sMkdUUEJUNTZ6WWJyTG1DaG16" +
        "d2gyNmFoNkFtZU40SGRLa1RvQ0xSM2c5NDB6WmhaMjUrUlRVZnNFclJCWlwvMWg5ZkxaUFwvVTA4bVU5cm5aMGhNUWE2dGNnY3VB" +
        "OEpsbEVPR1dGT3ZVS2tvS01ta2pOdlN2WVV1Q2wwWWJEaEJ3dlB6SmNGQzJaVzBYS3IxSHQ1WGlVSDFZNHpjazdUanJMaUlUSWhj" +
        "aUtMZG9Ib2NxWlA2Tk9oU1JsRHVIZXF3VHhwSW9Qbm9CNXZSeU5PUk8zUURMd0JsNlVVUWhOU01IRFBranhMNGNNOGEwM3NiVlFG" +
        "WU8xQ2hheWVucExsSEFTWlA2WElxYzZweW9sT25vQTRQbEVqS3pLMEdwd1VFYlpVdkFiREVKWHlkK0ZRWXlBaEtqcUJjQ05MQnhV" +
        "SytFS2NXMVdzOG9EQTA5U05LbVdJNFBSTWlrRjdHSktBMUtzdHFuamtLeFdleDF5WGxpZG5nazBoVVdGeGhhSkdOc1lYTnpibUZ0" +
        "WlZna1kyeGhjM05sYzE4UUZrTlNSRzlqZFcxbGJuUlBkWFJ3ZFhSU1pXZHBiMjZqR1JvYlh4QVdRMUpFYjJOMWJXVnVkRTkxZEhC" +
        "MWRGSmxaMmx2Ymw1RFVrOTFkSEIxZEZKbFoybHZibGhPVTA5aWFtVmpkQUFJQUJFQUdnQWtBQ2tBTWdBM0FFa0FUQUJSQUZNQVdB" +
        "QmVBR1VBYkFDQ0FLZ0FxZ0NzQUs4S25ncWpDcTRLdHdyUUN0UUs3UXI4QUFBQUFBQUFBZ0VBQUFBQUFBQUFIQUFBQUFBQUFBQUFB" +
        "QUFBQUFBQUN3VT0ifX0sIm9ic2VydmF0aW9uIjp7ImNvbmZpZGVuY2UiOjAsInRpbWVSYW5nZSI6eyJzdGFydCI6e30sImVuZCI6" +
        "e319LCJyZXF1ZXN0RGVzY3JpcHRvciI6eyJyZWNvZ25pemVEb2N1bWVudHNSZXF1ZXN0Ijp7Il8wIjp7InJldmlzaW9uMSI6e319" +
        "fX0sInV1aWQiOiJFNTJDRENBRS1COUU2LTQ1OTUtQjlDOC1BNTgwQzMyRTA3MUIifX0="

    @MainActor
    static func sampleDocumentObservations() throws -> [DocumentObservation] {
        guard let archivedData = Data(base64Encoded: archivedDocumentObservationBase64) else {
            throw VisionProviderError.serializationFailed
        }
        let observation = try JSONDecoder().decode(DocumentObservation.self, from: archivedData)
        return [observation]
    }

    @MainActor
    static func sampleRecognizedTextObservations() throws -> [VNRecognizedTextObservation] {
        guard let archivedData = Data(base64Encoded: archivedRecognizedTextObservationsBase64) else {
            throw VisionProviderError.serializationFailed
        }
        guard let observations = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(archivedData)
            as? [VNRecognizedTextObservation],
            observations.isEmpty == false
        else {
            throw VisionProviderError.serializationFailed
        }
        return observations
    }
}
