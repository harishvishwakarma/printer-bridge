import Foundation
import Testing
@testable import PrinterBridgeCore

@Test
func mediaCapabilitiesTranslateDriverChoicesToStandardIPPKeywords() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PrinterBridgeMediaTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let ppdURL = temporaryDirectory.appendingPathComponent("Epson.ppd")
    try """
    *EPIJ_Medi 0/Plain paper: ""
    *EPIJ_Medi 12/Epson Matte: ""
    *EPIJ_Medi 13/Epson Premium Glossy: ""
    *EPIJ_Medi 145/Photo Paper Glossy: ""
    *MediaType 0/Plain paper: ""
    *MediaType 12/Epson Matte: ""
    *MediaType 13/Epson Premium Glossy: ""
    *MediaType 145/Photo Paper Glossy: ""
    """.write(to: ppdURL, atomically: true, encoding: .utf8)

    let inspection = PrinterQueueInspection(
        summary: .init(name: "Epson", status: "idle", stateDetail: nil, deviceURI: "dnssd://epson"),
        detail: .init(
            rawStatusLine: "printer Epson is idle",
            attributes: ["Interface": ppdURL.path],
            listAttributes: [:],
            flags: []
        ),
        options: [
            .init(key: "EPIJ_Medi", displayName: "Media Type", values: [
                .init(value: "0", isDefault: true),
                .init(value: "12", isDefault: false),
                .init(value: "13", isDefault: false),
                .init(value: "145", isDefault: false),
            ]),
            .init(key: "MediaType", displayName: "MediaType", values: [
                .init(value: "0", isDefault: true),
                .init(value: "12", isDefault: false),
                .init(value: "13", isDefault: false),
                .init(value: "145", isDefault: false),
            ]),
        ]
    )
    let attributes = IPPPrinterAttributesSnapshot(
        queueName: "Epson",
        printerURI: "ipp://localhost/printers/Epson",
        attributes: [
            "media-default": .init(name: "media-default", valueType: "keyword", rawValue: "iso_a4_210x297mm"),
            "media-supported": .init(
                name: "media-supported",
                valueType: "1setOf keyword",
                rawValue: "iso_a4_210x297mm,na_index-4x6_4x6in"
            ),
            "media-col-database": .init(
                name: "media-col-database",
                valueType: "1setOf collection",
                rawValue: "{media-size={x-dimension=21000 y-dimension=29700} media-bottom-margin=300 media-left-margin=300 media-right-margin=300 media-top-margin=300},{media-size={x-dimension=10160 y-dimension=15240} media-bottom-margin=0 media-left-margin=0 media-right-margin=0 media-top-margin=0}"
            ),
        ],
        rawOutput: ""
    )

    let capabilities = PrinterMediaCapabilityService().capabilities(
        attributes: attributes,
        inspection: inspection
    )

    #expect(capabilities.defaultTypeKeyword == "stationery")
    #expect(capabilities.defaultSize?.ippKeyword == "iso_a4_210x297mm")
    #expect(capabilities.sizes.count == 2)
    #expect(capabilities.cupsOptions(forIPPKeyword: "stationery") == [
        "EPIJ_Medi": "0", "MediaType": "0",
    ])
    #expect(capabilities.cupsOptions(forIPPKeyword: "photographic-matte") == [
        "EPIJ_Medi": "12", "MediaType": "12",
    ])
    #expect(capabilities.cupsOptions(forIPPKeyword: "photographic-glossy") == [
        "EPIJ_Medi": "145", "MediaType": "145",
    ])
}
