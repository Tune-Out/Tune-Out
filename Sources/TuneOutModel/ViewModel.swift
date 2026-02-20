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

//    // adds has_extended_info, which is broken
//    public var hideUnverifiedStations: Bool = (!UserDefaults.standard.bool(forKey: "showUnverifiedStations")) {
//        didSet {
//            UserDefaults.standard.set(!hideUnverifiedStations, forKey: "showUnverifiedStations")
//        }
//    }

    public var hideBrokenStations: Bool = (!UserDefaults.standard.bool(forKey: "showBrokenStations")) {
        didSet {
            UserDefaults.standard.set(!hideBrokenStations, forKey: "showBrokenStations")
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

    /// The collection from which the current station is being played, or nil for recently played
    public var playbackCollection: StationCollection? = nil

    /// Snapshotted list of stations for next/previous navigation
    public var playbackStationList: [StoredStationInfo] = []

    internal let db = try! DatabaseManager(url: databaseFolder.appendingPathComponent("tuneout.sqlite"))
    /// Any changes to the database will incremenet this counter via the update hook;
    /// We use this for views to re-execute any queries performed in a `withDatabase` block.
    private var databaseChanges = Int64(0)

    /// Manually excluded stations for
    public var excludedStations: Set<String> = []

    public var queryParams: QueryParams {
        QueryParams(order: nil, reverse: false, hidebroken: hideBrokenStations, has_extended_info: nil, offset: 0, limit: 500)
    }

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

    /// The effective list of stations for next/previous navigation.
    /// Uses the snapshotted list if available, otherwise fetches from the effective collection.
    private var effectivePlaybackStations: [StoredStationInfo] {
        if !playbackStationList.isEmpty { return playbackStationList }
        let collection = playbackCollection ?? recentsCollection
        return withDatabase("playback stations") { db in
            try db.fetchStations(inCollection: collection).map(\.0)
        } ?? []
    }

    /// Index of the currently playing station in the playback list
    private var currentStationIndex: Int? {
        guard let current = nowPlaying else { return nil }
        return effectivePlaybackStations.firstIndex(where: { $0.stationuuid == current.stationuuid })
    }

    /// Whether there is a next station available in the current playback collection
    public var canGoNext: Bool {
        guard let index = currentStationIndex else { return false }
        return index + 1 < effectivePlaybackStations.count
    }

    /// Whether there is a previous station available in the current playback collection
    public var canGoPrevious: Bool {
        guard let index = currentStationIndex else { return false }
        return index > 0
    }

    public func play(_ station: StationInfo? = nil, fromCollection collection: StationCollection? = nil) {
        if station != nil {
            self.playbackCollection = collection
            // Snapshot the station list so next/prev isn't affected by recents reordering
            let effectiveCollection = collection ?? recentsCollection
            self.playbackStationList = withDatabase("snapshot playback stations") { db in
                try db.fetchStations(inCollection: effectiveCollection).map(\.0)
            } ?? []
        }
        playerController.play(station)
    }

    public func pause() {
        playerController.pause()
    }

    @discardableResult public func nextItem() -> Bool {
        let stations = effectivePlaybackStations
        guard let current = nowPlaying,
              let index = stations.firstIndex(where: { $0.stationuuid == current.stationuuid }),
              index + 1 < stations.count else { return false }
        playerController.play(stations[index + 1])
        return true
    }

    @discardableResult public func previousItem() -> Bool {
        let stations = effectivePlaybackStations
        guard let current = nowPlaying,
              let index = stations.firstIndex(where: { $0.stationuuid == current.stationuuid }),
              index > 0 else { return false }
        playerController.play(stations[index - 1])
        return true
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
