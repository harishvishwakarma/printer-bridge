import Foundation

public struct PrinterMediaChoice: Equatable, Sendable {
    public let ippKeyword: String
    public let displayName: String
    public let cupsOptions: [String: String]
    public let photoPresetOptions: [String: String]
    public let isPhotoMedia: Bool

    public init(
        ippKeyword: String,
        displayName: String,
        cupsOptions: [String: String],
        photoPresetOptions: [String: String] = [:],
        isPhotoMedia: Bool = false
    ) {
        self.ippKeyword = ippKeyword
        self.displayName = displayName
        self.cupsOptions = cupsOptions
        self.photoPresetOptions = photoPresetOptions
        self.isPhotoMedia = isPhotoMedia
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
    public let displayName: String
    public let cupsOptions: [String: String]
    public let isBorderless: Bool

    public init(
        ippKeyword: String,
        xDimension: Int,
        yDimension: Int,
        bottomMargin: Int = 0,
        leftMargin: Int = 0,
        rightMargin: Int = 0,
        topMargin: Int = 0,
        displayName: String? = nil,
        cupsOptions: [String: String] = [:],
        isBorderless: Bool = false
    ) {
        self.ippKeyword = ippKeyword
        self.xDimension = xDimension
        self.yDimension = yDimension
        self.bottomMargin = bottomMargin
        self.leftMargin = leftMargin
        self.rightMargin = rightMargin
        self.topMargin = topMargin
        self.displayName = displayName ?? ippKeyword
        self.cupsOptions = cupsOptions
        self.isBorderless = isBorderless
    }
}

public struct PrinterOutputCapabilities: Equatable, Sendable {
    public let supportsColor: Bool
    public let supportsMonochrome: Bool
    public let generalQualityOptions: [Int: [String: String]]
    public let photoNormalOptions: [String: String]
    public let colorModeOptions: [String: [String: String]]

    public init(
        supportsColor: Bool,
        supportsMonochrome: Bool,
        generalQualityOptions: [Int: [String: String]],
        photoNormalOptions: [String: String],
        colorModeOptions: [String: [String: String]] = [:]
    ) {
        self.supportsColor = supportsColor
        self.supportsMonochrome = supportsMonochrome
        self.generalQualityOptions = generalQualityOptions
        self.photoNormalOptions = photoNormalOptions
        self.colorModeOptions = colorModeOptions
    }

    public func colorOptions(for keyword: String) -> [String: String] {
        switch keyword {
        case "monochrome", "bi-level":
            return supportsMonochrome ? colorModeOptions["monochrome"] ?? [:] : [:]
        case "auto", "color":
            return supportsColor ? colorModeOptions["color"] ?? [:] : [:]
        default:
            return [:]
        }
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

    private struct PPDPageSize {
        let value: String
        let displayName: String
        let xDimension: Int
        let yDimension: Int
        let isBorderless: Bool
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
        let photoPresets = ppdContents.map(Self.photoPresetOptionsByMediaValue) ?? [:]
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

        if let ppdContents,
           let inspection,
           let matteCandidates = candidates["photographic-matte"],
           let thickPaperOption = inspection.options.first(where: Self.isThickPaperOption),
           let enabledValue = Self.enabledValue(for: thickPaperOption, in: ppdContents) {
            var cardStockCandidates = matteCandidates
            cardStockCandidates.removeValue(forKey: "media-type")
            cardStockCandidates[thickPaperOption.key] = Candidate(
                driverValue: enabledValue,
                displayName: "Card Stock",
                preference: 100
            )
            candidates["card-stock"] = cardStockCandidates
        }

        let choices = candidates.keys.sorted().compactMap { keyword -> PrinterMediaChoice? in
            guard let optionCandidates = candidates[keyword], !optionCandidates.isEmpty else { return nil }
            let preferred = optionCandidates.values.max { lhs, rhs in lhs.preference < rhs.preference }
            let mediaValue = optionCandidates["EPIJ_Medi"]?.driverValue
                ?? optionCandidates["MediaType"]?.driverValue
            return PrinterMediaChoice(
                ippKeyword: keyword,
                displayName: preferred?.displayName ?? Self.displayName(forStandardKeyword: keyword),
                cupsOptions: optionCandidates.mapValues(\.driverValue),
                photoPresetOptions: mediaValue.flatMap { photoPresets[$0] } ?? [:],
                isPhotoMedia: Self.isPhotoMediaKeyword(keyword)
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

        let rawSizes = Self.mediaSizes(from: attributes)
        let sizes = ppdContents.map { Self.enrichMediaSizes(rawSizes, ppdContents: $0) } ?? rawSizes
        let defaultSize = Self.defaultMediaSize(from: attributes, knownSizes: sizes)

        return PrinterMediaCapabilities(
            choices: choices,
            defaultTypeKeyword: defaultTypeKeyword,
            sizes: sizes,
            defaultSize: defaultSize
        )
    }

    public func outputCapabilities(
        attributes: IPPPrinterAttributesSnapshot?,
        inspection: PrinterQueueInspection?
    ) -> PrinterOutputCapabilities {
        let options = inspection?.options ?? []
        let ppdContents = inspection?.detail.interfacePath.flatMap { path in
            fileManager.isReadableFile(atPath: path)
                ? try? String(contentsOfFile: path, encoding: .utf8)
                : nil
        }
        let presets = ppdContents.map(Self.printerPresets) ?? []
        let qualityOption = options.first(where: { option in
            option.key == "EPIJ_Qual" || option.displayName.localizedCaseInsensitiveContains("print quality")
        })
        let qualityLabels = ppdContents.flatMap { contents in
            qualityOption.map { Self.choiceLabels(forOptionKey: $0.key, in: contents) }
        } ?? [:]
        let resolutionOption = options.first(where: { $0.key == "Resolution" })
        let supportedResolutions = resolutionOption?.values.map(\.value) ?? []

        func qualityValue(containing terms: [String]) -> String? {
            qualityOption?.values.first(where: { choice in
                guard let label = qualityLabels[choice.value]?.lowercased() else { return false }
                return terms.contains(where: label.contains)
            })?.value
        }

        func resolution(closestTo target: Int) -> String? {
            supportedResolutions.min { lhs, rhs in
                abs((Int(lhs.split(separator: "x").first ?? "") ?? target) - target)
                    < abs((Int(rhs.split(separator: "x").first ?? "") ?? target) - target)
            }
        }

        let plainGeneralPreset = presets.first(where: {
            $0["EPIJ_Medi"] == "0" && $0["preset.graphicsType"] == "General"
                && $0["EPIJ_Ink_"] == "1"
        }) ?? [:]
        let plainPhotoPreset = presets.first(where: {
            $0["EPIJ_Medi"] == "0" && $0["preset.graphicsType"] == "Photo"
        }) ?? [:]

        var draft: [String: String] = [:]
        if let value = qualityValue(containing: ["draft"]) { draft[qualityOption?.key ?? "EPIJ_Qual"] = value }
        if let value = resolution(closestTo: 180) { draft["Resolution"] = value }

        var normal = Self.driverOptions(fromPreset: plainGeneralPreset)
        if normal.isEmpty, let value = qualityValue(containing: ["normal"]) {
            normal[qualityOption?.key ?? "EPIJ_Qual"] = value
        }
        if normal["Resolution"] == nil, let value = resolution(closestTo: 360) { normal["Resolution"] = value }

        var high = Self.driverOptions(fromPreset: plainPhotoPreset)
        if high.isEmpty, let value = qualityValue(containing: ["fine", "high quality"]) {
            high[qualityOption?.key ?? "EPIJ_Qual"] = value
        }
        if high["Resolution"] == nil, let value = resolution(closestTo: 720) { high["Resolution"] = value }

        var photoNormal: [String: String] = [:]
        if let value = qualityValue(containing: ["quality"]) { photoNormal[qualityOption?.key ?? "EPIJ_Qual"] = value }
        if let value = resolution(closestTo: 720) { photoNormal["Resolution"] = value }
        if options.contains(where: { option in
            option.key == "EPIJ_Mode" && option.values.contains(where: { $0.value == "3" })
        }) {
            photoNormal["EPIJ_Mode"] = "3"
        }

        var colorModeOptions: [String: [String: String]] = [:]
        if let colorModel = options.first(where: { $0.key == "ColorModel" }) {
            if let value = colorModel.values.first(where: {
                ["rgb", "cmyk", "color"].contains($0.value.lowercased())
            })?.value {
                colorModeOptions["color", default: [:]][colorModel.key] = value
            }
            if let value = colorModel.values.first(where: {
                ["mono", "gray", "grayscale", "black"].contains($0.value.lowercased())
            })?.value {
                colorModeOptions["monochrome", default: [:]][colorModel.key] = value
            }
        }
        if let inkMode = options.first(where: { $0.key == "EPIJ_Ink_" }) {
            if inkMode.values.contains(where: { $0.value == "1" }) {
                colorModeOptions["color", default: [:]][inkMode.key] = "1"
            }
            if inkMode.values.contains(where: { $0.value == "0" }) {
                colorModeOptions["monochrome", default: [:]][inkMode.key] = "0"
            }
        }

        let supportsColor = attributes?.boolValue(named: "color-supported")
            ?? options.contains(where: { $0.key == "ColorModel" && $0.values.contains(where: { $0.value == "RGB" }) })
        let supportsMonochrome = options.contains(where: {
            ($0.key == "ColorModel" && $0.values.contains(where: { $0.value == "Mono" }))
                || ($0.key == "EPIJ_Ink_" && $0.values.contains(where: { $0.value == "0" }))
        })

        return PrinterOutputCapabilities(
            supportsColor: supportsColor,
            supportsMonochrome: supportsMonochrome,
            generalQualityOptions: [3: draft, 4: normal, 5: high],
            photoNormalOptions: photoNormal,
            colorModeOptions: colorModeOptions
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

    private static func printerPresets(_ ppdContents: String) -> [[String: String]] {
        var presets: [[String: String]] = []
        var current: [String: String]?

        for rawLine in ppdContents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("*APPrinterPreset ") {
                current = [:]
                continue
            }
            guard current != nil else { continue }
            if line == "*End" {
                if let current { presets.append(current) }
                current = nil
                continue
            }
            if line.hasPrefix("com.apple.print.preset.graphicsType ") {
                current?["preset.graphicsType"] = String(line.split(separator: " ").last ?? "")
                continue
            }
            guard line.hasPrefix("*"), !line.hasPrefix("*EPSON.PrintModule.Setting."),
                  !line.hasPrefix("*EPIJPrinterPreset") else {
                continue
            }
            let components = line.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
            if components.count == 2, !components[0].contains(".") {
                current?[components[0]] = components[1]
            }
        }

        return presets
    }

    private static func photoPresetOptionsByMediaValue(_ ppdContents: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for preset in printerPresets(ppdContents)
            where preset["preset.graphicsType"] == "Photo" {
            guard let mediaValue = preset["EPIJ_Medi"] else { continue }
            result[mediaValue] = driverOptions(fromPreset: preset)
        }
        return result
    }

    private static func driverOptions(fromPreset preset: [String: String]) -> [String: String] {
        let allowed = ["EPIJ_Medi", "EPIJ_Ink_", "EPIJ_Mode", "EPIJ_Qual", "EPIJ_Hori", "Resolution"]
        return preset.filter { allowed.contains($0.key) }
    }

    private static func enrichMediaSizes(
        _ sizes: [PrinterMediaSize],
        ppdContents: String
    ) -> [PrinterMediaSize] {
        let pageSizes = ppdPageSizes(ppdContents)
        let epsonSizeLabels = choiceLabels(forOptionKey: "EPIJ_Size", in: ppdContents)
        let epsonPageSourceLabels = choiceLabels(forOptionKey: "EPIJ_PSrc", in: ppdContents)
        let epsonBorderlessLabels = choiceLabels(forOptionKey: "EPIJ_Bdls", in: ppdContents)
        let epsonExpansionLabels = choiceLabels(forOptionKey: "EPIJ_exmg", in: ppdContents)

        return sizes.map { size in
            let zeroMargins = size.bottomMargin == 0 && size.leftMargin == 0
                && size.rightMargin == 0 && size.topMargin == 0
            let dimensionMatches = pageSizes.filter {
                abs($0.xDimension - size.xDimension) <= 5 && abs($0.yDimension - size.yDimension) <= 5
            }
            let pageSize = dimensionMatches.first(where: { $0.isBorderless == zeroMargins })
                ?? dimensionMatches.first(where: { !$0.isBorderless })
                ?? dimensionMatches.first
            guard let pageSize else { return size }

            let normalizedPageLabel = normalizedSizeLabel(pageSize.displayName)
            let epsonSizeValue = epsonSizeLabels.first(where: {
                normalizedSizeLabel($0.value) == normalizedPageLabel
            })?.key
            var options = ["PageSize": pageSize.value]
            if !epsonBorderlessLabels.isEmpty {
                options["EPIJ_Bdls"] = pageSize.isBorderless ? "1" : "0"
            }
            if pageSize.isBorderless, !epsonExpansionLabels.isEmpty {
                options["EPIJ_exmg"] = "2"
            }
            let pageSourceLabel = pageSize.isBorderless ? "borderless" : "standard"
            if let pageSourceValue = epsonPageSourceLabels.first(where: {
                $0.value.localizedCaseInsensitiveContains(pageSourceLabel)
            })?.key {
                options["EPIJ_PSrc"] = pageSourceValue
            }
            if let epsonSizeValue {
                options["EPIJ_Size"] = epsonSizeValue
            }

            return PrinterMediaSize(
                ippKeyword: size.ippKeyword,
                xDimension: size.xDimension,
                yDimension: size.yDimension,
                bottomMargin: size.bottomMargin,
                leftMargin: size.leftMargin,
                rightMargin: size.rightMargin,
                topMargin: size.topMargin,
                displayName: decodedPPDLabel(pageSize.displayName),
                cupsOptions: options,
                isBorderless: pageSize.isBorderless
            )
        }
    }

    private static func ppdPageSizes(_ ppdContents: String) -> [PPDPageSize] {
        let prefix = "*PageSize "
        return ppdContents.split(separator: "\n").compactMap { rawLine in
            let line = String(rawLine)
            guard line.hasPrefix(prefix),
                  let slash = line.firstIndex(of: "/"),
                  let colon = line[slash...].firstIndex(of: ":"),
                  let dimensionsStart = line.range(of: "/PageSize[")?.upperBound,
                  let dimensionsEnd = line[dimensionsStart...].firstIndex(of: "]") else {
                return nil
            }
            let value = line[line.index(line.startIndex, offsetBy: prefix.count)..<slash]
                .trimmingCharacters(in: .whitespaces)
            let displayName = String(line[line.index(after: slash)..<colon])
            let dimensions = line[dimensionsStart..<dimensionsEnd]
                .split(separator: " ", omittingEmptySubsequences: true)
                .compactMap { Double($0) }
            guard dimensions.count == 2 else { return nil }
            return PPDPageSize(
                value: value,
                displayName: displayName,
                xDimension: Int((dimensions[0] * 2540 / 72).rounded()),
                yDimension: Int((dimensions[1] * 2540 / 72).rounded()),
                isBorderless: displayName.localizedCaseInsensitiveContains("borderless")
                    || value.localizedCaseInsensitiveContains("NMgn")
            )
        }
    }

    private static func normalizedSizeLabel(_ value: String) -> String {
        decodedPPDLabel(value)
            .replacingOccurrences(of: "(Borderless)", with: "", options: .caseInsensitive)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func decodedPPDLabel(_ value: String) -> String {
        var result = value
        let replacements = ["<2E>": ".", "<3A>": ":", "<2F>": "/"]
        for (encoded, decoded) in replacements {
            result = result.replacingOccurrences(of: encoded, with: decoded)
        }
        return result
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

    private static func isPhotoMediaKeyword(_ keyword: String) -> Bool {
        keyword.hasPrefix("photographic-") || keyword == "stationery-coated" || keyword == "labels"
    }

    private static func isMediaTypeOption(_ option: PrinterOption) -> Bool {
        let key = option.key.lowercased()
        let displayName = option.displayName.lowercased()
        return key == "mediatype"
            || key.hasSuffix("_medi")
            || displayName.contains("media type")
            || displayName.contains("paper type")
    }

    private static func isThickPaperOption(_ option: PrinterOption) -> Bool {
        option.key == "EPIJ_PGEx"
            || option.displayName.localizedCaseInsensitiveContains("thick paper")
    }

    private static func enabledValue(for option: PrinterOption, in ppdContents: String) -> String? {
        let labels = choiceLabels(forOptionKey: option.key, in: ppdContents)
        return option.values.first(where: { choice in
            let label = labels[choice.value]?.lowercased() ?? ""
            return label == "on"
                || label == "enabled"
                || ["1", "on", "true", "yes"].contains(choice.value.lowercased())
        })?.value
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
