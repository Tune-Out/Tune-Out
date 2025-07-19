// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Observation
import SkipAV
import OSLog
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// A logger for the TuneOutModel module.
let logger: Logger = Logger(subsystem: "tune.out.model", category: "TuneOutModel")

/// The Observable ViewModel used by the application.
@Observable @MainActor public final class ViewModel {
    public let player: AVQueuePlayer = AVQueuePlayer()
    public var playing = false
    public var curentTrackTitle: String? = nil
    private static var audioSessionActivated = false

    // TODO: enable setting hidebroken from user preference
    public let queryParams = QueryParams(order: nil, reverse: nil, hidebroken: true, offset: nil, limit: nil)

    public var favorites: [StationInfo] = loadFavorites() {
        didSet { saveFavorites() }
    }

    public var nowPlaying: StationInfo? = loadNowPlaying().first {
        didSet { saveNowPlaying() }
    }

    public init() {
    }

    /// Configure the app for playback in the background
    func activateAudioSession() {
        #if os(iOS)
        do {
            // https://developer.apple.com/documentation/AVFoundation/configuring-your-app-for-media-playback#Configure-the-audio-session
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
        } catch {
            logger.error("error configuring AVAudioSession: \(error)")
        }
        #endif
    }

    public func clear() {
        favorites.removeAll()
    }

    public func isUpdated(_ item: StationInfo) -> Bool {
        item != favorites.first { i in
            i.id == item.id
        }
    }

    public func update(favorite: StationInfo) {
        favorites = favorites.map { item in
            item.id == favorite.id ? favorite : item
        }
    }
    
    /// Returns true if the given station is in the favorites list
    public func isFavorite(_ station: StationInfo) -> Bool {
        favorites.first { $0.id == station.id } != nil
    }

    /// Removes the given station from the favorites list
    public func unfavorite(_ station: StationInfo) {
        favorites = favorites.filter { $0.id != station.id }
    }

    /// Adds the given station to the favorites list
    public func favorite(_ station: StationInfo) {
        unfavorite(station)
        favorites.append(station)
    }

    public func isPlaying(_ station: StationInfo) -> Bool {
        self.playing && nowPlaying?.id == station.id
    }

    public func play(_ station: StationInfo) {
        // “You can activate the audio session at any time after setting its category, but it’s recommended to defer this call until your app begins audio playback. Deferring the call ensures that you don’t prematurely interrupt any other background audio that may be in progress.”
        if !Self.audioSessionActivated {
            Self.audioSessionActivated = true
            activateAudioSession()
        }

        self.nowPlaying = station
        guard let url = URL(string: station.url) else {
            logger.error("cannot parse station url: \(station.url)")
            return
        }
        let item = AVPlayerItem(url: url)
        configurePlayerListener(for: item)
        self.player.replaceCurrentItem(with: item)
        self.player.play()
        // TODO: we should instead be listening for player updates, so if the player is paused externally (e.g., using MPNowPlayingInfoCenter.default()), this property will be correctly updated
        self.playing = true
        //self.updateCurrentTrack(title: nil) // clear the current title until it comes up again; disabled because Android's MediaPlayer doesn't re-update this when you pause then play the same station again
    }

    public func pause() {
        self.player.pause()
        self.playing = false
    }

    func updateCurrentTrack(title: String?) {
        self.curentTrackTitle = title

        #if canImport(MediaPlayer)
        let center = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = center.nowPlayingInfo ?? [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        if let currentStationName = self.nowPlaying?.name {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = currentStationName
        }
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

    fileprivate static func loadNowPlaying() -> [StationInfo] {
        loadItems(savePath: nowPlayingPath)
    }

    fileprivate func saveNowPlaying() {
        if let nowPlaying {
            saveItems(savePath: Self.nowPlayingPath, items: [nowPlaying])
        }
    }

    fileprivate static func loadFavorites() -> [StationInfo] {
        loadItems(savePath: favoritesPath)
    }

    fileprivate func saveFavorites() {
        saveItems(savePath: Self.favoritesPath, items: favorites)
    }

    private static func loadItems(savePath: URL) -> [StationInfo] {
        do {
            let start = Date.now
            let data = try Data(contentsOf: savePath)
            defer {
                let end = Date.now
                logger.info("loaded \(data.count) bytes from \(savePath.path) in \(end.timeIntervalSince(start)) seconds")
            }
            return unique(try JSONDecoder().decode([StationInfo].self, from: data))
        } catch {
            // perhaps the first launch, or the data could not be read
            logger.warning("failed to load data from \(savePath), using defaultItems: \(error)")
            return []
        }
    }

    private func saveItems(savePath: URL, items: [StationInfo]) {
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
    public static func unique(_ stations: [StationInfo]) -> [StationInfo] {
        var uniqueStations: [StationInfo] = []
        #if SKIP
        uniqueStations.reserveCapacity(stations.count)
        #endif
        var ids = Set<StationInfo.ID>()
        for station in stations {
            if ids.insert(station.id).inserted {
                uniqueStations.append(station)
            }
        }
        return uniqueStations
    }

}
