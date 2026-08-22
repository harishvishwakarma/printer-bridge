import Foundation

public struct PrinterMediaChoice: Equatable, Sendable {
    public let ippKeyword: String
    public let displayName: String
    public let cupsOptions: [String: String]

    public init(ippKeyword: String, displayName: String, cupsOptions: [String: String]) {
        self.ippKeyword = ippKeyword
        self.displayName = displayName
        self.cupsOptions = cupsOptions
    }
}

public struct PrinterMediaSize: Equatable, Sendable {
    public let ippKeyword: String
    public let xDimension: Int
    public let yDimension: Int
    public let bottomMargin: Int
    public let leftMargin: Int
    public let rightMargin: Int
    public let topMargin: Int

    public init(
        ippKeyword: String,
        xDimension: Int,
        yDimension: Int,
        bottomMargin: Int = 0,
        leftMargin: Int = 0,
        rightMargin: Int = 0,
        topMargin: Int = 0
    ) {
        self.ippKeyword = ippKeyword
        self.xDimension = xDimension
        self.yDimension = yDimension
        self.bottomMargin = bottomMargin
        self.leftMargin = leftMargin
        self.rightMargin = rightMargin
        self.topMargin = topMargin
    }
}

public struct PrinterMediaCapabilities: Equatable, Sendable {
    public let choices: [PrinterMediaChoice]
    public let defaultTypeKeyword: String?
    public let sizes: [PrinterMediaSize]
    public let defaultSize: PrinterMediaSize?

    public init(
        choices: [PrinterMediaChoice],
        defaultTypeKeyword: String?,
        sizes: [PrinterMediaSize],
        defaultSize: PrinterMediaSize?
    ) {
        self.choices = choices
        self.defaultTypeKeyword = defaultTypeKeyword
        self.sizes = sizes
        self.defaultSize = defaultSize
    }

    public func cupsOptions(forIPPKeyword keyword: String) -> [String: String] {
        choices.first(where: { $0.ippKeyword == keyword })?.cupsOptions ?? [:]
    }
}

public struct PrinterMediaCapabilityService {
    private struct Candidate {
        let driverValue: String
        let displayName: String
        let preference: Int
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func capabilities(
        attributes: IPPPrinterAttributesSnapshot?,
        inspection: PrinterQueueInspection?
    ) -> PrinterMediaCapabilities {
        let mediaOptions = inspection?.options.filter(Self.isMediaTypeOption) ?? []
        let ppdContents: String?
        if let path = inspection?.detail.interfacePath, fileManager.isReadableFile(atPath: path) {
            ppdContents = try? String(contentsOfFile: path, encoding: .utf8)
        } else {
            ppdContents = nil
        }

        var candidates: [String: [String: Candidate]] = [:]
        if let ppdContents {
            for option in mediaOptions {
                let labels = Self.choiceLabels(forOptionKey: option.key, in: ppdContents)
                for choice in option.values {
                    guard
                        let displayName = labels[choice.value],
                        let keyword = Self.standardMediaTypeKeyword(for: displayName)
                    else {
                        continue
                    }

                    let candidate = Candidate(
                        driverValue: choice.value,
                        displayName: displayName,
                        preference: Self.preferenceScore(for: displayName, keyword: keyword)
                    )
                    let current = candidates[keyword]?[option.key]
                    if current == nil || candidate.preference > current?.preference ?? Int.min {
                        candidates[keyword, default: [:]][option.key] = candidate
                    }
                }
            }
        }

        for rawKeyword in attributes?.values(named: "media-type-supported") ?? [] {
            let keyword = rawKeyword.lowercased()
            guard Self.isStandardMediaTypeKeyword(keyword) else { continue }
            candidates[keyword, default: [:]]["media-type"] = Candidate(
                driverValue: keyword,
                displayName: Self.displayName(forStandardKeyword: keyword),
                preference: 0
            )
        }

        let choices = candidates.keys.sorted().compactMap { keyword -> PrinterMediaChoice? in
            guard let optionCandidates = candidates[keyword], !optionCandidates.isEmpty else { return nil }
            let preferred = optionCandidates.values.max { lhs, rhs in lhs.preference < rhs.preference }
            return PrinterMediaChoice(
                ippKeyword: keyword,
                displayName: preferred?.displayName ?? Self.displayName(forStandardKeyword: keyword),
                cupsOptions: optionCandidates.mapValues(\.driverValue)
            )
        }

        let defaultTypeKeyword = mediaOptions.lazy.compactMap { option -> String? in
            guard
                let defaultValue = option.defaultValue,
                let ppdContents,
                let label = Self.choiceLabels(forOptionKey: option.key, in: ppdContents)[defaultValue]
            else {
                return nil
            }
            return Self.standardMediaTypeKeyword(for: label)
        }.first ?? Self.standardDefaultType(from: attributes)

        let sizes = Self.mediaSizes(from: attributes)
        let defaultSize = Self.defaultMediaSize(from: attributes, knownSizes: sizes)

        return PrinterMediaCapabilities(
            choices: choices,
            defaultTypeKeyword: defaultTypeKeyword,
            sizes: sizes,
            defaultSize: defaultSize
        )
    }

    static func choiceLabels(forOptionKey optionKey: String, in ppdContents: String) -> [String: String] {
        let prefix = "*\(optionKey) "
        var labels: [String: String] = [:]

        for rawLine in ppdContents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard line.hasPrefix(prefix) else { continue }
            let choice = line.dropFirst(prefix.count)
            guard
                let slash = choice.firstIndex(of: "/"),
                let colon = choice[choice.index(after: slash)...].firstIndex(of: ":")
            else {
                continue
            }

            let value = String(choice[..<slash]).trimmingCharacters(in: .whitespaces)
            let label = String(choice[choice.index(after: slash)..<colon]).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty, !label.isEmpty {
                labels[value] = label
            }
        }

        return labels
    }

    static func standardMediaTypeKeyword(for displayName: String) -> String? {
        let name = displayName.lowercased()
        if name.contains("letterhead") { return "stationery-letterhead" }
        if name.contains("envelope") { return "envelope" }
        if name.contains("sticker") || name.contains("label") { return "labels" }
        if name.contains("card") { return "card-stock" }
        if name.contains("semi") && name.contains("gloss") { return "photographic-semi-gloss" }
        if name.contains("satin") || name.contains("luster") || name.contains("lustre") { return "photographic-satin" }
        if name.contains("matte") || name.contains("matt ") { return "photographic-matte" }
        if name.contains("ultra") && name.contains("gloss") { return "photographic-high-gloss" }
        if name.contains("gloss") { return "photographic-glossy" }
        if name.contains("photo quality") || name.contains("coated") { return "stationery-coated" }
        if name.contains("plain") { return "stationery" }
        return nil
    }

    private static func isMediaTypeOption(_ option: PrinterOption) -> Bool {
        let key = option.key.lowercased()
        let displayName = option.displayName.lowercased()
        return key == "mediatype"
            || key.hasSuffix("_medi")
            || displayName.contains("media type")
            || displayName.contains("paper type")
    }

    private static func preferenceScore(for displayName: String, keyword: String) -> Int {
        let name = displayName.lowercased()
        if keyword == "photographic-glossy", name == "photo paper glossy" { return 30 }
        if name.contains("premium") { return 20 }
        if name.contains("epson") { return 10 }
        return 0
    }

    private static func isStandardMediaTypeKeyword(_ keyword: String) -> Bool {
        let known = [
            "card-stock", "envelope", "labels", "photographic-glossy",
            "photographic-high-gloss", "photographic-matte", "photographic-satin",
            "photographic-semi-gloss", "stationery", "stationery-coated",
            "stationery-letterhead",
        ]
        return known.contains(keyword)
    }

    private static func displayName(forStandardKeyword keyword: String) -> String {
        keyword
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private static func standardDefaultType(from attributes: IPPPrinterAttributesSnapshot?) -> String? {
        let rawDefault = attributes?.stringValue(named: "media-type-default")?.lowercased()
        guard let rawDefault, isStandardMediaTypeKeyword(rawDefault) else { return nil }
        return rawDefault
    }

    private static func mediaSizes(from attributes: IPPPrinterAttributesSnapshot?) -> [PrinterMediaSize] {
        let names = attributes?.values(named: "media-supported") ?? []
        let collections = attributes?.values(named: "media-col-database") ?? []
        let dimensionCollections = attributes?.values(named: "media-size-supported") ?? []

        return names.enumerated().compactMap { index, name in
            let collection = collections.indices.contains(index)
                ? collections[index]
                : (dimensionCollections.indices.contains(index) ? dimensionCollections[index] : "")
            guard
                let xDimension = intValue(named: "x-dimension", in: collection),
                let yDimension = intValue(named: "y-dimension", in: collection)
            else {
                return nil
            }

            return PrinterMediaSize(
                ippKeyword: name,
                xDimension: xDimension,
                yDimension: yDimension,
                bottomMargin: intValue(named: "media-bottom-margin", in: collection) ?? 0,
                leftMargin: intValue(named: "media-left-margin", in: collection) ?? 0,
                rightMargin: intValue(named: "media-right-margin", in: collection) ?? 0,
                topMargin: intValue(named: "media-top-margin", in: collection) ?? 0
            )
        }
    }

    private static func defaultMediaSize(
        from attributes: IPPPrinterAttributesSnapshot?,
        knownSizes: [PrinterMediaSize]
    ) -> PrinterMediaSize? {
        if let defaultName = attributes?.stringValue(named: "media-default"),
           let known = knownSizes.first(where: { $0.ippKeyword == defaultName }) {
            return known
        }

        guard
            let rawCollection = attributes?.stringValue(named: "media-col-default"),
            let xDimension = intValue(named: "x-dimension", in: rawCollection),
            let yDimension = intValue(named: "y-dimension", in: rawCollection)
        else {
            return knownSizes.first
        }

        return PrinterMediaSize(
            ippKeyword: attributes?.stringValue(named: "media-default") ?? "custom",
            xDimension: xDimension,
            yDimension: yDimension,
            bottomMargin: intValue(named: "media-bottom-margin", in: rawCollection) ?? 0,
            leftMargin: intValue(named: "media-left-margin", in: rawCollection) ?? 0,
            rightMargin: intValue(named: "media-right-margin", in: rawCollection) ?? 0,
            topMargin: intValue(named: "media-top-margin", in: rawCollection) ?? 0
        )
    }

    private static func intValue(named key: String, in collection: String) -> Int? {
        guard let keyRange = collection.range(of: "\(key)=") else { return nil }
        let suffix = collection[keyRange.upperBound...]
        let digits = suffix.prefix(while: { $0.isNumber })
        return Int(digits)
    }
}
