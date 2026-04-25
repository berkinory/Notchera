import Foundation

struct BrewUpdateCheckResult: Equatable {
    let latestVersion: String
    let downloadURL: URL?

    var updateAvailable: Bool {
        latestVersion != (Bundle.main.releaseVersionNumber ?? "")
    }
}

enum BrewUpdateChecker {
    static func check() async throws -> BrewUpdateCheckResult {
        guard let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feedURLString)
        else {
            throw NSError(domain: "BrewUpdateChecker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update feed URL is missing."])
        }

        let (data, _) = try await URLSession.shared.data(from: feedURL)
        let parser = AppcastParser()
        return try parser.parse(data: data)
    }
}

private final class AppcastParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var insideFirstItem = false
    private var hasParsedFirstItem = false
    private var latestVersion = ""
    private var enclosureURL: URL?

    func parse(data: Data) throws -> BrewUpdateCheckResult {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? NSError(domain: "BrewUpdateChecker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse update feed."])
        }

        guard !latestVersion.isEmpty else {
            throw NSError(domain: "BrewUpdateChecker", code: 3, userInfo: [NSLocalizedDescriptionKey: "No release version found in update feed."])
        }

        return BrewUpdateCheckResult(latestVersion: latestVersion, downloadURL: enclosureURL)
    }

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "item", !hasParsedFirstItem {
            insideFirstItem = true
            return
        }

        guard insideFirstItem else { return }

        if elementName == "enclosure", let rawURL = attributeDict["url"] {
            enclosureURL = URL(string: rawURL)
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard insideFirstItem else { return }
        if currentElement == "sparkle:shortVersionString" {
            latestVersion += string
        }
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        if elementName == "item", insideFirstItem {
            insideFirstItem = false
            hasParsedFirstItem = true
            latestVersion = latestVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        currentElement = ""
    }
}
