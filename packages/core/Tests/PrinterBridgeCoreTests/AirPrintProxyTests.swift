import Foundation
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
    appendCollectionEnd(to: &message)
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
                    cupsOptions: ["EPIJ_Medi": "145", "MediaType": "145"]
                ),
            ],
            defaultTypeKeyword: "stationery",
            sizes: [
                .init(
                    ippKeyword: "na_index-4x6_4x6in",
                    xDimension: 10160,
                    yDimension: 15240
                ),
            ],
            defaultSize: nil
        )
    )

    #expect(options.cupsOptions == [
        "EPIJ_Medi": "145",
        "MediaType": "145",
        "media": "na_index-4x6_4x6in",
    ])
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
        ])
    )

    #expect(result.jobNumber == 42)
    #expect(capturedArguments.starts(with: ["-d", "Epson", "-t", "Photo"]))
    #expect(capturedArguments.contains(["-o", "EPIJ_Medi=145"]))
    #expect(capturedArguments.contains(["-o", "MediaType=145"]))
    #expect(capturedArguments.contains(["-o", "media=na_index-4x6_4x6in"]))
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

private func appendAttribute(tag: UInt8, name: String, value: String, to data: inout Data) {
    let nameData = Data(name.utf8)
    let valueData = Data(value.utf8)
    data.append(tag)
    data.append(contentsOf: [UInt8((nameData.count >> 8) & 0xff), UInt8(nameData.count & 0xff)])
    data.append(nameData)
    data.append(contentsOf: [UInt8((valueData.count >> 8) & 0xff), UInt8(valueData.count & 0xff)])
    data.append(valueData)
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
