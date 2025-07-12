// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Observation
import OSLog

/// A logger for the TuneOutModel module.
let logger: Logger = Logger(subsystem: "tune.out.model", category: "TuneOutModel")

public typealias Item = StationInfo

/// The Observable ViewModel used by the application.
@Observable public class ViewModel {
    // TODO: enable setting hidebroken from user preference
    public let queryParams = QueryParams(order: nil, reverse: nil, hidebroken: true, offset: nil, limit: nil)

    public var items: [Item] = loadItems() {
        didSet { saveItems() }
    }

    public init() {
    }

    public func clear() {
        items.removeAll()
    }

    public func isUpdated(_ item: Item) -> Bool {
        item != items.first { i in
            i.id == item.id
        }
    }

    public func save(item: Item) {
        items = items.map { i in
            i.id == item.id ? item : i
        }
    }

    public func favorite(_ station: StationInfo) {
        items.append(station)
    }

    public func play(_ station: StationInfo) {

    }

    public func pause(_ station: StationInfo) {

    }
}

/// Utilities for defaulting and persising the items in the list
extension ViewModel {
    private static let savePath = URL.applicationSupportDirectory.appendingPathComponent("appdata.json")

    fileprivate static func loadItems() -> [Item] {
        do {
            let start = Date.now
            let data = try Data(contentsOf: savePath)
            defer {
                let end = Date.now
                logger.info("loaded \(data.count) bytes from \(Self.savePath.path) in \(end.timeIntervalSince(start)) seconds")
            }
            return try JSONDecoder().decode([Item].self, from: data)
        } catch {
            // perhaps the first launch, or the data could not be read
            logger.warning("failed to load data from \(Self.savePath), using defaultItems: \(error)")
            return []
        }
    }

    fileprivate func saveItems() {
        do {
            let start = Date.now
            let data = try JSONEncoder().encode(items)
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try data.write(to: Self.savePath)
            let end = Date.now
            logger.info("saved \(data.count) bytes to \(Self.savePath.path) in \(end.timeIntervalSince(start)) seconds")
        } catch {
            logger.error("error saving data: \(error)")
        }
    }
}


