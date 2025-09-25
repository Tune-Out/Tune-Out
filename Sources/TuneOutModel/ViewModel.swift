// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Observation
import SkipAV
import SkipSQL
import OSLog

/// A logger for the TuneOutModel module.
let logger: Logger = Logger(subsystem: "tune.out.model", category: "TuneOutModel")

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

/// The Observable ViewModel used by the application.
@Observable @MainActor public final class ViewModel {
    public var tab: ContentTab = (UserDefaults.standard.string(forKey: "selectedTab").flatMap({ ContentTab(rawValue: $0) })) ?? ContentTab.browse {
        didSet {
            UserDefaults.standard.set(tab.rawValue, forKey: "selectedTab")
        }
    }

    private var playerController: PlayerController!

    public var playerState: PlayerState = .stopped
    public enum PlayerState {
        case stopped
        case playing
        case paused
    }

    public var browseNavigationPath: [NavPath] = [] {
        didSet {
            logger.log("browseNavigationPath: \(self.browseNavigationPath)")
        }
    }

    public var collectionsNavigationPath: [NavPath] = [] {
        didSet {
            logger.log("collectionsNavigationPath: \(self.collectionsNavigationPath)")
        }
    }

    public var curentTrackTitle: String? = nil
    public var currentTrackArtwork: URL? = nil

    internal let db = try! DatabaseManager(url: databaseFolder.appendingPathComponent("tuneout.sqlite"))
    /// Any changes to the database will incremenet this counter via the update hook;
    /// We use this for views to re-execute any queries performed in a `withDatabase` block.
    private var databaseChanges = Int64(0)

    // TODO: enable setting hidebroken from user preference
    public let queryParams = QueryParams(order: nil, reverse: nil, hidebroken: true, offset: nil, limit: nil)

    public var nowPlaying: StoredStationInfo? {
        withDatabase("nowPlaying") { db in
            try db.fetchStations(inCollection: self.recentsCollection).first?.0
        } ?? nil
    }

    /// The folder where the database is to be stored
    ///
    /// Creates the given file URL if it does not already exist
    static var databaseFolder: URL {
        get throws {
            // note that the `applicationSupportDirectory` ()
            let dir = URL.applicationSupportDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
    }

    public init() {
        self.playerController = PlayerController(viewModel: self)

        // watch the database for any changes and increment the databaseChanges counter whenever
        // something is updated, which will cause anything in a `trackingQuery` block
        // to be re-executed
        db.ctx.onUpdate(hook: { action, rowid, dbname, tblname in
            logger.log("onUpdate: \(action.description) rowid=\(rowid) tblname=\(tblname)")
            self.databaseChanges += 1
        })
    }

    @discardableResult public func withDatabase<T>(_ actionTitle: String, block: (DatabaseManager) throws -> T) -> T? {
        do {
            // access the changes counter so we re-execute this block when it changes
            let changes = self.databaseChanges
            let _ = changes
            logger.debug("tryAction: \(actionTitle) (databaseChanges=\(changes))")
            return try block(db)
        } catch {
            logger.error("tryAction: error \(actionTitle): \(error)")
            return nil
        }
    }

    public var favoritesCollection: StationCollection {
        get {
            try! db.fetchCollections(standard: true).first { collection in
                collection.name == StationCollection.favoritesCollectionName
            }!
        }
    }

    public var recentsCollection: StationCollection {
        get {
            try! db.fetchCollections(standard: true).first { collection in
                collection.name == StationCollection.recentsCollectionName
            }!
        }
    }

    public var standardCollections: [StationCollection] {
        withDatabase("standardCollections") { db in
            try db.fetchCollections(standard: true)
        } ?? []
    }

    public var customCollections: [StationCollection] {
        withDatabase("customCollections") { db in
            try db.fetchCollections(standard: false)
        } ?? []
    }

    public var collectionCounts: [(StationCollection, Int)] {
        withDatabase("collectionCounts") { db in
            try db.fetchCollectionCounts()
        } ?? []
    }

    /// Returns whether a new collection name is valid
    public func isValidCollectionName(_ name: String) -> Bool {
        !name.isEmpty && (try? db.fetchCollection(named: name, create: false)) == nil
    }

    /// Returns whether a new station name is valid
    public func isValidStationName(_ name: String) -> Bool {
        !name.isEmpty
    }

    /// Returns whether a new station URL is valid
    public func isValidStationURL(_ urlString: String) -> Bool {
        if urlString.isEmpty {
            return false
        }

        guard let url = URL(string: urlString) else {
            return false
        }

        if url.scheme != "http" && url.scheme != "https" {
            return false
        }

        return true
    }

    public func addStation(_ station: StationInfo, to collection: StationCollection) throws {
        let storedStation = try db.saveStation(StoredStationInfo.create(from: station))
        try db.addStation(storedStation, toCollection: collection)
    }

    func addRecentStation(_ station: StationInfo) {
        // add the station to the recents collection, which sets it as the `nowPlaying` station
        try? addStation(station, to: db.recentsCollection) // TODO: trim recents down to size
    }

    public func isPlaying(_ station: StationInfo) -> Bool {
        self.playerState == .playing && nowPlaying?.stationuuid == station.stationuuid
    }

    public func play(_ station: StationInfo? = nil) {
        playerController.play(station)
    }

    public func pause() {
        playerController.pause()
    }

    @discardableResult public func nextItem() -> Bool {
        playerController.nextItem()
    }

    @discardableResult public func previousItem() -> Bool {
        playerController.previousItem()
    }
}

public enum ContentTab: String, Hashable {
    case browse, collections, nowPlaying, search, settings
}

/// The navigation path for various tabs in the app
public enum NavPath : Hashable {
    case stationQuery(StationQuery)
    case apiStationInfo(APIStationInfo)
    case storedStationInfo(StoredStationInfo)
    case stationCollection(StationCollection)
    case browseStationMode(BrowseStationMode)
}

public enum BrowseStationMode: String, Hashable, Codable {
    //case languages // languages are not normalized and are full of garbage
    case countries
    case tags
}

public struct StationQuery: Hashable, Codable {
    public var title: String
    public var params: StationQueryParams
    public var sortOption: StationSortOption

    public init(title: String, params: StationQueryParams = StationQueryParams(), sortOption: StationSortOption = .popularity) {
        self.title = title
        self.params = params
        self.sortOption = sortOption
    }
}

public enum StationSortOption: String, Identifiable, Hashable, CaseIterable, Codable {
    case name
    case popularity
    case trend
    case random

    public var id: StationSortOption {
        self
    }
}

/// Implemented by both `StoredStationInfo` and `APIStationInfo`
public protocol StationInfo {
    // name: Best Radio
    var name: String { get }

    var stationuuid: UUID? { get }

    // url: http://www.example.com/test.pls
    var url: String { get }

    // url: http://www.example.com/test.pls
    var homepage: String? { get }

    // favicon: https://www.example.com/icon.png
    var favicon: String? { get }

    // tags: jazz,pop,rock,indie
    var tags: String? { get }

    // countrycode: US
    var countrycode: String? { get }
}
