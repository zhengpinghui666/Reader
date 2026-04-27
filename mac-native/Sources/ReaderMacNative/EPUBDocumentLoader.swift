import Foundation
import ZIPFoundation

enum EPUBDocumentLoader {
    private struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let properties: String
    }

    static func load(from sourceURL: URL) throws -> EPUBReaderDocument {
        let extractionRoot = try prepareExtractionDirectory(for: sourceURL)
        try unzipEPUB(from: sourceURL, to: extractionRoot)

        let opfRelativePath = try locateOPFPath(in: extractionRoot)
        let opfURL = extractionRoot.appendingPathComponent(opfRelativePath).standardizedFileURL
        let opfDirectoryURL = opfURL.deletingLastPathComponent()
        let packageDocument = try parseXMLDocument(at: opfURL)

        let metadataTitle = try firstStringValue(
            forXPath: "//*[local-name()='metadata']//*[local-name()='title'][1]",
            in: packageDocument
        )?.trimmed

        let manifest = try parseManifest(in: packageDocument)
        let spine = try parseSpine(in: packageDocument, manifest: manifest, baseURL: opfDirectoryURL)
        let toc = try parseTOC(in: packageDocument, manifest: manifest, baseURL: opfDirectoryURL, spine: spine)

        guard !spine.isEmpty else {
            throw ReaderOpenError.invalidEPUB("spine is empty")
        }

        return EPUBReaderDocument(
            sourceURL: sourceURL,
            title: metadataTitle.flatMap { $0.isEmpty ? nil : $0 } ?? sourceURL.deletingPathExtension().lastPathComponent,
            extractionRootURL: extractionRoot,
            opfDirectoryURL: opfDirectoryURL,
            spine: spine,
            toc: toc
        )
    }

    private static func prepareExtractionDirectory(for sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("ReaderMacNativeEPUB", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let safeName = sourceURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let extractionRoot = tempRoot.appendingPathComponent("\(safeName)-\(Int(modified))", isDirectory: true)

        if fileManager.fileExists(atPath: extractionRoot.path) {
            try fileManager.removeItem(at: extractionRoot)
        }
        try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        return extractionRoot
    }

    private static func unzipEPUB(from sourceURL: URL, to destinationURL: URL) throws {
        guard let archive = Archive(url: sourceURL, accessMode: .read) else {
            throw ReaderOpenError.invalidEPUB("unable to open zip archive")
        }

        let fileManager = FileManager.default

        for entry in archive {
            let entryURL = destinationURL.appendingPathComponent(entry.path)
            if entry.type == .directory {
                try fileManager.createDirectory(at: entryURL, withIntermediateDirectories: true)
                continue
            }

            try fileManager.createDirectory(
                at: entryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = try archive.extract(entry, to: entryURL)
        }
    }

    private static func locateOPFPath(in extractionRoot: URL) throws -> String {
        let containerURL = extractionRoot
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml")

        let document = try parseXMLDocument(at: containerURL)
        guard let path = try firstStringValue(
            forXPath: "//*[local-name()='rootfile'][1]/@full-path",
            in: document
        )?.trimmed, !path.isEmpty else {
            throw ReaderOpenError.invalidEPUB("missing container rootfile")
        }

        return path
    }

    private static func parseManifest(in packageDocument: XMLDocument) throws -> [String: ManifestItem] {
        let nodes = try packageDocument.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")
        var manifest: [String: ManifestItem] = [:]

        for case let element as XMLElement in nodes {
            guard
                let id = element.attribute(forName: "id")?.stringValue?.trimmed,
                let href = element.attribute(forName: "href")?.stringValue?.trimmed,
                let mediaType = element.attribute(forName: "media-type")?.stringValue?.trimmed,
                !id.isEmpty,
                !href.isEmpty
            else {
                continue
            }

            let properties = element.attribute(forName: "properties")?.stringValue?.trimmed ?? ""
            manifest[id] = ManifestItem(
                id: id,
                href: href.removingPercentEncoding ?? href,
                mediaType: mediaType,
                properties: properties
            )
        }

        if manifest.isEmpty {
            throw ReaderOpenError.invalidEPUB("manifest is empty")
        }

        return manifest
    }

    private static func parseSpine(
        in packageDocument: XMLDocument,
        manifest: [String: ManifestItem],
        baseURL: URL
    ) throws -> [EPUBSpineItem] {
        let nodes = try packageDocument.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']")
        var spine: [EPUBSpineItem] = []

        for case let element as XMLElement in nodes {
            guard let idRef = element.attribute(forName: "idref")?.stringValue?.trimmed,
                  let item = manifest[idRef] else {
                continue
            }

            let fileURL = URL(fileURLWithPath: item.href, relativeTo: baseURL).standardizedFileURL
            spine.append(
                EPUBSpineItem(
                    id: item.id,
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    relativePath: item.href,
                    fileURL: fileURL
                )
            )
        }

        return spine
    }

    private static func parseTOC(
        in packageDocument: XMLDocument,
        manifest: [String: ManifestItem],
        baseURL: URL,
        spine: [EPUBSpineItem]
    ) throws -> [EPUBTOCItem] {
        if let navItem = manifest.values.first(where: { $0.properties.contains("nav") }) {
            let navURL = URL(fileURLWithPath: navItem.href, relativeTo: baseURL).standardizedFileURL
            let toc = try parseNavigationDocument(at: navURL, spine: spine)
            if !toc.isEmpty {
                return toc
            }
        }

        if let ncxID = try firstStringValue(forXPath: "//*[local-name()='spine'][1]/@toc", in: packageDocument),
           let ncxItem = manifest[ncxID] {
            let ncxURL = URL(fileURLWithPath: ncxItem.href, relativeTo: baseURL).standardizedFileURL
            let toc = try parseNCXDocument(at: ncxURL, spine: spine)
            if !toc.isEmpty {
                return toc
            }
        }

        if let ncxItem = manifest.values.first(where: { $0.mediaType.contains("ncx") }) {
            let ncxURL = URL(fileURLWithPath: ncxItem.href, relativeTo: baseURL).standardizedFileURL
            let toc = try parseNCXDocument(at: ncxURL, spine: spine)
            if !toc.isEmpty {
                return toc
            }
        }

        return spine.enumerated().map { index, item in
            EPUBTOCItem(
                id: "spine-\(index)",
                title: item.title,
                href: item.relativePath,
                spineIndex: index
            )
        }
    }

    private static func parseNavigationDocument(
        at url: URL,
        spine: [EPUBSpineItem]
    ) throws -> [EPUBTOCItem] {
        let document = try parseXMLDocument(at: url)
        let nodes = try document.nodes(forXPath: "//*[local-name()='nav']//*[local-name()='a']")
        var items: [EPUBTOCItem] = []
        var seen = Set<String>()

        for case let element as XMLElement in nodes {
            guard let href = element.attribute(forName: "href")?.stringValue?.trimmed,
                  !href.isEmpty else {
                continue
            }

            let title = element.stringValue?.trimmed ?? href
            let normalizedHref = href.removingPercentEncoding ?? href
            guard seen.insert(normalizedHref).inserted else {
                continue
            }

            let location = resolveLocation(for: normalizedHref, relativeTo: url, spine: spine)
            items.append(
                EPUBTOCItem(
                    id: "toc-\(items.count)",
                    title: title.isEmpty ? "目录 \(items.count + 1)" : title,
                    href: canonicalHref(for: normalizedHref, location: location, spine: spine),
                    spineIndex: location?.spineIndex
                )
            )
        }

        return items
    }

    private static func parseNCXDocument(
        at url: URL,
        spine: [EPUBSpineItem]
    ) throws -> [EPUBTOCItem] {
        let document = try parseXMLDocument(at: url)
        let nodes = try document.nodes(forXPath: "//*[local-name()='navPoint']")
        var items: [EPUBTOCItem] = []
        var seen = Set<String>()

        for case let element as XMLElement in nodes {
            let labelNode = try firstNode(
                forXPath: "./*[local-name()='navLabel']//*[local-name()='text'][1]",
                in: element
            )
            let contentNode = try firstNode(
                forXPath: "./*[local-name()='content'][1]/@src",
                in: element
            )

            guard let href = contentNode?.stringValue?.trimmed, !href.isEmpty else {
                continue
            }

            let normalizedHref = href.removingPercentEncoding ?? href
            guard seen.insert(normalizedHref).inserted else {
                continue
            }

            let title = labelNode?.stringValue?.trimmed ?? normalizedHref
            let location = resolveLocation(for: normalizedHref, relativeTo: url, spine: spine)

            items.append(
                EPUBTOCItem(
                    id: "toc-\(items.count)",
                    title: title.isEmpty ? "目录 \(items.count + 1)" : title,
                    href: canonicalHref(for: normalizedHref, location: location, spine: spine),
                    spineIndex: location?.spineIndex
                )
            )
        }

        return items
    }

    private static func resolveLocation(
        for href: String,
        relativeTo referenceURL: URL,
        spine: [EPUBSpineItem]
    ) -> EPUBLocation? {
        let decoded = href.removingPercentEncoding ?? href
        let parts = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let relativePath = parts.first.map(String.init) ?? decoded
        let anchor = parts.count > 1 ? String(parts[1]) : nil
        let absoluteURL: URL
        if relativePath.isEmpty {
            absoluteURL = referenceURL.standardizedFileURL
        } else {
            absoluteURL = URL(
                fileURLWithPath: relativePath,
                relativeTo: referenceURL.deletingLastPathComponent()
            ).standardizedFileURL
        }

        guard let index = spine.firstIndex(where: { $0.fileURL.standardizedFileURL.path == absoluteURL.path }) else {
            return nil
        }

        return EPUBLocation(fileURL: absoluteURL, spineIndex: index, anchor: anchor)
    }

    private static func canonicalHref(
        for sourceHref: String,
        location: EPUBLocation?,
        spine: [EPUBSpineItem]
    ) -> String {
        guard
            let location,
            spine.indices.contains(location.spineIndex)
        else {
            return sourceHref
        }

        var href = spine[location.spineIndex].relativePath
        if let anchor = location.anchor, !anchor.isEmpty {
            href += "#\(anchor)"
        }
        return href
    }

    private static func parseXMLDocument(at url: URL) throws -> XMLDocument {
        let data = try Data(contentsOf: url)
        return try XMLDocument(data: data, options: [.nodePreserveAll, .documentTidyXML])
    }

    private static func firstStringValue(
        forXPath xpath: String,
        in document: XMLDocument
    ) throws -> String? {
        try firstNode(forXPath: xpath, in: document)?.stringValue
    }

    private static func firstNode(
        forXPath xpath: String,
        in node: XMLNode
    ) throws -> XMLNode? {
        try node.nodes(forXPath: xpath).first as? XMLNode
    }
}
