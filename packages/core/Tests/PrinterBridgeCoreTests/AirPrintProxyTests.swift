import Foundation
import CoreGraphics
import PDFKit
import Testing
@testable import PrinterBridgeCore

@Test
func ippRequestParserSeparatesDocumentDataFromAttributes() throws {
    var message = Data([0x01, 0x01])
    message.append(contentsOf: [0x00, 0x02]) // Print-Job
    message.append(contentsOf: [0x00, 0x00, 0x00, 0x2A]) // request-id
    message.append(0x01) // operation-attributes-tag

    appendAttribute(tag: 0x47, name: "attributes-charset", value: "utf-8", to: &message)
    appendAttribute(tag: 0x48, name: "attributes-natural-language", value: "en", to: &message)
    appendAttribute(tag: 0x42, name: "job-name", value: "Notes Print", to: &message)
    appendAttribute(tag: 0x49, name: "document-format", value: "application/pdf", to: &message)
    message.append(0x03) // end-of-attributes-tag
    message.append(Data("PDF-DATA".utf8))

    let request = try IPPRequestParser.parse(message)

    #expect(request.operationID == .printJob)
    #expect(request.requestID == 42)
    #expect(request.firstStringValue(named: "job-name") == "Notes Print")
    #expect(request.firstStringValue(named: "document-format") == "application/pdf")
    #expect(String(data: request.documentData, encoding: .utf8) == "PDF-DATA")
}

@Test
func printJobValidatorRejectsUnsupportedFormatAndMedia() throws {
    let media = PrinterMediaCapabilities(
        choices: [
            .init(ippKeyword: "stationery", displayName: "Plain Paper", cupsOptions: [:]),
        ],
        defaultTypeKeyword: "stationery",
        sizes: [
            .init(ippKeyword: "iso_a4_210x297mm", xDimension: 21000, yDimension: 29700),
        ],
        defaultSize: nil
    )
    let output = PrinterOutputCapabilities(
        supportsColor: true,
        supportsMonochrome: true,
        generalQualityOptions: [:],
        photoNormalOptions: [:]
    )

    var unsupportedFormat = Data([0x02, 0x00])
    unsupportedFormat.append(contentsOf: [0x00, 0x04])
    unsupportedFormat.append(contentsOf: [0x00, 0x00, 0x00, 0x20])
    unsupportedFormat.append(0x01)
    appendAttribute(tag: 0x49, name: "document-format", value: "application/postscript", to: &unsupportedFormat)
    unsupportedFormat.append(0x03)
    let formatRequest = try IPPRequestParser.parse(unsupportedFormat)

    #expect(PrintJobValidator.validationError(
        request: formatRequest,
        media: media,
        output: output,
        documentFormats: ["application/pdf", "image/jpeg"]
    ) == .clientErrorDocumentFormatNotSupported)

    var unsupportedMedia = Data([0x02, 0x00])
    unsupportedMedia.append(contentsOf: [0x00, 0x04])
    unsupportedMedia.append(contentsOf: [0x00, 0x00, 0x00, 0x21])
    unsupportedMedia.append(0x02)
    appendAttribute(tag: 0x44, name: "media", value: "iso_a3_297x420mm", to: &unsupportedMedia)
    unsupportedMedia.append(0x03)
    let mediaRequest = try IPPRequestParser.parse(unsupportedMedia)

    #expect(PrintJobValidator.validationError(
        request: mediaRequest,
        media: media,
        output: output,
        documentFormats: ["application/pdf", "image/jpeg"]
    ) == .clientErrorAttributesOrValuesNotSupported)
}

@Test
func ippRequestParserDecodesMediaCollection() throws {
    var message = Data([0x02, 0x00])
    message.append(contentsOf: [0x00, 0x02]) // Print-Job
    message.append(contentsOf: [0x00, 0x00, 0x00, 0x2B])
    message.append(0x02) // job-attributes-tag
    appendCollectionStart(name: "media-col", to: &message)
    appendCollectionMemberName("media-type", to: &message)
    appendCollectionString(tag: 0x44, value: "photographic-glossy", to: &message)
    appendCollectionMemberName("media-size", to: &message)
    appendCollectionStart(name: nil, to: &message)
    appendCollectionMemberName("x-dimension", to: &message)
    appendCollectionInteger(10160, to: &message)
    appendCollectionMemberName("y-dimension", to: &message)
    appendCollectionInteger(15240, to: &message)
    appendCollectionEnd(to: &message)
    for margin in ["media-bottom-margin", "media-left-margin", "media-right-margin", "media-top-margin"] {
        appendCollectionMemberName(margin, to: &message)
        appendCollectionInteger(0, to: &message)
    }
    appendCollectionEnd(to: &message)
    appendAttribute(tag: 0x44, name: "print-color-mode", value: "monochrome", to: &message)
    appendIntegerAttribute(name: "print-quality", value: 5, to: &message)
    appendIntegerAttribute(name: "copies", value: 2, to: &message)
    appendIntegerAttribute(name: "orientation-requested", value: 4, to: &message)
    appendAttribute(tag: 0x44, name: "print-scaling", value: "fill", to: &message)
    message.append(0x03)
    message.append(Data("PHOTO".utf8))

    let request = try IPPRequestParser.parse(message)
    let media = request.firstCollectionValue(named: "media-col")
    let size = media?.firstCollectionValue(named: "media-size")

    #expect(media?.firstStringValue(named: "media-type") == "photographic-glossy")
    #expect(size?.firstIntegerValue(named: "x-dimension") == 10160)
    #expect(size?.firstIntegerValue(named: "y-dimension") == 15240)

    let options = PrintJobOptionResolver.resolve(
        request: request,
        media: PrinterMediaCapabilities(
            choices: [
                .init(
                    ippKeyword: "photographic-glossy",
                    displayName: "Photo Paper Glossy",
                    cupsOptions: ["EPIJ_Medi": "145", "MediaType": "145"],
                    photoPresetOptions: [
                        "EPIJ_Medi": "145", "EPIJ_Ink_": "1", "EPIJ_Mode": "3",
                        "EPIJ_Qual": "306", "Resolution": "720x720dpi",
                    ],
                    isPhotoMedia: true
                ),
            ],
            defaultTypeKeyword: "stationery",
            sizes: [
                .init(
                    ippKeyword: "na_index-4x6_4x6in",
                    xDimension: 10160,
                    yDimension: 15240,
                    cupsOptions: [
                        "PageSize": "EPKG.NMgn", "EPIJ_Size": "EPKG",
                        "EPIJ_Bdls": "1", "EPIJ_exmg": "2", "EPIJ_PSrc": "3",
                    ],
                    isBorderless: true
                ),
            ],
            defaultSize: nil
        ),
        output: PrinterOutputCapabilities(
            supportsColor: true,
            supportsMonochrome: true,
            generalQualityOptions: [:],
            photoNormalOptions: [:],
            colorModeOptions: [
                "color": ["ColorModel": "RGB", "EPIJ_Ink_": "1"],
                "monochrome": ["ColorModel": "Mono", "EPIJ_Ink_": "0"],
            ]
        )
    )

    #expect(options.cupsOptions == [
        "ColorModel": "Mono",
        "EPIJ_Bdls": "1",
        "EPIJ_Ink_": "0",
        "EPIJ_Medi": "145",
        "EPIJ_Mode": "3",
        "EPIJ_PSrc": "3",
        "EPIJ_Qual": "306",
        "EPIJ_Size": "EPKG",
        "EPIJ_exmg": "2",
        "MediaType": "145",
        "PageSize": "EPKG.NMgn",
        "Resolution": "720x720dpi",
        "orientation-requested": "4",
        "print-scaling": "fill",
    ])
    #expect(options.copies == 2)
    #expect(options.fillsBorderlessPhotoMedia)
}

@Test
func resolverMapsPlainA4MonochromeNormalToEpsonDriverOptions() throws {
    var message = Data([0x02, 0x00])
    message.append(contentsOf: [0x00, 0x02])
    message.append(contentsOf: [0x00, 0x00, 0x00, 0x2C])
    message.append(0x02)
    appendAttribute(tag: 0x44, name: "media", value: "iso_a4_210x297mm", to: &message)
    appendAttribute(tag: 0x44, name: "media-type", value: "stationery", to: &message)
    appendAttribute(tag: 0x44, name: "print-color-mode", value: "monochrome", to: &message)
    appendIntegerAttribute(name: "print-quality", value: 4, to: &message)
    message.append(0x03)
    message.append(Data("A4-DOCUMENT".utf8))

    let request = try IPPRequestParser.parse(message)
    let options = PrintJobOptionResolver.resolve(
        request: request,
        media: PrinterMediaCapabilities(
            choices: [
                .init(
                    ippKeyword: "stationery",
                    displayName: "Plain Paper",
                    cupsOptions: ["EPIJ_Medi": "0", "MediaType": "0"]
                ),
            ],
            defaultTypeKeyword: "stationery",
            sizes: [
                .init(
                    ippKeyword: "iso_a4_210x297mm",
                    xDimension: 21000,
                    yDimension: 29700,
                    cupsOptions: ["PageSize": "A4", "EPIJ_Size": "A4", "EPIJ_Bdls": "0"]
                ),
            ],
            defaultSize: nil
        ),
        output: PrinterOutputCapabilities(
            supportsColor: true,
            supportsMonochrome: true,
            generalQualityOptions: [
                4: ["EPIJ_Mode": "3", "EPIJ_Qual": "303", "Resolution": "360x360dpi"],
            ],
            photoNormalOptions: [:],
            colorModeOptions: [
                "color": ["ColorModel": "RGB", "EPIJ_Ink_": "1"],
                "monochrome": ["ColorModel": "Mono", "EPIJ_Ink_": "0"],
            ]
        )
    )

    #expect(options.cupsOptions == [
        "ColorModel": "Mono",
        "EPIJ_Bdls": "0",
        "EPIJ_Ink_": "0",
        "EPIJ_Medi": "0",
        "EPIJ_Mode": "3",
        "EPIJ_Qual": "303",
        "EPIJ_Size": "A4",
        "MediaType": "0",
        "PageSize": "A4",
        "Resolution": "360x360dpi",
    ])
    #expect(!options.fillsBorderlessPhotoMedia)
}

@Test
func resolverMapsA4ColorAndQualityMatrix() throws {
    let media = PrinterMediaCapabilities(
        choices: [
            .init(
                ippKeyword: "stationery",
                displayName: "Plain Paper",
                cupsOptions: ["EPIJ_Medi": "0", "MediaType": "0"]
            ),
        ],
        defaultTypeKeyword: "stationery",
        sizes: [
            .init(
                ippKeyword: "iso_a4_210x297mm",
                xDimension: 21000,
                yDimension: 29700,
                cupsOptions: ["PageSize": "A4", "EPIJ_Size": "A4", "EPIJ_Bdls": "0"]
            ),
        ],
        defaultSize: nil
    )
    let output = PrinterOutputCapabilities(
        supportsColor: true,
        supportsMonochrome: true,
        generalQualityOptions: [
            3: ["EPIJ_Qual": "308", "Resolution": "180x180dpi"],
            4: ["EPIJ_Mode": "3", "EPIJ_Qual": "303", "Resolution": "360x360dpi"],
            5: ["EPIJ_Mode": "3", "EPIJ_Qual": "304", "Resolution": "720x720dpi"],
        ],
        photoNormalOptions: [:],
        colorModeOptions: [
            "color": ["ColorModel": "RGB", "EPIJ_Ink_": "1"],
            "monochrome": ["ColorModel": "Mono", "EPIJ_Ink_": "0"],
        ]
    )
    let qualities = [
        (quality: 3, driverValue: "308", resolution: "180x180dpi"),
        (quality: 4, driverValue: "303", resolution: "360x360dpi"),
        (quality: 5, driverValue: "304", resolution: "720x720dpi"),
    ]
    let colorModes = [
        (keyword: "color", colorModel: "RGB", inkMode: "1"),
        (keyword: "monochrome", colorModel: "Mono", inkMode: "0"),
    ]

    for quality in qualities {
        for color in colorModes {
            var message = Data([0x02, 0x00])
            message.append(contentsOf: [0x00, 0x02])
            message.append(contentsOf: [0x00, 0x00, 0x00, UInt8(0x30 + quality.quality)])
            message.append(0x02)
            appendAttribute(tag: 0x44, name: "media", value: "iso_a4_210x297mm", to: &message)
            appendAttribute(tag: 0x44, name: "media-type", value: "stationery", to: &message)
            appendAttribute(tag: 0x44, name: "print-color-mode", value: color.keyword, to: &message)
            appendIntegerAttribute(name: "print-quality", value: UInt32(quality.quality), to: &message)
            message.append(0x03)
            message.append(Data("A4-DOCUMENT".utf8))

            let request = try IPPRequestParser.parse(message)
            let options = PrintJobOptionResolver.resolve(request: request, media: media, output: output)

            #expect(options.cupsOptions["PageSize"] == "A4")
            #expect(options.cupsOptions["EPIJ_Qual"] == quality.driverValue)
            #expect(options.cupsOptions["Resolution"] == quality.resolution)
            #expect(options.cupsOptions["ColorModel"] == color.colorModel)
            #expect(options.cupsOptions["EPIJ_Ink_"] == color.inkMode)
            #expect(!options.fillsBorderlessPhotoMedia)
        }
    }
}

@Test
func resolverRespectsExplicitFitForBorderlessPhoto() throws {
    var message = Data([0x02, 0x00])
    message.append(contentsOf: [0x00, 0x02])
    message.append(contentsOf: [0x00, 0x00, 0x00, 0x2E])
    message.append(0x02)
    appendAttribute(tag: 0x44, name: "media", value: "oe_epkg-nmgn_4x6in", to: &message)
    appendAttribute(tag: 0x44, name: "media-type", value: "photographic-glossy", to: &message)
    appendAttribute(tag: 0x44, name: "print-scaling", value: "fit", to: &message)
    message.append(0x03)
    message.append(paddedPhotoPDFData())

    let request = try IPPRequestParser.parse(message)
    let options = PrintJobOptionResolver.resolve(
        request: request,
        media: PrinterMediaCapabilities(
            choices: [
                .init(
                    ippKeyword: "photographic-glossy",
                    displayName: "Photo Glossy Paper",
                    cupsOptions: [:],
                    isPhotoMedia: true
                ),
            ],
            defaultTypeKeyword: "stationery",
            sizes: [
                .init(
                    ippKeyword: "oe_epkg-nmgn_4x6in",
                    xDimension: 10160,
                    yDimension: 15240,
                    cupsOptions: ["PageSize": "EPKG.NMgn"],
                    isBorderless: true
                ),
            ],
            defaultSize: nil
        ),
        output: PrinterOutputCapabilities(
            supportsColor: true,
            supportsMonochrome: true,
            generalQualityOptions: [:],
            photoNormalOptions: [:]
        )
    )

    #expect(options.cupsOptions["print-scaling"] == "fit")
    #expect(!options.fillsBorderlessPhotoMedia)
}

@Test
func resolverDoesNotCropExplicitLabelsOnBorderlessPhotoSizedMedia() throws {
    var message = Data([0x02, 0x00])
    message.append(contentsOf: [0x00, 0x02])
    message.append(contentsOf: [0x00, 0x00, 0x00, 0x2F])
    message.append(0x02)
    appendAttribute(tag: 0x44, name: "media", value: "oe_epkg-nmgn_4x6in", to: &message)
    appendAttribute(tag: 0x44, name: "media-type", value: "labels", to: &message)
    message.append(0x03)
    message.append(paddedPhotoPDFData())

    let request = try IPPRequestParser.parse(message)
    let options = PrintJobOptionResolver.resolve(
        request: request,
        media: PrinterMediaCapabilities(
            choices: [
                .init(
                    ippKeyword: "labels",
                    displayName: "Photo Stickers",
                    cupsOptions: ["EPIJ_Medi": "72"],
                    isPhotoMedia: true
                ),
            ],
            defaultTypeKeyword: "stationery",
            sizes: [
                .init(
                    ippKeyword: "oe_epkg-nmgn_4x6in",
                    xDimension: 10160,
                    yDimension: 15240,
                    cupsOptions: ["PageSize": "EPKG.NMgn"],
                    isBorderless: true
                ),
            ],
            defaultSize: nil
        ),
        output: PrinterOutputCapabilities(
            supportsColor: true,
            supportsMonochrome: true,
            generalQualityOptions: [:],
            photoNormalOptions: [:]
        )
    )

    #expect(options.cupsOptions["print-scaling"] == nil)
    #expect(!options.fillsBorderlessPhotoMedia)
}

@Test
func resolverInfersLandscapeOrientationFromPDFPageGeometry() throws {
    var message = Data([0x02, 0x00])
    message.append(contentsOf: [0x00, 0x02])
    message.append(contentsOf: [0x00, 0x00, 0x00, 0x2D])
    message.append(0x02)
    appendAttribute(tag: 0x44, name: "media", value: "na_index-4x6_4x6in", to: &message)
    appendAttribute(tag: 0x49, name: "document-format", value: "application/pdf", to: &message)
    message.append(0x03)
    message.append(landscapePDFData())

    let request = try IPPRequestParser.parse(message)
    let options = PrintJobOptionResolver.resolve(
        request: request,
        media: PrinterMediaCapabilities(
            choices: [],
            defaultTypeKeyword: nil,
            sizes: [
                .init(
                    ippKeyword: "na_index-4x6_4x6in",
                    xDimension: 10160,
                    yDimension: 15240,
                    cupsOptions: ["PageSize": "EPKG.NMgn"],
                    isBorderless: true
                ),
            ],
            defaultSize: nil
        ),
        output: PrinterOutputCapabilities(
            supportsColor: true,
            supportsMonochrome: true,
            generalQualityOptions: [:],
            photoNormalOptions: [:]
        )
    )

    #expect(options.cupsOptions["orientation-requested"] == "4")
    #expect(options.cupsOptions["print-scaling"] == "fill")
    #expect(options.fillsBorderlessPhotoMedia)
}

@Test
func ippResponseEncodesNestedMediaCollections() throws {
    let response = IPPResponse(
        versionMajor: 2,
        versionMinor: 0,
        statusCode: .successfulOK,
        requestID: 44,
        groups: [
            .init(tag: .printerAttributes, attributes: [
                .init(name: "media-col-default", values: [.collection([
                    .init(name: "media-size", values: [.collection([
                        .init(name: "x-dimension", values: [.integer(21000)]),
                        .init(name: "y-dimension", values: [.integer(29700)]),
                    ])]),
                    .init(name: "media-type", values: [.keyword("stationery")]),
                ])]),
            ]),
        ]
    )

    let parsed = try IPPRequestParser.parse(response.encoded())
    let media = parsed.firstCollectionValue(named: "media-col-default")
    let size = media?.firstCollectionValue(named: "media-size")

    #expect(media?.firstStringValue(named: "media-type") == "stationery")
    #expect(size?.firstIntegerValue(named: "x-dimension") == 21000)
    #expect(size?.firstIntegerValue(named: "y-dimension") == 29700)
}

@Test
func compactMediaDatabaseIncludesPhotoTypesForBorderlessSizeVariants() {
    let bordered4x6 = PrinterMediaSize(
        ippKeyword: "na_index-4x6_4x6in",
        xDimension: 10160,
        yDimension: 15240,
        isBorderless: false
    )
    let borderless4x6 = PrinterMediaSize(
        ippKeyword: "oe_epkg-nmgn_4x6in",
        xDimension: 10160,
        yDimension: 15240,
        isBorderless: true
    )
    let borderless5x7 = PrinterMediaSize(
        ippKeyword: "om_epphoto-paper-2-l-nmgn_127x177.94mm",
        xDimension: 12700,
        yDimension: 17794,
        isBorderless: true
    )
    let media = PrinterMediaCapabilities(
        choices: [],
        defaultTypeKeyword: "stationery",
        sizes: [bordered4x6, borderless4x6, borderless5x7],
        defaultSize: bordered4x6
    )

    let database = ProxyAirPrintRequestHandler.compactMediaDatabase(
        media: media,
        typeKeywords: ["stationery", "photographic-glossy", "photographic-matte"],
        defaultType: "stationery",
        defaultSize: bordered4x6
    )

    #expect(database.containsMediaCombination(size: borderless4x6.ippKeyword, type: "photographic-glossy"))
    #expect(database.containsMediaCombination(size: borderless4x6.ippKeyword, type: "photographic-matte"))
    #expect(database.containsMediaCombination(size: borderless5x7.ippKeyword, type: "photographic-glossy"))
}

@Test
func printJobSubmissionForwardsResolvedCUPSOptions() throws {
    var capturedArguments: [String] = []
    let runner = InventoryStubCommandRunner { executable, arguments in
        capturedArguments = arguments
        return CommandResult(
            executable: executable,
            arguments: arguments,
            exitCode: 0,
            standardOutput: "request id is Epson-42 (1 file(s))",
            standardError: ""
        )
    }
    let service = PrintJobSubmissionService(runner: runner)

    let result = try service.submit(
        documentData: Data("PDF".utf8),
        toQueueNamed: "Epson",
        jobName: "Photo",
        documentFormat: "application/pdf",
        options: PrintJobOptions(cupsOptions: [
            "EPIJ_Medi": "145",
            "MediaType": "145",
            "media": "na_index-4x6_4x6in",
        ], copies: 3)
    )

    #expect(result.jobNumber == 42)
    #expect(capturedArguments.starts(with: ["-d", "Epson", "-t", "Photo"]))
    #expect(capturedArguments.contains(["-n", "3"]))
    #expect(capturedArguments.contains(["-o", "EPIJ_Medi=145"]))
    #expect(capturedArguments.contains(["-o", "MediaType=145"]))
    #expect(capturedArguments.contains(["-o", "media=na_index-4x6_4x6in"]))
}

@Test
func printJobSubmissionFillsWhitePaddedBorderlessPhotoPDF() throws {
    var submittedData: Data?
    let runner = InventoryStubCommandRunner { executable, arguments in
        submittedData = try? Data(contentsOf: URL(fileURLWithPath: arguments.last!))
        return CommandResult(
            executable: executable,
            arguments: arguments,
            exitCode: 0,
            standardOutput: "request id is Epson-43 (1 file(s))",
            standardError: ""
        )
    }
    let service = PrintJobSubmissionService(runner: runner)
    let originalData = paddedPhotoPDFData()

    _ = try service.submit(
        documentData: originalData,
        toQueueNamed: "Epson",
        jobName: "Borderless Photo",
        documentFormat: "application/pdf",
        options: PrintJobOptions(fillsBorderlessPhotoMedia: true)
    )

    let filledData = try #require(submittedData)
    #expect(filledData != originalData)
    let rendered = try renderedGrayscalePDF(filledData, width: 432, height: 288)
    #expect(rendered[144 * 432] < 252)
    #expect(rendered[144 * 432 + 431] < 252)
    #expect(rendered[216] < 252)
    #expect(rendered[287 * 432 + 216] < 252)
}

@Test
func borderlessPhotoProcessorLeavesAlreadyFilledPDFUnchanged() {
    let originalData = filledPhotoPDFData()
    #expect(BorderlessPhotoPDFProcessor.fillWhitePaddedPages(in: originalData) == originalData)
}

@Test
func borderlessPhotoProcessorFillsPortraitPhotoPadding() throws {
    let originalData = photoPDFData(
        mediaBox: CGRect(x: 0, y: 0, width: 288, height: 432),
        contentRect: CGRect(x: 0, y: 24, width: 288, height: 384)
    )
    let filledData = BorderlessPhotoPDFProcessor.fillWhitePaddedPages(in: originalData)
    let rendered = try renderedGrayscalePDF(filledData, width: 288, height: 432)

    #expect(filledData != originalData)
    #expect(rendered[144] < 252)
    #expect(rendered[431 * 288 + 144] < 252)
}

@Test(arguments: [90, 270])
func borderlessPhotoProcessorFillsRotatedPhotoPadding(rotation: Int) throws {
    let originalData = rotatedPaddedPhotoPDFData(rotation: rotation)
    let filledData = BorderlessPhotoPDFProcessor.fillWhitePaddedPages(in: originalData)
    let rendered = try renderedGrayscalePDF(filledData, width: 432, height: 288)

    #expect(filledData != originalData)
    #expect(rendered[144 * 432] < 252)
    #expect(rendered[144 * 432 + 431] < 252)
    #expect(rendered[216] < 252)
    #expect(rendered[287 * 432 + 216] < 252)
}

@Test
func borderlessPhotoProcessorFillsMixedRotatedPages() throws {
    let originalData = mixedRotationPhotoPDFData()
    let filledData = BorderlessPhotoPDFProcessor.fillWhitePaddedPages(in: originalData)
    let firstPage = try renderedGrayscalePDF(filledData, pageNumber: 1, width: 432, height: 288)
    let secondPage = try renderedGrayscalePDF(filledData, pageNumber: 2, width: 432, height: 288)

    #expect(filledData != originalData)
    #expect(firstPage[144 * 432] < 252)
    #expect(firstPage[144 * 432 + 431] < 252)
    #expect(secondPage[144 * 432] < 252)
    #expect(secondPage[144 * 432 + 431] < 252)
}

@Test
func borderlessPhotoProcessorSkipsDocumentsBeyondPageLimit() {
    let originalData = manyPagePaddedPhotoPDFData(pageCount: 101)
    #expect(BorderlessPhotoPDFProcessor.fillWhitePaddedPages(in: originalData) == originalData)
}

@Test
func httpRequestAssemblerDecodesChunkedIPPBodyAlreadyBufferedWithHeaders() {
    let assembler = HTTPRequestAssembler()
    assembler.append(Data(
        "POST /printers/test HTTP/1.1\r\n"
            .appending("Content-Type: application/ipp\r\n")
            .appending("Transfer-Encoding: chunked\r\n")
            .appending("Expect: 100-continue\r\n\r\n")
            .appending("4\r\nIPP-\r\n4\r\nDATA\r\n0\r\n\r\n")
            .utf8
    ))

    #expect(assembler.shouldSendContinue)
    assembler.markContinueSent()
    let request = assembler.takeRequest()

    #expect(request?.method == "POST")
    #expect(request?.path == "/printers/test")
    #expect(String(data: request?.body ?? Data(), encoding: .utf8) == "IPP-DATA")
}

@Test
func httpRequestAssemblerWaitsForFinalChunkAcrossReads() {
    let assembler = HTTPRequestAssembler()
    assembler.append(Data(
        "POST /printers/test HTTP/1.1\r\n"
            .appending("Content-Type: application/ipp\r\n")
            .appending("Transfer-Encoding: chunked\r\n\r\n")
            .appending("8\r\nIPP-")
            .utf8
    ))

    #expect(assembler.takeRequest() == nil)
    assembler.append(Data("DATA\r\n0\r\n\r\n".utf8))

    #expect(String(data: assembler.takeRequest()?.body ?? Data(), encoding: .utf8) == "IPP-DATA")
}

@Test
func httpRequestAssemblerRejectsOversizedDeclaredBodyBeforeContinue() {
    let assembler = HTTPRequestAssembler()
    let request = "POST /printers/Epson HTTP/1.1\r\n"
        + "Content-Type: application/ipp\r\n"
        + "Content-Length: \(HTTPRequestAssembler.maximumBodyByteCount + 1)\r\n"
        + "Expect: 100-continue\r\n\r\n"

    assembler.append(Data(request.utf8))

    #expect(assembler.exceededSizeLimit)
    #expect(!assembler.shouldSendContinue)
    #expect(assembler.takeRequest() == nil)
}

@Test
func ippRequestParserRejectsExcessiveCollectionDepth() {
    var message = Data([0x02, 0x00])
    message.append(contentsOf: [0x00, 0x02])
    message.append(contentsOf: [0x00, 0x00, 0x00, 0x41])
    message.append(0x02)
    appendCollectionStart(name: "media-col", to: &message)
    for depth in 2...9 {
        appendCollectionMemberName("nested-\(depth)", to: &message)
        appendCollectionStart(name: nil, to: &message)
    }
    appendCollectionMemberName("leaf", to: &message)
    appendCollectionString(tag: 0x44, value: "value", to: &message)
    for _ in 1...9 {
        appendCollectionEnd(to: &message)
    }
    message.append(0x03)

    #expect(throws: IPPRequestParserError.malformedAttribute) {
        try IPPRequestParser.parse(message)
    }
}

private func appendAttribute(tag: UInt8, name: String, value: String, to data: inout Data) {
    let nameData = Data(name.utf8)
    let valueData = Data(value.utf8)
    data.append(tag)
    data.append(contentsOf: [UInt8((nameData.count >> 8) & 0xff), UInt8(nameData.count & 0xff)])
    data.append(nameData)
    data.append(contentsOf: [UInt8((valueData.count >> 8) & 0xff), UInt8(valueData.count & 0xff)])
    data.append(valueData)
}

private func appendIntegerAttribute(name: String, value: UInt32, to data: inout Data) {
    let nameData = Data(name.utf8)
    data.append(0x21)
    appendLengthPrefixed(nameData, to: &data)
    appendLengthPrefixed(Data([
        UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff), UInt8(value & 0xff),
    ]), to: &data)
}

private func landscapePDFData() -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 432, height: 288)
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
    context.beginPDFPage(nil)
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

private func paddedPhotoPDFData() -> Data {
    photoPDFData(contentRect: CGRect(x: 24, y: 0, width: 384, height: 288))
}

private func filledPhotoPDFData() -> Data {
    photoPDFData(contentRect: CGRect(x: 0, y: 0, width: 432, height: 288))
}

private func photoPDFData(contentRect: CGRect) -> Data {
    photoPDFData(
        mediaBox: CGRect(x: 0, y: 0, width: 432, height: 288),
        contentRect: contentRect
    )
}

private func photoPDFData(mediaBox inputMediaBox: CGRect, contentRect: CGRect) -> Data {
    let data = NSMutableData()
    var mediaBox = inputMediaBox
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
    context.beginPDFPage(nil)
    context.setFillColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(contentRect)
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

private func rotatedPaddedPhotoPDFData(rotation: Int) -> Data {
    let data = photoPDFData(
        mediaBox: CGRect(x: 0, y: 0, width: 288, height: 432),
        contentRect: CGRect(x: 0, y: 24, width: 288, height: 384)
    )
    let document = PDFDocument(data: data)!
    document.page(at: 0)!.rotation = rotation
    return document.dataRepresentation()!
}

private func mixedRotationPhotoPDFData() -> Data {
    let data = NSMutableData()
    var firstMediaBox = CGRect(x: 0, y: 0, width: 432, height: 288)
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let context = CGContext(consumer: consumer, mediaBox: &firstMediaBox, nil)!
    context.beginPDFPage(nil)
    context.setFillColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 24, y: 0, width: 384, height: 288))
    context.endPDFPage()

    var secondMediaBox = CGRect(x: 0, y: 0, width: 288, height: 432)
    context.beginPDFPage([
        kCGPDFContextMediaBox: Data(bytes: &secondMediaBox, count: MemoryLayout<CGRect>.size),
    ] as CFDictionary)
    context.setFillColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 24, width: 288, height: 384))
    context.endPDFPage()
    context.closePDF()
    let document = PDFDocument(data: data as Data)!
    document.page(at: 1)!.rotation = 90
    return document.dataRepresentation()!
}

private func manyPagePaddedPhotoPDFData(pageCount: Int) -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 432, height: 288)
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
    for _ in 0..<pageCount {
        context.beginPDFPage(nil)
        context.setFillColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 24, y: 0, width: 384, height: 288))
        context.endPDFPage()
    }
    context.closePDF()
    return data as Data
}

private func renderedGrayscalePDF(
    _ data: Data,
    pageNumber: Int = 1,
    width: Int,
    height: Int
) throws -> [UInt8] {
    let provider = try #require(CGDataProvider(data: data as CFData))
    let document = try #require(CGPDFDocument(provider))
    let page = try #require(document.page(at: pageNumber))
    var pixels = [UInt8](repeating: 255, count: width * height)
    let context = try #require(CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ))
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let drawingTransform = page.getDrawingTransform(
        .mediaBox,
        rect: CGRect(x: 0, y: 0, width: width, height: height),
        rotate: 0,
        preserveAspectRatio: false
    )
    context.concatenate(drawingTransform)
    context.drawPDFPage(page)
    return pixels
}

private extension Array where Element == IPPResponseValue {
    func containsMediaCombination(size: String, type: String) -> Bool {
        contains { value in
            guard case let .collection(members) = value else { return false }
            let sizeName = members.first(where: { $0.name == "media-size-name" })?.values.first
            let mediaType = members.first(where: { $0.name == "media-type" })?.values.first
            return sizeName == .keyword(size) && mediaType == .keyword(type)
        }
    }
}

private func appendCollectionStart(name: String?, to data: inout Data) {
    data.append(0x34)
    appendLengthPrefixed(name.map { Data($0.utf8) } ?? Data(), to: &data)
    appendLengthPrefixed(Data(), to: &data)
}

private func appendCollectionMemberName(_ name: String, to data: inout Data) {
    data.append(0x4A)
    appendLengthPrefixed(Data(), to: &data)
    appendLengthPrefixed(Data(name.utf8), to: &data)
}

private func appendCollectionString(tag: UInt8, value: String, to data: inout Data) {
    data.append(tag)
    appendLengthPrefixed(Data(), to: &data)
    appendLengthPrefixed(Data(value.utf8), to: &data)
}

private func appendCollectionInteger(_ value: UInt32, to data: inout Data) {
    data.append(0x21)
    appendLengthPrefixed(Data(), to: &data)
    appendLengthPrefixed(Data([
        UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff), UInt8(value & 0xff),
    ]), to: &data)
}

private func appendCollectionEnd(to data: inout Data) {
    data.append(0x37)
    appendLengthPrefixed(Data(), to: &data)
    appendLengthPrefixed(Data(), to: &data)
}

private func appendLengthPrefixed(_ value: Data, to data: inout Data) {
    data.append(contentsOf: [UInt8((value.count >> 8) & 0xff), UInt8(value.count & 0xff)])
    data.append(value)
}

private extension Array where Element == String {
    func contains(_ adjacentPair: [String]) -> Bool {
        guard adjacentPair.count == 2, count >= 2 else { return false }
        return indices.dropLast().contains { index in
            self[index] == adjacentPair[0] && self[index + 1] == adjacentPair[1]
        }
    }
}
