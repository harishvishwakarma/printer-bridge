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
    *EPIJ_Qual 302/Economy: ""
    *EPIJ_Qual 303/Normal: ""
    *EPIJ_Qual 308/Draft: ""
    *EPIJ_Qual 304/Fine: ""
    *EPIJ_Qual 305/Quality: ""
    *EPIJ_Qual 306/High Quality: ""
    *EPIJ_PGEx 0/Off: ""
    *EPIJ_PGEx 1/On: ""
    *Resolution 180x180dpi/180 dpi: ""
    *Resolution 360x360dpi/360 dpi: ""
    *Resolution 720x720dpi/720 dpi: ""
    *PageSize A4/A4: "<</PageSize[595.20 841.80]/ImagingBBox null>>setpagedevice"
    *PageSize A4.NMgn/A4 (Borderless): "<</PageSize[595.20 841.80]/ImagingBBox null>>setpagedevice"
    *PageSize EPKG/10 x 15 cm (4 x 6 in): "<</PageSize[288.00 432.00]/ImagingBBox null>>setpagedevice"
    *PageSize EPKG.NMgn/10 x 15 cm (4 x 6 in) (Borderless): "<</PageSize[288.00 432.00]/ImagingBBox null>>setpagedevice"
    *EPIJ_PSrc 2/Standard: ""
    *EPIJ_PSrc 3/Borderless: ""
    *EPIJ_Bdls 0/Off: ""
    *EPIJ_Bdls 1/On: ""
    *EPIJ_exmg 0/Minimum: ""
    *EPIJ_exmg 2/Standard: ""
    *EPIJ_Size A4/A4: ""
    *EPIJ_Size EPKG/10 x 15 cm (4 x 6 in): ""
    *APPrinterPreset PlainGeneral/General on Plain paper: "
    *EPIJ_Medi 0
    *EPIJ_Ink_ 1
    *EPIJ_Mode 3
    *EPIJ_Qual 303
    *Resolution 360x360dpi
    com.apple.print.preset.graphicsType General
    com.apple.print.preset.quality normal"
    *End
    *APPrinterPreset PlainPhoto/Photo on Plain paper: "
    *EPIJ_Medi 0
    *EPIJ_Ink_ 1
    *EPIJ_Mode 3
    *EPIJ_Qual 304
    *Resolution 720x720dpi
    com.apple.print.preset.graphicsType Photo
    com.apple.print.preset.quality high"
    *End
    *APPrinterPreset GlossyPhoto/Photo on Glossy paper: "
    *EPIJ_Medi 145
    *EPIJ_Ink_ 1
    *EPIJ_Mode 3
    *EPIJ_Qual 306
    *Resolution 720x720dpi
    com.apple.print.preset.graphicsType Photo
    com.apple.print.preset.quality high"
    *End
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
            .init(key: "EPIJ_Qual", displayName: "Print Quality", values: [
                .init(value: "302", isDefault: false),
                .init(value: "303", isDefault: true),
                .init(value: "308", isDefault: false),
                .init(value: "304", isDefault: false),
                .init(value: "305", isDefault: false),
                .init(value: "306", isDefault: false),
            ]),
            .init(key: "Resolution", displayName: "Resolution", values: [
                .init(value: "180x180dpi", isDefault: false),
                .init(value: "360x360dpi", isDefault: true),
                .init(value: "720x720dpi", isDefault: false),
            ]),
            .init(key: "EPIJ_PGEx", displayName: "Thick paper and envelopes", values: [
                .init(value: "0", isDefault: true),
                .init(value: "1", isDefault: false),
            ]),
            .init(key: "ColorModel", displayName: "Color Model", values: [
                .init(value: "RGB", isDefault: true),
                .init(value: "Mono", isDefault: false),
            ]),
            .init(key: "EPIJ_Ink_", displayName: "Grayscale", values: [
                .init(value: "1", isDefault: true),
                .init(value: "0", isDefault: false),
            ]),
        ]
    )
    let attributes = IPPPrinterAttributesSnapshot(
        queueName: "Epson",
        printerURI: "ipp://localhost/printers/Epson",
        attributes: [
            "color-supported": .init(name: "color-supported", valueType: "boolean", rawValue: "true"),
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
    #expect(capabilities.cupsOptions(forIPPKeyword: "card-stock") == [
        "EPIJ_Medi": "12", "MediaType": "12", "EPIJ_PGEx": "1",
    ])
    let glossy = capabilities.choices.first { $0.ippKeyword == "photographic-glossy" }
    #expect(glossy?.photoPresetOptions["EPIJ_Qual"] == "306")
    #expect(glossy?.photoPresetOptions["Resolution"] == "720x720dpi")
    #expect(capabilities.sizes.first { $0.ippKeyword == "iso_a4_210x297mm" }?.cupsOptions["PageSize"] == "A4")
    #expect(capabilities.sizes.first { $0.ippKeyword == "iso_a4_210x297mm" }?.cupsOptions["EPIJ_PSrc"] == "2")
    #expect(capabilities.sizes.first { $0.ippKeyword == "na_index-4x6_4x6in" }?.cupsOptions["PageSize"] == "EPKG.NMgn")
    #expect(capabilities.sizes.first { $0.ippKeyword == "na_index-4x6_4x6in" }?.cupsOptions["EPIJ_PSrc"] == "3")
    #expect(capabilities.sizes.first { $0.ippKeyword == "na_index-4x6_4x6in" }?.cupsOptions["EPIJ_Bdls"] == "1")
    #expect(capabilities.sizes.first { $0.ippKeyword == "na_index-4x6_4x6in" }?.cupsOptions["EPIJ_exmg"] == "2")
    #expect(capabilities.sizes.first { $0.ippKeyword == "na_index-4x6_4x6in" }?.isBorderless == true)

    let output = PrinterMediaCapabilityService().outputCapabilities(
        attributes: attributes,
        inspection: inspection
    )
    #expect(output.generalQualityOptions[4]?["EPIJ_Qual"] == "303")
    #expect(output.generalQualityOptions[4]?["Resolution"] == "360x360dpi")
    #expect(output.generalQualityOptions[5]?["EPIJ_Qual"] == "304")
    #expect(output.generalQualityOptions[5]?["Resolution"] == "720x720dpi")
    #expect(output.generalQualityOptions[3]?["EPIJ_Qual"] == "308")
    #expect(output.generalQualityOptions[3]?["Resolution"] == "180x180dpi")
    #expect(output.photoNormalOptions["EPIJ_Qual"] == "305")
    #expect(output.colorOptions(for: "color") == ["ColorModel": "RGB", "EPIJ_Ink_": "1"])
    #expect(output.colorOptions(for: "monochrome") == ["ColorModel": "Mono", "EPIJ_Ink_": "0"])
}
