import Foundation
import MediaPlayer

struct PlayContext {
    let index: Int
    let name: String
    let playables: [AbstractPlayable]
    var isKeepIndexDuringShuffle: Bool = false
    
    init() {
        self.name = ""
        self.index = 0
        self.playables = []
    }
    
    init(containable: PlayableContainable) {
        self.name = containable.name
        self.index = 0
        self.playables = containable.playables
    }

    init(name: String, index: Int = 0, playables: [AbstractPlayable]) {
        self.name = name
        self.index = index
        self.playables = playables
    }

    func getActivePlayable() -> AbstractPlayable? {
        guard playables.count > 0, index < playables.count else { return nil }
        return playables[index]
    }
    
    func getWithShuffledIndex() -> PlayContext {
        guard !isKeepIndexDuringShuffle else { return self }
        return PlayContext(name: name, index: Int.random(in: 0...playables.count-1), playables: playables)
    }
}

protocol PlayerFacade {
    var prevQueue: [AbstractPlayable] { get }
    var userQueue: [AbstractPlayable] { get }
    var nextQueue: [AbstractPlayable] { get }
    
    var isPlaying: Bool { get }
    func getPlayable(at playerIndex: PlayerIndex) -> AbstractPlayable
    var currentlyPlaying: AbstractPlayable?  { get }
    var contextName: String { get }
    var elapsedTime: Double { get }
    var duration: Double { get }
    var isShuffle: Bool { get }
    func toggleShuffle()
    var repeatMode: RepeatMode { get }
    func setRepeatMode(_: RepeatMode)
    var isOfflineMode: Bool { get set }
    var isAutoCachePlayedItems: Bool { get set }

    func reinit(playerStatus: PlayerData, queueHandler: PlayQueueHandler)
    func seek(toSecond: Double)
    
    func insertContextQueue(playables: [AbstractPlayable])
    func appendContextQueue(playables: [AbstractPlayable])
    func insertUserQueue(playables: [AbstractPlayable])
    func appendUserQueue(playables: [AbstractPlayable])
    func removePlayable(at: PlayerIndex)
    func movePlayable(from: PlayerIndex, to: PlayerIndex)
    func clearUserQueue()
    func clearContextQueue()
    func clearQueues()

    func play()
    func play(context: PlayContext)
    func playShuffled(context: PlayContext)
    func play(playerIndex: PlayerIndex)
    func pause()
    func togglePlayPause()
    func stop()
    func playPreviousOrReplay()
    func playNext()
    
    func addNotifier(notifier: MusicPlayable)
}

class PlayerFacadeImpl: PlayerFacade {
    
    private var playerStatus: PlayerStatusPersistent
    private var queueHandler: PlayQueueHandler
    private let backendAudioPlayer: BackendAudioPlayer
    private let musicPlayer: MusicPlayer
    private let userStatistics: UserStatistics
    
    init(playerStatus: PlayerStatusPersistent, queueHandler: PlayQueueHandler, musicPlayer: MusicPlayer, library: LibraryStorage, playableDownloadManager: DownloadManageable, backendAudioPlayer: BackendAudioPlayer, userStatistics: UserStatistics) {
        self.playerStatus = playerStatus
        self.queueHandler = queueHandler
        self.backendAudioPlayer = backendAudioPlayer
        self.musicPlayer = musicPlayer
        self.userStatistics = userStatistics
    }
    
    var prevQueue: [AbstractPlayable] {
        return queueHandler.prevQueue
    }
    var userQueue: [AbstractPlayable] {
        return queueHandler.userQueue
    }
    var nextQueue: [AbstractPlayable] {
        return queueHandler.nextQueue
    }
    
    var isPlaying: Bool {
        return backendAudioPlayer.isPlaying
    }
    func getPlayable(at playerIndex: PlayerIndex) -> AbstractPlayable {
        return queueHandler.getPlayable(at: playerIndex)
    }
    var currentlyPlaying: AbstractPlayable? {
        return musicPlayer.currentlyPlaying
    }
    var contextName: String {
        get {
            guard queueHandler.contextName.isEmpty else { return queueHandler.contextName }
            if queueHandler.prevQueue.isEmpty, queueHandler.nextQueue.isEmpty, queueHandler.currentlyPlaying == nil || queueHandler.isUserQueuePlaying {
                return ""
            } else {
                return "Mixed Context"
            }
        }
    }
    var elapsedTime: Double {
        return backendAudioPlayer.elapsedTime
    }
    var duration: Double {
        return backendAudioPlayer.duration
    }
    var isShuffle: Bool {
        return playerStatus.isShuffle
    }
    func toggleShuffle() {
        playerStatus.isShuffle = !isShuffle
        musicPlayer.notifyShuffleUpdated()
        musicPlayer.notifyPlaylistUpdated()
    }
    var repeatMode: RepeatMode {
        return playerStatus.repeatMode
    }
    func setRepeatMode(_ newValue: RepeatMode) {
        playerStatus.repeatMode = newValue
        musicPlayer.notifyRepeatUpdated()
    }
    var isOfflineMode: Bool {
        get { return backendAudioPlayer.isOfflineMode }
        set { backendAudioPlayer.isOfflineMode = newValue }
    }
    var isAutoCachePlayedItems: Bool {
        get { return playerStatus.isAutoCachePlayedItems }
        set {
            playerStatus.isAutoCachePlayedItems = newValue
            backendAudioPlayer.isAutoCachePlayedItems = newValue
        }
    }
    
    func reinit(playerStatus: PlayerData, queueHandler: PlayQueueHandler) {
        self.playerStatus = playerStatus
        self.queueHandler = queueHandler
        musicPlayer.reinit(playerStatus: playerStatus, queueHandler: queueHandler)
    }
    
    func seek(toSecond: Double) {
        userStatistics.usedAction(.playerSeek)
        backendAudioPlayer.seek(toSecond: toSecond)
    }
    
    func insertContextQueue(playables: [AbstractPlayable]) {
        queueHandler.insertContextQueue(playables: playables)
        musicPlayer.notifyPlaylistUpdated()
    }
    
    func appendContextQueue(playables: [AbstractPlayable]) {
        queueHandler.appendContextQueue(playables: playables)
        musicPlayer.notifyPlaylistUpdated()
    }

    func insertUserQueue(playables: [AbstractPlayable]) {
        queueHandler.insertUserQueue(playables: playables)
        musicPlayer.notifyPlaylistUpdated()
    }
    
    func appendUserQueue(playables: [AbstractPlayable]) {
        queueHandler.appendUserQueue(playables: playables)
        musicPlayer.notifyPlaylistUpdated()
    }

    func removePlayable(at: PlayerIndex) {
        queueHandler.removePlayable(at: at)
    }
    
    func movePlayable(from: PlayerIndex, to: PlayerIndex) {
        queueHandler.movePlayable(from: from, to: to)
    }

    func clearUserQueue() {
        queueHandler.clearUserQueue()
    }
    
    func clearContextQueue() {
        if !queueHandler.isUserQueuePlaying {
            if queueHandler.userQueue.isEmpty {
                musicPlayer.stop()
            } else {
                play(playerIndex: PlayerIndex(queueType: .user, index: 0))
            }
        }
        queueHandler.clearContextQueue()
    }
    
    func clearQueues() {
        musicPlayer.stop()
        clearContextQueue()
        queueHandler.clearUserQueue()
        musicPlayer.notifyPlayerStopped()
    }

    func play() {
        musicPlayer.play()
    }
    
    func play(context: PlayContext) {
        if playerStatus.isShuffle { playerStatus.isShuffle = false }
        musicPlayer.play(context: context)
    }
    
    func playShuffled(context: PlayContext) {
        guard !context.playables.isEmpty else { return }
        if playerStatus.isShuffle { playerStatus.isShuffle = false }
        let shuffleContext = context.getWithShuffledIndex()
        musicPlayer.play(context: shuffleContext)
        playerStatus.isShuffle = true
        musicPlayer.notifyShuffleUpdated()
        musicPlayer.notifyPlaylistUpdated()
    }
    
    func play(playerIndex: PlayerIndex) {
        musicPlayer.play(playerIndex: playerIndex)
    }
    
    func pause() {
        musicPlayer.pause()
    }
    
    func togglePlayPause() {
        musicPlayer.togglePlayPause()
    }
    
    func stop() {
        musicPlayer.stop()
    }
    
    func playPreviousOrReplay() {
        musicPlayer.playPreviousOrReplay()
    }
    
    func playNext() {
        musicPlayer.playNext()
    }
    
    func addNotifier(notifier: MusicPlayable) {
        musicPlayer.addNotifier(notifier: notifier)
    }
    
}
