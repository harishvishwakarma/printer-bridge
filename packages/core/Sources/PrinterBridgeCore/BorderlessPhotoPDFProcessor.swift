import CoreGraphics
import Foundation

enum BorderlessPhotoPDFProcessor {
    private struct PageGeometry {
        let page: CGPDFPage
        let mediaBox: CGRect
        let drawingTransform: CGAffineTransform
    }

    private static let maximumAnalysisDimension = 720
    private static let maximumDocumentByteCount = 100 * 1024 * 1024
    private static let maximumPageCount = 100
    private static let whiteThreshold: UInt8 = 252

    static func fillWhitePaddedPages(in documentData: Data) -> Data {
        guard
            documentData.starts(with: Data("%PDF".utf8)),
            documentData.count <= maximumDocumentByteCount,
            let provider = CGDataProvider(data: documentData as CFData),
            let document = CGPDFDocument(provider),
            document.numberOfPages > 0,
            document.numberOfPages <= maximumPageCount
        else {
            return documentData
        }

        let pages = (1...document.numberOfPages).compactMap(document.page(at:))
        guard pages.count == document.numberOfPages else { return documentData }
        let geometries = pages.compactMap(pageGeometry)
        guard geometries.count == pages.count else { return documentData }
        let contentRects = geometries.map(detectedContentRect)
        guard contentRects.contains(where: { $0 != nil }) else { return documentData }

        let outputData = NSMutableData()
        guard let consumer = CGDataConsumer(data: outputData as CFMutableData) else {
            return documentData
        }

        var firstMediaBox = geometries[0].mediaBox
        guard let context = CGContext(consumer: consumer, mediaBox: &firstMediaBox, nil) else {
            return documentData
        }

        for (geometry, detectedRect) in zip(geometries, contentRects) {
            var mediaBox = geometry.mediaBox
            guard mediaBox.width > 0, mediaBox.height > 0 else { return documentData }
            context.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            context.saveGState()
            context.clip(to: mediaBox)

            if let contentRect = detectedRect {
                let scale = max(mediaBox.width / contentRect.width, mediaBox.height / contentRect.height)
                context.translateBy(
                    x: mediaBox.midX - contentRect.midX * scale,
                    y: mediaBox.midY - contentRect.midY * scale
                )
                context.scaleBy(x: scale, y: scale)
            }

            context.concatenate(geometry.drawingTransform)
            context.drawPDFPage(geometry.page)
            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return outputData.isEmpty ? documentData : outputData as Data
    }

    private static func pageGeometry(for page: CGPDFPage) -> PageGeometry? {
        let sourceMediaBox = page.getBoxRect(.mediaBox)
        guard sourceMediaBox.width > 0, sourceMediaBox.height > 0 else { return nil }
        let normalizedRotation = ((page.rotationAngle % 360) + 360) % 360
        let swapsDimensions = normalizedRotation == 90 || normalizedRotation == 270
        let mediaBox = CGRect(
            x: 0,
            y: 0,
            width: swapsDimensions ? sourceMediaBox.height : sourceMediaBox.width,
            height: swapsDimensions ? sourceMediaBox.width : sourceMediaBox.height
        )
        let drawingTransform = page.getDrawingTransform(
            .mediaBox,
            rect: mediaBox,
            rotate: 0,
            preserveAspectRatio: false
        )
        return PageGeometry(page: page, mediaBox: mediaBox, drawingTransform: drawingTransform)
    }

    private static func detectedContentRect(for geometry: PageGeometry) -> CGRect? {
        let mediaBox = geometry.mediaBox

        let analysisScale = min(
            1,
            CGFloat(maximumAnalysisDimension) / max(mediaBox.width, mediaBox.height)
        )
        let width = max(1, Int((mediaBox.width * analysisScale).rounded()))
        let height = max(1, Int((mediaBox.height * analysisScale).rounded()))
        var pixels = [UInt8](repeating: 255, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let bitmap = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        bitmap.setFillColor(gray: 1, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bitmap.scaleBy(
            x: CGFloat(width) / mediaBox.width,
            y: CGFloat(height) / mediaBox.height
        )
        bitmap.concatenate(geometry.drawingTransform)
        bitmap.drawPDFPage(geometry.page)

        let left = contiguousWhiteColumns(in: pixels, width: width, height: height, fromLeadingEdge: true)
        let right = contiguousWhiteColumns(in: pixels, width: width, height: height, fromLeadingEdge: false)
        let bottom = contiguousWhiteRows(in: pixels, width: width, height: height, fromLeadingEdge: true)
        let top = contiguousWhiteRows(in: pixels, width: width, height: height, fromLeadingEdge: false)

        let horizontalPadding = symmetricPadding(low: left, high: right, dimension: width)
        let verticalPadding = symmetricPadding(low: bottom, high: top, dimension: height)
        guard horizontalPadding || verticalPadding else { return nil }

        let horizontalRatio = horizontalPadding ? CGFloat(left + right) / CGFloat(width) : 0
        let verticalRatio = verticalPadding ? CGFloat(bottom + top) / CGFloat(height) : 0
        let useHorizontalPadding = horizontalRatio >= verticalRatio
        let contentLeft = useHorizontalPadding ? left : 0
        let contentRight = useHorizontalPadding ? right : 0
        let contentBottom = useHorizontalPadding ? 0 : bottom
        let contentTop = useHorizontalPadding ? 0 : top
        let contentWidth = width - contentLeft - contentRight
        let contentHeight = height - contentBottom - contentTop
        guard contentWidth > 0, contentHeight > 0 else { return nil }

        return CGRect(
            x: mediaBox.minX + CGFloat(contentLeft) * mediaBox.width / CGFloat(width),
            y: mediaBox.minY + CGFloat(contentBottom) * mediaBox.height / CGFloat(height),
            width: CGFloat(contentWidth) * mediaBox.width / CGFloat(width),
            height: CGFloat(contentHeight) * mediaBox.height / CGFloat(height)
        )
    }

    private static func symmetricPadding(low: Int, high: Int, dimension: Int) -> Bool {
        let minimum = max(2, Int((CGFloat(dimension) * 0.005).rounded(.up)))
        let tolerance = max(2, Int((CGFloat(dimension) * 0.01).rounded(.up)))
        return low >= minimum
            && high >= minimum
            && abs(low - high) <= tolerance
            && low + high < dimension / 2
    }

    private static func contiguousWhiteColumns(
        in pixels: [UInt8],
        width: Int,
        height: Int,
        fromLeadingEdge: Bool
    ) -> Int {
        var count = 0
        for offset in 0..<width {
            let x = fromLeadingEdge ? offset : width - 1 - offset
            guard (0..<height).allSatisfy({ pixels[$0 * width + x] >= whiteThreshold }) else {
                break
            }
            count += 1
        }
        return count
    }

    private static func contiguousWhiteRows(
        in pixels: [UInt8],
        width: Int,
        height: Int,
        fromLeadingEdge: Bool
    ) -> Int {
        var count = 0
        for offset in 0..<height {
            let y = fromLeadingEdge ? offset : height - 1 - offset
            let rowStart = y * width
            guard (0..<width).allSatisfy({ pixels[rowStart + $0] >= whiteThreshold }) else {
                break
            }
            count += 1
        }
        return count
    }
}
