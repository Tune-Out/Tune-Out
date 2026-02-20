// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Observation
import SkipAV
import SkipSQL
import OSLog
#if canImport(MediaPlayer)
import MediaPlayer
#endif
#if SKIP
//import android.media.MediaMetadata
import androidx.core.content.ContextCompat
import android.content.ComponentName
import android.media.session.PlaybackState
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MediaMetadata
import androidx.media3.session.SessionToken
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
#endif


/// The `PlayerController` manages an `AVPlayer` and handles the platform-specific interactions
/// with the underlying media frameworks that are not yet supported directly by `SkipAV`.
@MainActor final class PlayerController {
    unowned let viewModel: ViewModel

    public var player = AVPlayer()

    #if SKIP
    internal var playerListener: PlayerListener? = nil
    #else
    // Strong reference to the player's push delegate, since it is stored weakly
    internal var outputPushDelegate: AVPlayerItemMetadataOutputPushDelegate? = nil
    #endif
    static var audioSessionActivated = false


    init(viewModel: ViewModel) {
        self.viewModel = viewModel
        setupRemoteCommands()
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
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = viewModel.canGoNext
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = viewModel.canGoPrevious
        #endif
    }

    func setupRemoteCommands() {
        logger.log("ViewModel.setupRemoteCommands")
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

        #if SKIP
        let ctx = ProcessInfo.processInfo.androidContext
        let sessionToken = SessionToken(ctx, ComponentName(ctx, PlayBackService.self.java))
        let controllerFuture = MediaController.Builder(ctx, sessionToken).buildAsync()
        controllerFuture.addListener({
            logger.log("PlayBackService: controllerFuture.addListener")
            let controller: MediaController = controllerFuture.get()

            // https://developer.android.com/media/media3/session/connect-to-media-app#use-controller : “MediaController implements the Player interface, so you can use the commands defined in the interface to control playback of the connected MediaSession.”
            // replace the stock AVPlayer with one that wraps the controller interface to the service player
            self.player = AVPlayer(player: controller)
        }, ContextCompat.getMainExecutor(ctx))


//        mediaSession.setFlags(Int(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS | MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS))
//
//        // Set callback for media controls
//        mediaSession.setCallback(MediaSessionCallback(viewModel: self))
//        mediaSession.isActive = true
        #endif
    }

    #if SKIP
    class MediaSessionCallback : MediaSession.Callback {
        private let viewModel: ViewModel

        init(viewModel: ViewModel) {
            self.viewModel = viewModel
        }

//        override func onPlay() {
//            // Handle play
//            viewModel.play()
//            //updatePlaybackState(PlaybackStateCompat.STATE_PLAYING)
//        }
//
//        override func onPause() {
//            // Handle pause
//            viewModel.pause()
//            //updatePlaybackState(PlaybackStateCompat.STATE_PAUSED)
//        }
//
//        override func onStop() {
//            // Handle stop
//            viewModel.pause()
//            //updatePlaybackState(PlaybackStateCompat.STATE_STOPPED)
//        }
    }
    #endif

    @MainActor public func play(_ station: StationInfo? = nil) {
        guard let station = station ?? viewModel.nowPlaying else {
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

        viewModel.addRecentStation(station)

        let item = AVPlayerItem(url: url)
        configurePlayerListener(for: item)
        self.player.replaceCurrentItem(with: item)
        self.player.play()
        // TODO: we should instead be listening for player updates, so if the player is paused externally (e.g., using MPNowPlayingInfoCenter.default()), this property will be correctly updated
        viewModel.playerState = .playing
        updateRemoteCommands()
        #if !os(Android)
        self.updateCurrentTrack(title: nil) // clear the current title until it comes up again; disabled because Android's MediaPlayer doesn't re-update this when you pause then play the same station again
        #endif
    }

    public func pause() {
        logger.info("pause")
        self.player.pause()
        viewModel.playerState = .paused
        updateRemoteCommands()
    }

    @discardableResult public func nextItem() -> Bool {
        logger.info("nextItem")
        let result = viewModel.nextItem()
        updateRemoteCommands()
        return result
    }

    @discardableResult public func previousItem() -> Bool {
        logger.info("previousItem")
        let result = viewModel.previousItem()
        updateRemoteCommands()
        return result
    }

    func updateCurrentTrack(title: String?) {
        viewModel.curentTrackTitle = title
        // clear any artwork until we get an update
        viewModel.currentTrackArtwork = nil

        #if canImport(MediaPlayer)
        let center = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = center.nowPlayingInfo ?? [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? viewModel.nowPlaying?.name
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true as AnyObject
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue as NSNumber

        // TODO: Update queue list with the current collection list
        //nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.count as AnyObject
        //nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = 1 as AnyObject

        if let currentStationName = viewModel.nowPlaying?.name {
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

        #if SKIP
        var metadata = MediaMetadata.Builder()
        //metadata = metadata.putString(MediaMetadata.METADATA_KEY_ARTIST, "Artist Name")
        //metadata = metadata.putString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI, "album art uri")
        //metadata = metadata.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, albumArtBitmap)

//        if let currentStationName = self.nowPlaying?.name {
//            metadata = metadata.putString(MediaMetadata.METADATA_KEY_TITLE, currentStationName)
//        }
//        mediaSession.setMetadata(metadata.build())
        #endif
    }

    /// Platform-specific implementation to set up a listener for media metadata changes (e.g., changes in the current track title) in the player for the specific item.
    private func configurePlayerListener(for item: AVPlayerItem) {
        #if SKIP
        // the Player.Listener is set on the player itself, so only set it once…
        if self.playerListener == nil {
            let listener = PlayerListener { metadata in
                self.updateCurrentTrack(title: metadata.title?.description)
                if let artworkUri = metadata.artworkUri {
                    viewModel.currentTrackArtwork = URL(string: artworkUri.toString())
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
                                    self.viewModel.currentTrackArtwork = artworkURL
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

}


#if SKIP
final class PlayerListener: Player.Listener {
    let metadataCallback: (MediaMetadata) -> ()

    init(metadataCallback: (MediaMetadata) -> ()) {
        self.metadataCallback = metadataCallback
    }

    override func onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
        if let mediaItem {
            if let metadata = mediaItem.mediaMetadata {
                logger.log("track changed: \(metadata.title) artist: \(metadata.artist) album: \(metadata.albumTitle)")
                self.metadataCallback(metadata)
            }
        }
    }

    // Listen for metadata updates (important for streams)
    override func onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
        logger.log("metadata updated: title: \(mediaMetadata.title) artist: \(mediaMetadata.artist) albumTitle: \(mediaMetadata.artworkUri) zrtwork URI: \(mediaMetadata.artworkUri)")
        metadataCallback(mediaMetadata)
    }

    // Listen for playback state changes
    override func onPlaybackStateChanged(playbackState: Int) {
        switch playbackState {
        case Player.STATE_BUFFERING: logger.log("media buffering...")
        case Player.STATE_READY: logger.log("media ready to play")
        case Player.STATE_ENDED: logger.log("media playback ended")
        }
    }

    // Listen for position updates
    override func onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
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

#if SKIP
/// This service name is referenced in the `AndroidManifest.xml`
public final class PlayBackService : MediaSessionService {
    private var mediaSession: MediaSession?

    public init() {
    }

    // FIXME: does not seem to ever be instantiated or called
    override func onCreate() {
        super.onCreate()
        logger.log("PlayBackService: onCreate")

        let player = ExoPlayer.Builder(self).build()
        mediaSession = MediaSession.Builder(self, player)
            .setId("Tune-Out") // session identifier
            .build()
    }

    override func onGetSession(controllerInfo: MediaSession.ControllerInfo) -> MediaSession? {
        logger.log("PlayBackService: onGetSession")
        return mediaSession
    }

    override func onDestroy() {
        logger.log("PlayBackService: onDestroy")
        // https://developer.android.com/media/media3/session/background-playback#service-lifecycle
        mediaSession?.run {
            player.release()
            release()
            mediaSession = nil
        }
        super.onDestroy()
    }
}
#endif
