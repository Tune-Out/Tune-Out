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
    public let player = AVPlayer()

    public var playerState: PlayerState = .stopped

    public enum PlayerState {
        case stopped
        case playing
        case paused
    }

    public var curentTrackTitle: String? = nil
    private static var audioSessionActivated = false

    internal let db = try! DatabaseManager(url: URL.applicationSupportDirectory.appendingPathComponent("tuneout.sqlite"))
    /// Any changes to the database will incremenet this counter via the update hook;
    /// We use this for views to re-execute any queries performed in a `withDatabase` block.
    private var databaseChanges = Int64(0)

    // TODO: enable setting hidebroken from user preference
    public let queryParams = QueryParams(order: nil, reverse: nil, hidebroken: true, offset: nil, limit: nil)

    //@available(*, deprecated, message: "TODO: replace with DatabaseManager collection")
    public var favorites: [APIStationInfo] = loadFavorites() {
        didSet { saveFavorites() }
    }

    //@available(*, deprecated, message: "TODO: replace with DatabaseManager collection")
    public var nowPlaying: APIStationInfo? = loadNowPlaying().first {
        didSet { saveNowPlaying() }
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
            logger.debug("tryAction: \(actionTitle)")
            return try block(db)
        } catch {
            logger.error("tryAction: error \(actionTitle): \(error)")
            return nil
        }
    }

    /// Configure the app for playback in the background
    func activateAudioSession() {
        #if canImport(MediaPlayer)
        do {
            // https://developer.apple.com/documentation/AVFoundation/configuring-your-app-for-media-playback#Configure-the-audio-session
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            logger.error("error configuring AVAudioSession: \(error)")
        }
        #endif
    }

    func setupRemoteCommands() {
        #if canImport(MediaPlayer)
        // self.player.observe(\.currentItem) { player, change in }

        MPRemoteCommandCenter.shared().playCommand.isEnabled = true
        MPRemoteCommandCenter.shared().playCommand.addTarget { [unowned self] event in
            logger.info("playCommand")
            self.play()
            return MPRemoteCommandHandlerStatus.success
        }

        MPRemoteCommandCenter.shared().pauseCommand.isEnabled = true
        MPRemoteCommandCenter.shared().pauseCommand.addTarget { [unowned self] event in
            logger.info("pauseCommand")
            self.pause()
            return MPRemoteCommandHandlerStatus.success
        }

        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = true
        MPRemoteCommandCenter.shared().nextTrackCommand.addTarget { [unowned self] event in
            logger.info("nextTrackCommand")
            return self.nextItem() ? .success : .commandFailed
        }

        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = true
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
    public func clear() {
        favorites.removeAll()
    }

    /// Returns true if the given station is in the favorites list
    public func isFavorite(_ station: APIStationInfo) -> Bool {
        favorites.first { $0.id == station.id } != nil
    }

    /// Removes the given station from the favorites list
    public func unfavorite(_ station: APIStationInfo) {
        favorites = favorites.filter { $0.id != station.id }
        do {
            if let stationID = station.stationuuid,
               let existingStation = try db.fetchStation(stationuuid: stationID) {
                try db.removeStation(existingStation, fromCollection: db.favoritesCollection)
            }
        } catch {
            print("### error unfavorite: \(error)")
        }
    }

    /// Adds the given station to the favorites list
    public func favorite(_ station: APIStationInfo) {
        if favorites.contains(station) {
            unfavorite(station)
        }
        favorites.append(station)

        do {
            let storedStation = try db.saveStation(StoredStationInfo(info: station))
            try db.addStation(storedStation, toCollection: db.favoritesCollection)
        } catch {
            print("### error favorite: \(error)")
        }
    }

    public func isPlaying(_ station: APIStationInfo) -> Bool {
        self.playerState == .playing && nowPlaying?.id == station.id
    }

    public func play(_ station: APIStationInfo? = nil) {
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

        self.nowPlaying = station

        let item = AVPlayerItem(url: url)
        configurePlayerListener(for: item)
        self.player.replaceCurrentItem(with: item)
        self.player.play()
        // TODO: we should instead be listening for player updates, so if the player is paused externally (e.g., using MPNowPlayingInfoCenter.default()), this property will be correctly updated
        self.playerState = .playing
        #if !os(Android)
        self.updateCurrentTrack(title: nil) // clear the current title until it comes up again; disabled because Android's MediaPlayer doesn't re-update this when you pause then play the same station again
        #endif
    }

    public func pause() {
        logger.info("pause")
        self.player.pause()
        self.playerState = .paused
    }

    @discardableResult public func nextItem() -> Bool {
        logger.info("nextItem")
        //self.player.advanceToNextItem()
        return false // TODO
    }

    @discardableResult public func previousItem() -> Bool {
        logger.info("previousItem")
        return false // TODO
    }

    func updateCurrentTrack(title: String?) {
        self.curentTrackTitle = title

        #if canImport(MediaPlayer)
        let center = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = center.nowPlayingInfo ?? [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? self.nowPlaying?.name
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
                        if item.commonKey?.rawValue == "title" { // key names are like StreamTitle and StreamUrl
                            Task { @MainActor  in
                                let title = try await item.getStringValue()
                                logger.log("track title: \(title ?? "")")
                                self.updateCurrentTrack(title: title)
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

public protocol StationInfo {
    // name: Best Radio
    var name: String { get }

    var stationuuid: UUID? { get }

    // url: http://www.example.com/test.pls
    var url: String { get }

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
        logger.log("metadata updated: title: \(mediaMetadata.title) artist: \(mediaMetadata.artist) zlbum: \(mediaMetadata.albumTitle) zrtwork URI: \(mediaMetadata.artworkUri)")
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

/// Utilities for defaulting and persising the items in the list
extension ViewModel {

    private static let favoritesPath = URL.applicationSupportDirectory.appendingPathComponent("favorites.json")
    private static let nowPlayingPath = URL.applicationSupportDirectory.appendingPathComponent("playing.json")

    fileprivate static func loadNowPlaying() -> [APIStationInfo] {
        loadItems(savePath: nowPlayingPath)
    }

    fileprivate func saveNowPlaying() {
        if let nowPlaying {
            saveItems(savePath: Self.nowPlayingPath, items: [nowPlaying])
        }
    }

    fileprivate static func loadFavorites() -> [APIStationInfo] {
        loadItems(savePath: favoritesPath)
    }

    fileprivate func saveFavorites() {
        saveItems(savePath: Self.favoritesPath, items: favorites)
    }

    private static func loadItems(savePath: URL) -> [APIStationInfo] {
        do {
            let start = Date.now
            let data = try Data(contentsOf: savePath)
            defer {
                let end = Date.now
                logger.info("loaded \(data.count) bytes from \(savePath.path) in \(end.timeIntervalSince(start)) seconds")
            }
            return unique(try JSONDecoder().decode([APIStationInfo].self, from: data))
        } catch {
            // perhaps the first launch, or the data could not be read
            logger.warning("failed to load data from \(savePath), using defaultItems: \(error)")
            return []
        }
    }

    private func saveItems(savePath: URL, items: [APIStationInfo]) {
        do {
            let start = Date.now
            let data = try JSONEncoder().encode(items)
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try data.write(to: savePath)
            let end = Date.now
            logger.info("saved \(data.count) bytes to \(savePath.path) in \(end.timeIntervalSince(start)) seconds")
        } catch {
            logger.error("error saving data: \(error)")
        }
    }

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
