// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Observation
import SkipAV
import SkipSQL
import OSLog
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// A logger for the TuneOutModel module.
let logger: Logger = Logger(subsystem: "tune.out.model", category: "TuneOutModel")

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

/// The Observable ViewModel used by the application.
@Observable @MainActor public final class ViewModel {
    public var tab = ContentTab.browse

    public let player = AVPlayer()

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
    private static var audioSessionActivated = false

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
        // watch the database for any changes and increment the databaseChanges counter whenever
        // something is updated, which will cause anything in a `trackingQuery` block
        // to be re-executed
        db.ctx.onUpdate(hook: { action, rowid, dbname, tblname in
            logger.log("onUpdate: \(action.description) rowid=\(rowid) tblname=\(tblname)")
            self.databaseChanges += 1
        })

        setupRemoteCommands()
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

    /// Configure the app for playback in the background
    func activateAudioSession() {
        #if canImport(MediaPlayer)
        #if !os(macOS) // AVAudioSession not available on macOS
        do {
            // https://developer.apple.com/documentation/AVFoundation/configuring-your-app-for-media-playback#Configure-the-audio-session
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            logger.error("error configuring AVAudioSession: \(error)")
        }
        #endif
        #endif
    }

    func updateRemoteCommands() {
        #if canImport(MediaPlayer)
        MPRemoteCommandCenter.shared().playCommand.isEnabled = true
        MPRemoteCommandCenter.shared().pauseCommand.isEnabled = true
        // TODO: enable/disable next track based on whether the current collection has multiple entries
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = true
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = true
        #endif
    }

    func setupRemoteCommands() {
        #if canImport(MediaPlayer)
        // self.player.observe(\.currentItem) { player, change in }

        updateRemoteCommands()

        MPRemoteCommandCenter.shared().playCommand.addTarget { [unowned self] event in
            logger.info("playCommand")
            self.play()
            return MPRemoteCommandHandlerStatus.success
        }

        MPRemoteCommandCenter.shared().pauseCommand.addTarget { [unowned self] event in
            logger.info("pauseCommand")
            self.pause()
            return MPRemoteCommandHandlerStatus.success
        }

        MPRemoteCommandCenter.shared().nextTrackCommand.addTarget { [unowned self] event in
            logger.info("nextTrackCommand")
            return self.nextItem() ? .success : .commandFailed
        }

        MPRemoteCommandCenter.shared().previousTrackCommand.addTarget { [unowned self] event in
            logger.info("previousTrackCommand")
            return self.previousItem() ? .success : .commandFailed
        }

        // TODO: handle starring the current track as a favorite
        //MPRemoteCommandCenter.shared().likeCommand.isEnabled = true
        //MPRemoteCommandCenter.shared().likeCommand.addTarget { [unowned self] event in
        //    logger.info("likeCommand")
        //    return MPRemoteCommandHandlerStatus.commandFailed // TODO
        //}
        #endif
    }

    /// Returns whether a new collection name is valid
    public func isValidCollectionName(_ name: String) -> Bool {
        !name.isEmpty && (try? db.fetchCollection(named: name, create: false)) == nil
    }

    public func addStation(_ station: StationInfo, to collection: StationCollection) throws {
        let storedStation = try db.saveStation(StoredStationInfo.create(from: station))
        try db.addStation(storedStation, toCollection: collection)
    }

    public func isPlaying(_ station: StationInfo) -> Bool {
        self.playerState == .playing && nowPlaying?.stationuuid == station.stationuuid
    }

    public func play(_ station: StationInfo? = nil) {
        guard let station = station ?? self.nowPlaying else {
            logger.warning("no current station")
            return
        }

        logger.info("play: \(station.url)")

        guard let url = URL(string: station.url) else {
            logger.error("cannot parse station url: \(station.url)")
            return
        }

        // “You can activate the audio session at any time after setting its category, but it’s recommended to defer this call until your app begins audio playback. Deferring the call ensures that you don’t prematurely interrupt any other background audio that may be in progress.”
        if !Self.audioSessionActivated {
            Self.audioSessionActivated = true
            activateAudioSession()
        }

        // add the station to the recents collection, which sets it as the `nowPlaying` station
        try? self.addStation(station, to: db.recentsCollection) // TODO: trim recents down to size

        let item = AVPlayerItem(url: url)
        configurePlayerListener(for: item)
        self.player.replaceCurrentItem(with: item)
        self.player.play()
        // TODO: we should instead be listening for player updates, so if the player is paused externally (e.g., using MPNowPlayingInfoCenter.default()), this property will be correctly updated
        self.playerState = .playing
        updateRemoteCommands()
        #if !os(Android)
        self.updateCurrentTrack(title: nil) // clear the current title until it comes up again; disabled because Android's MediaPlayer doesn't re-update this when you pause then play the same station again
        #endif
    }

    public func pause() {
        logger.info("pause")
        self.player.pause()
        self.playerState = .paused
        updateRemoteCommands()
    }

    @discardableResult public func nextItem() -> Bool {
        logger.info("nextItem")
        //self.player.advanceToNextItem()
        updateRemoteCommands()
        return false // TODO
    }

    @discardableResult public func previousItem() -> Bool {
        logger.info("previousItem")
        updateRemoteCommands()
        return false // TODO
    }

    func updateCurrentTrack(title: String?) {
        self.curentTrackTitle = title
        // clear any artwork until we get an update
        self.currentTrackArtwork = nil

        #if canImport(MediaPlayer)
        let center = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = center.nowPlayingInfo ?? [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? self.nowPlaying?.name
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true as AnyObject
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue as NSNumber

        // TODO: Update queue list with the current collection list
        //nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.count as AnyObject
        //nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = 1 as AnyObject

        if let currentStationName = self.nowPlaying?.name {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = currentStationName
        }
        //nowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = metadata.assetURL
        //nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = metadata.mediaType.rawValue
        //nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = metadata.isLiveStream
        //nowPlayingInfo[MPMediaItemPropertyTitle] = metadata.title
        //nowPlayingInfo[MPMediaItemPropertyArtist] = metadata.artist
        //nowPlayingInfo[MPMediaItemPropertyArtwork] = metadata.artwork
        //nowPlayingInfo[MPMediaItemPropertyAlbumArtist] = metadata.albumArtist
        //nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = metadata.albumTitle
        center.nowPlayingInfo = nowPlayingInfo
        #endif
    }

    /// Platform-specific implementation to set up a listener for media metadata changes (e.g., changes in the current track title) in the player for the specific item.
    private func configurePlayerListener(for item: AVPlayerItem) {
        #if SKIP
        // the androidx.media3.common.Player.Listener is set on the player itself, so only set it once…
        if self.playerListener == nil {
            let listener = PlayerListener { metadata in
                self.updateCurrentTrack(title: metadata.title?.description)
                if let artworkUri = metadata.artworkUri {
                    self.currentTrackArtwork = URL(string: artworkUri.toString())
                }
            }
            self.playerListener = listener
            player.mediaPlayer.addListener(listener)
        }
        #else
        // …whereas the listener for an AVPlayer is defined on a per-AVPlayerItem basis
        let listener = OutputPushDelegate { groups in
            for group in groups {
                for item in group.items {
                    if let key = item.key {
                        logger.log("item key: \(key.description) common: \(item.commonKey?.rawValue ?? "none")")
                        // FIXME: some streams encode a bunch of information in the title, like:
                        // "<AVMutableMetadataItem: 0x600000302560, identifier=icy/StreamTitle, keySpace=icy, key class = __NSCFConstantString, key=StreamTitle, commonKey=title, extendedLanguageTag=(null), dataType=(null), time={1341376/24000 = 55.891}, duration={1/24000 = 0.000}, startDate=(null), extras={\n}, value class=__NSCFString, value=Georgia Brown - text=\"As Long As He Needs Me\" song_spot=\"M\" spotInstanceId=\"-1\" length=\"00:04:07\" MediaBaseId=\"\" TAID=\"0\" TPID=\"648410\" cartcutId=\"422206\" amgArtworkURL=\"https://i.iheart.com/v3/catalog/track/648410?ops=fit(400,400),format(%22png%22)\" spEventID=\"59365933-b66b-f011-836a-0242c86e7629\" >"

                        if item.commonKey?.rawValue == "title" { // key names are like StreamTitle and StreamUrl
                            Task { @MainActor  in
                                let title = try await item.getStringValue()
                                logger.log("track title: \(title ?? "")")
                                self.updateCurrentTrack(title: title)
                            }
                        }

                        // artwork can come in like:
                        // "<AVMutableMetadataItem: 0x60000022cfa0, identifier=icy/StreamUrl, keySpace=icy, key class = __NSCFConstantString, key=StreamUrl, commonKey=(null), extendedLanguageTag=(null), dataType=(null), time={15296/44100 = 0.347}, duration={1/44100 = 0.000}, startDate=(null), extras={\n}, value class=__NSCFString, value=http://img.radioparadise.com/covers/l/18541_48f6fcd3-566e-4124-aaa8-f7e7db864f62.jpg>"
                        // "<AVMutableMetadataItem: 0x60000022eca0, identifier=icy/StreamUrl, keySpace=icy, key class = __NSCFConstantString, key=StreamUrl, commonKey=(null), extendedLanguageTag=(null), dataType=(null), time={123264/44100 = 2.795}, duration={1/44100 = 0.000}, startDate=(null), extras={\n}, value class=__NSCFString, value=https://somafm.com/logos/512/groovesalad512.png>"
                        //
                        // but other "StreamUrl" metadata isn't necessarily a URL to artwork, like:
                        //
                        // "<AVMutableMetadataItem: 0x60000022ccc0, identifier=icy/StreamUrl, keySpace=icy, key class = __NSCFConstantString, key=StreamUrl, commonKey=(null), extendedLanguageTag=(null), dataType=(null), time={2304/44100 = 0.052}, duration={1/44100 = 0.000}, startDate=(null), extras={\n}, value class=__NSCFString, value=MM-CLA-112563.mp3>"
                        // "<AVMutableMetadataItem: 0x600000331fc0, identifier=icy/StreamUrl, keySpace=icy, key class = __NSCFConstantString, key=StreamUrl, commonKey=(null), extendedLanguageTag=(null), dataType=(null), time={43776/44100 = 0.993}, duration={1/44100 = 0.000}, startDate=(null), extras={\n}, value class=__NSCFString, value=http://www.miamibeachradio.com>"
                        //
                        // also artwork can come in like:
                        // "<AVMutableMetadataItem: 0x600000322a60, identifier=id3/TXXX, keySpace=org.id3, key class = NSTaggedPointerString, key=TXXX, commonKey=(null), extendedLanguageTag=(null), dataType=(null), time={32316480/360000 = 89.768}, duration={1/360000 = 0.000}, startDate=(null), extras={\n    info = URL;\n}, value class=__NSCFString, value=song_spot=\"M\" spotInstanceId=\"-1\" length=\"00:01:44\" MediaBaseId=\"1181648\" TAID=\"0\" TPID=\"82989618\" cartcutId=\"735438\" amgArtworkURL=\"http://image.iheart.com/SBMG2/Thumb_Content/Full_PC/SBMG/Dec09/121509/batch4/1919137/000/000/000/000/026/468/71/00000000000002646871-480x480_72dpi_RGB_100Q.jpg\" spEventID=\"a29b708c-2478-f011-836a-0242c86e7629\" >"
                        if item.key?.description == "StreamUrl" {
                            Task { @MainActor  in
                                let streamUrl = try await item.getStringValue()
                                logger.log("track streamUrl: \(streamUrl ?? "")")
                                // e.g.: http://img.radioparadise.com/covers/l/18951_f4537ecb-b795-45d4-ac6e-fb6dba939c12.jpg
                                if let streamUrl,
                                   (streamUrl.hasPrefix("http://") || streamUrl.hasPrefix("https://")),
                                   (streamUrl.hasSuffix("png") || streamUrl.hasSuffix("gif") || streamUrl.hasSuffix("jpg") || streamUrl.hasSuffix("jpeg")),
                                   let artworkURL = URL(string: streamUrl) {
                                    // looks like artwork URL: update the currently playing URL
                                    self.currentTrackArtwork = artworkURL
                                }
                            }
                        }
                    }
                }
            }
        }
        self.outputPushDelegate = listener // need to retain the listener or it will be cleared
        let output = AVPlayerItemMetadataOutput()
        output.setDelegate(listener, queue: .main)
        item.add(output)
        #endif
    }

    #if SKIP
    private var playerListener: PlayerListener? = nil
    #else
    // Strong reference to the player's push delegate, since it is stored weakly
    private var outputPushDelegate: AVPlayerItemMetadataOutputPushDelegate? = nil
    #endif
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


#if SKIP
final class PlayerListener: androidx.media3.common.Player.Listener {
    let metadataCallback: (androidx.media3.common.MediaMetadata) -> ()

    init(metadataCallback: (androidx.media3.common.MediaMetadata) -> ()) {
        self.metadataCallback = metadataCallback
    }

    override func onMediaItemTransition(mediaItem: androidx.media3.common.MediaItem?, reason: Int) {
        if let mediaItem {
            if let metadata = mediaItem.mediaMetadata {
                logger.log("track changed: \(metadata.title) artist: \(metadata.artist) album: \(metadata.albumTitle)")
                self.metadataCallback(metadata)
            }
        }
    }

    // Listen for metadata updates (important for streams)
    override func onMediaMetadataChanged(mediaMetadata: androidx.media3.common.MediaMetadata) {
        logger.log("metadata updated: title: \(mediaMetadata.title) artist: \(mediaMetadata.artist) albumTitle: \(mediaMetadata.artworkUri) zrtwork URI: \(mediaMetadata.artworkUri)")
        metadataCallback(mediaMetadata)
    }

    // Listen for playback state changes
    override func onPlaybackStateChanged(playbackState: Int) {
        switch playbackState {
        case androidx.media3.common.Player.STATE_BUFFERING: logger.log("media buffering...")
        case androidx.media3.common.Player.STATE_READY: logger.log("media ready to play")
        case androidx.media3.common.Player.STATE_ENDED: logger.log("media playback ended")
        }
    }

    // Listen for position updates
    override func onPositionDiscontinuity(oldPosition: androidx.media3.common.Player.PositionInfo, newPosition: androidx.media3.common.Player.PositionInfo, reason: Int) {
        // handle position changes
    }
}
#else
final class OutputPushDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate, @unchecked Sendable {
    let callback: ([AVTimedMetadataGroup]) -> ()

    init(callback: @escaping ([AVTimedMetadataGroup]) -> ()) {
        self.callback = callback
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        logger.debug("metadataOutput: \(output) track: \(track?.description ?? "none")")
        for group in groups {
            logger.debug("metadataOutput: group: \(group)")
        }
        self.callback(groups)
    }
}

extension AVMetadataItem {
    func getStringValue() async throws -> String? {
        let title = try await load(.value)
        return title?.description
    }
}
#endif

extension ViewModel {
    /// Ensure that no duplicate IDs exist in the list of stations, which will crash on Android with:
    /// `07-11 17:48:47.636 11894 11894 E AndroidRuntime: java.lang.IllegalArgumentException: Key "9617A958-0601-11E8-AE97-52543BE04C81" was already used. If you are using LazyColumn/Row please make sure you provide a unique key for each item.`
    public static func unique(_ stations: [APIStationInfo]) -> [APIStationInfo] {
        var uniqueStations: [APIStationInfo] = []
        #if !SKIP
        uniqueStations.reserveCapacity(stations.count)
        #endif
        var ids = Set<APIStationInfo.ID>()
        for station in stations {
            if ids.insert(station.id).inserted {
                uniqueStations.append(station)
            }
        }
        return uniqueStations
    }
}
