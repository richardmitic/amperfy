//
//  PlayerView.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 09.03.19.
//  Copyright (c) 2019 Maximilian Bauer. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import MediaPlayer
import MarqueeLabel
import AmperfyKit
import PromiseKit

class PlayerView: UIView {
  
    static private let frameHeightCompact: CGFloat = 190 + margin.top + margin.bottom
    static private let margin = UIEdgeInsets(top: 0, left: UIView.defaultMarginX, bottom: 20, right: UIView.defaultMarginX)
    static private let defaultAnimationDuration = TimeInterval(0.50)
    
    var lastDisplayedPlayable: AbstractPlayable?
    
    private var appDelegate: AppDelegate!
    private var player: PlayerFacade!
    private var rootView: PopupPlayerVC?
    private var displayStyle: PlayerDisplayStyle!
    
    @IBOutlet weak var artworkImage: LibraryEntityImage!
    @IBOutlet weak var artworkContainerView: UIView!
    
    @IBOutlet weak var titleCompactLabel: MarqueeLabel!
    @IBOutlet weak var titleCompactButton: UIButton!
    @IBOutlet weak var titleLargeLabel: MarqueeLabel!
    @IBOutlet weak var titleLargeButton: UIButton!
    
    @IBOutlet weak var albumLargeLabel: MarqueeLabel!
    @IBOutlet weak var albumLargeButton: UIButton!
    
    @IBOutlet weak var artistNameCompactLabel: MarqueeLabel!
    @IBOutlet weak var artistNameCompactButton: UIButton!
    @IBOutlet weak var artistNameLargeLabel: MarqueeLabel!
    @IBOutlet weak var artistNameLargeButton: UIButton!
    
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var previousButton: UIButton!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var repeatButton: UIButton!
    @IBOutlet weak var shuffleButton: UIButton!
    @IBOutlet weak var skipBackwardButton: UIButton!
    @IBOutlet weak var skipForwardButton: UIButton!
    
    @IBOutlet weak var timeSlider: UISlider!
    @IBOutlet weak var elapsedTimeLabel: UILabel!
    @IBOutlet weak var remainingTimeLabel: UILabel!
    
    @IBOutlet weak var playerModeButton: UIButton!
    @IBOutlet weak var displayPlaylistButton: UIButton!
    @IBOutlet weak var playbackRateButton: UIButton!
    @IBOutlet weak var sleepTimerButton: UIButton!
    
    @IBOutlet weak var ratingPlaceholderView: UIView!

    // Animation constraints
    @IBOutlet weak var artistToTitleLargeDistanceConstraint: NSLayoutConstraint!
    @IBOutlet weak var bottomControlToProgressDistanceConstraint: NSLayoutConstraint!
    @IBOutlet weak var artworkWidthConstraint: NSLayoutConstraint!
    private var infoCompactToArtworkDistanceConstraint: NSLayoutConstraint?
    @IBOutlet weak var infoLargeToProgressDistanceConstraint: NSLayoutConstraint!
    private var artworkXPositionConstraint: NSLayoutConstraint?
    @IBOutlet weak var timeSliderToArtworkDistanceConstraint: NSLayoutConstraint!
    @IBOutlet weak var elapsedTimeToArtworkDistanceConstraint: NSLayoutConstraint!
    @IBOutlet weak var remainingTimeToArtworkDistanceConstraint: NSLayoutConstraint!
    @IBOutlet weak var ratingToBottomControlDistanceConstraint: NSLayoutConstraint!
    
    private var bottomSpaceHeight: CGFloat = 0.0
    
    static let sliderLabelToSliderDistance = 12.0

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        appDelegate = (UIApplication.shared.delegate as! AppDelegate)
        self.displayStyle = appDelegate.storage.settings.playerDisplayStyle
        self.layoutMargins = PlayerView.margin
        player = appDelegate.player
        player.addNotifier(notifier: self)
    }
    
    func prepare(toWorkOnRootView: PopupPlayerVC? ) {
        self.rootView = toWorkOnRootView
        ratingPlaceholderView.backgroundColor = .clear
        fetchSongInfoAndUpdateViews()
        refreshPlayer()
    }
    
    @IBAction func playButtonPushed(_ sender: Any) {
        player.togglePlayPause()
        refreshPlayButtonTitle()
    }
    
    @IBAction func previousButtonPushed(_ sender: Any) {
        switch player.playerMode {
        case .music:
            player.playPreviousOrReplay()
        case .podcast:
            player.skipBackward(interval: player.skipBackwardPodcastInterval)
        }
    }
    
    @IBAction func nextButtonPushed(_ sender: Any) {
        switch player.playerMode {
        case .music:
            player.playNext()
        case .podcast:
            player.skipForward(interval: player.skipForwardPodcastInterval)
        }
    }
    
    @IBAction func repeatButtonPushed(_ sender: Any) {
        player.setRepeatMode(player.repeatMode.nextMode)
        refreshRepeatButton()
    }
    
    @IBAction func shuffleButtonPushed(_ sender: Any) {
        player.toggleShuffle()
        refreshShuffleButton()
        rootView?.scrollToNextPlayingRow()
    }
    
    @IBAction func skipBackwardButtonPushed(_ sender: Any) {
        player.skipBackward(interval: player.skipBackwardMusicInterval)
    }
    
    @IBAction func skipForwardButtonPushed(_ sender: Any) {
        player.skipForward(interval: player.skipForwardMusicInterval)
    }
    
    @IBAction func timeSliderChanged(_ sender: Any) {
        if let timeSliderValue = timeSlider?.value {
            player.seek(toSecond: Double(timeSliderValue))
        }
    }
    
    @IBAction func timeSliderIsChanging(_ sender: Any) {
        if let timeSliderValue = timeSlider?.value {
            let elapsedClockTime = ClockTime(timeInSeconds: Int(timeSliderValue))
            elapsedTimeLabel.text = elapsedClockTime.asShortString()
            let remainingTime = ClockTime(timeInSeconds: Int(Double(timeSliderValue) - ceil(player.duration)))
            remainingTimeLabel.text = remainingTime.asShortString()
        }
    }
    
    @IBAction func airplayButtonPushed(_ sender: Any) {
        appDelegate.userStatistics.usedAction(.airplay)
        let rect = CGRect(x: -100, y: 0, width: 0, height: 0)
        let airplayVolume = MPVolumeView(frame: rect)
        airplayVolume.showsVolumeSlider = false
        self.addSubview(airplayVolume)
        for view: UIView in airplayVolume.subviews {
            if let button = view as? UIButton {
                button.sendActions(for: .touchUpInside)
                break
            }
        }
        airplayVolume.removeFromSuperview()
    }
    
    @IBAction func optionsPressed(_ sender: Any) {
        self.rootView?.optionsPressed()
    }
    
    @IBAction private func displayPlaylistPressed() {
        appDelegate.userStatistics.usedAction(.changePlayerDisplayStyle)
        displayStyle.switchToNextStyle()
        appDelegate.storage.settings.playerDisplayStyle = displayStyle
        refreshDisplayPlaylistButton()
        renderAnimation()
    }
    
    @IBAction func playerModeChangePressed(_ sender: Any) {
        switch player.playerMode {
        case .music:
            appDelegate.player.setPlayerMode(.podcast)
        case .podcast:
            appDelegate.player.setPlayerMode(.music)
        }
        refreshPlayerModeChangeButton()
    }
    
    @IBAction func titleCompactPressed(_ sender: Any) {
        displayAlbumDetail()
        displayPodcastDetail()
    }
    @IBAction func titleLargePressed(_ sender: Any) {
        displayAlbumDetail()
        displayPodcastDetail()
    }
    @IBAction func albumLargePressed(_ sender: Any) {
        displayAlbumDetail()
        displayPodcastDetail()
    }
    @IBAction func artistNameCompactPressed(_ sender: Any) {
        displayArtistDetail()
        displayPodcastDetail()
    }
    @IBAction func artistNameLargePressed(_ sender: Any) {
        displayArtistDetail()
        displayPodcastDetail()
    }
    
    private func displayArtistDetail() {
        if let song = lastDisplayedPlayable?.asSong, let artist = song.artist {
            let artistDetailVC = ArtistDetailVC.instantiateFromAppStoryboard()
            artistDetailVC.artist = artist
            rootView?.closePopupPlayerAndDisplayInLibraryTab(vc: artistDetailVC)
        }
    }
    
    private func displayAlbumDetail() {
        if let song = lastDisplayedPlayable?.asSong, let album = song.album {
            let albumDetailVC = AlbumDetailVC.instantiateFromAppStoryboard()
            albumDetailVC.album = album
            albumDetailVC.songToScrollTo = song
            rootView?.closePopupPlayerAndDisplayInLibraryTab(vc: albumDetailVC)
        }
    }
    
    private func displayPodcastDetail() {
        if let podcastEpisode = lastDisplayedPlayable?.asPodcastEpisode, let podcast = podcastEpisode.podcast {
            let podcastDetailVC = PodcastDetailVC.instantiateFromAppStoryboard()
            podcastDetailVC.podcast = podcast
            podcastDetailVC.episodeToScrollTo = podcastEpisode
            rootView?.closePopupPlayerAndDisplayInLibraryTab(vc: podcastDetailVC)
        }
    }
    
    func renderAnimation(animationDuration: TimeInterval = defaultAnimationDuration) {
        if displayStyle == .compact {
            rootView?.scrollToNextPlayingRow()
            renderAnimationSwitchToCompact(animationDuration: animationDuration)
        } else {
            renderAnimationSwitchToLarge(animationDuration: animationDuration)
        }
    }
    
    private func renderAnimationSwitchToCompact(animationDuration: TimeInterval = defaultAnimationDuration) {
        guard let rootView = self.rootView else { return }
        artworkWidthConstraint.constant = 70
        infoLargeToProgressDistanceConstraint.constant = -30
        bottomControlToProgressDistanceConstraint.constant = 5
        timeSliderToArtworkDistanceConstraint.constant = 10
        elapsedTimeToArtworkDistanceConstraint.constant = timeSliderToArtworkDistanceConstraint.constant + Self.sliderLabelToSliderDistance
        remainingTimeToArtworkDistanceConstraint.constant = timeSliderToArtworkDistanceConstraint.constant + Self.sliderLabelToSliderDistance

        self.infoCompactToArtworkDistanceConstraint?.isActive = false
        self.infoCompactToArtworkDistanceConstraint = NSLayoutConstraint(item: self.titleCompactLabel!,
                           attribute: .leading,
                           relatedBy: .equal,
                           toItem: self.artworkContainerView,
                           attribute: .trailing,
                           multiplier: 1.0,
                           constant: UIView.defaultMarginX)
        self.infoCompactToArtworkDistanceConstraint?.isActive = true
        
        self.artworkXPositionConstraint?.isActive = false
        self.artworkXPositionConstraint = NSLayoutConstraint(item: artworkContainerView!,
                           attribute: .left,
                           relatedBy: .equal,
                           toItem: displayPlaylistButton,
                           attribute: .left,
                           multiplier: 1.0,
                           constant: 16)
        self.artworkXPositionConstraint?.isActive = true
    
        UIView.animate(withDuration: animationDuration/3, delay: animationDuration/2, options: .curveEaseIn, animations: ({
            self.titleCompactLabel.alpha = 1
            self.titleCompactButton.isHidden = false
            self.artistNameCompactLabel.alpha = 1
            self.artistNameCompactButton.isHidden = false
        }), completion: nil)
        UIView.animate(withDuration: animationDuration, delay: 0, options: .curveEaseOut, animations: ({
            self.ratingPlaceholderView.alpha = 0
            self.ratingPlaceholderView.isHidden = true
            self.titleLargeLabel.alpha = 0
            self.titleLargeButton.isHidden = true
            self.albumLargeLabel.alpha = 0
            self.albumLargeButton.isHidden = true
            self.artistNameLargeLabel.alpha = 0
            self.artistNameLargeButton.isHidden = true
        }), completion: nil)
        
        rootView.renderAnimationForCompactPlayer(ofHight: PlayerView.frameHeightCompact, animationDuration: animationDuration)

        UIView.animate(withDuration: animationDuration) {
            self.layoutIfNeeded()
        }
    }
    
    static let minInfoLargeToProgressHeight = 10.0
    static let minBottomControlToProgressHeight = 20.0
    static let minRatingToBottomControlHeight = 20.0
    static let minLargeBottomMargin = 16.0
    
    private func renderAnimationSwitchToLarge(animationDuration: TimeInterval = defaultAnimationDuration) {
        guard let rootView = self.rootView else { return }
        infoLargeToProgressDistanceConstraint.constant = Self.minInfoLargeToProgressHeight
        bottomControlToProgressDistanceConstraint.constant = titleLargeLabel.frame.height + artistNameLargeLabel.frame.height + artistToTitleLargeDistanceConstraint.constant + infoLargeToProgressDistanceConstraint.constant + Self.minBottomControlToProgressHeight
        ratingToBottomControlDistanceConstraint.constant = Self.minRatingToBottomControlHeight
        timeSliderToArtworkDistanceConstraint.constant = 18
        elapsedTimeToArtworkDistanceConstraint.constant = timeSliderToArtworkDistanceConstraint.constant + Self.sliderLabelToSliderDistance
        remainingTimeToArtworkDistanceConstraint.constant = timeSliderToArtworkDistanceConstraint.constant + Self.sliderLabelToSliderDistance
        bottomSpaceHeight = Self.minLargeBottomMargin

        let availableRootWidth = rootView.frameSizeWithRotationAdjusment.width - PlayerView.margin.left -  PlayerView.margin.right
        let availableRootHeight = rootView.availableFrameHeightForLargePlayer

        var elementsBelowArtworkHeight = timeSliderToArtworkDistanceConstraint.constant
        elementsBelowArtworkHeight += timeSlider.frame.size.height
        elementsBelowArtworkHeight += infoLargeToProgressDistanceConstraint.constant
        elementsBelowArtworkHeight += titleLargeLabel.frame.size.height
        elementsBelowArtworkHeight += artistToTitleLargeDistanceConstraint.constant
        elementsBelowArtworkHeight += artistNameLargeLabel.frame.size.height
        elementsBelowArtworkHeight += playButton.frame.size.height
        elementsBelowArtworkHeight += ratingToBottomControlDistanceConstraint.constant
        elementsBelowArtworkHeight += ratingPlaceholderView.frame.size.height
        elementsBelowArtworkHeight += bottomSpaceHeight
        
        let planedArtworkHeight = availableRootWidth
        let fullLargeHeight = artworkContainerView.frame.origin.y + planedArtworkHeight + elementsBelowArtworkHeight + bottomSpaceHeight + PlayerView.margin.bottom

        // Set artwork size depending on device height
        if availableRootHeight < fullLargeHeight {
            artworkWidthConstraint.constant = availableRootHeight - (fullLargeHeight-planedArtworkHeight)
        } else {
            artworkWidthConstraint.constant = planedArtworkHeight
            let availableBottomLeftOverSpace = availableRootHeight - fullLargeHeight
            infoLargeToProgressDistanceConstraint.constant += availableBottomLeftOverSpace / 4
            bottomControlToProgressDistanceConstraint.constant += availableBottomLeftOverSpace / 2
            ratingToBottomControlDistanceConstraint.constant += availableBottomLeftOverSpace / 4
            bottomSpaceHeight += availableBottomLeftOverSpace / 4
        }
        
        self.infoCompactToArtworkDistanceConstraint?.isActive = false
        self.infoCompactToArtworkDistanceConstraint = NSLayoutConstraint(item: titleCompactLabel!,
                           attribute: .leading,
                           relatedBy: .lessThanOrEqual,
                           toItem: artworkContainerView,
                           attribute: .trailing,
                           multiplier: 1.0,
                           constant: 0)
        self.infoCompactToArtworkDistanceConstraint?.isActive = true
        
        self.artworkXPositionConstraint?.isActive = false
        self.artworkXPositionConstraint = NSLayoutConstraint(item: artworkContainerView!,
                           attribute: .centerX,
                           relatedBy: .equal,
                           toItem: rootView.view,
                           attribute: .centerX,
                           multiplier: 1.0,
                           constant: 0)
        self.artworkXPositionConstraint?.isActive = true

        self.titleCompactLabel.alpha = 0
        self.titleCompactButton.isHidden = true
        self.artistNameCompactLabel.alpha = 0
        self.artistNameCompactButton.isHidden = true
        
        UIView.animate(withDuration: animationDuration, delay: 0, options: .curveEaseIn, animations: ({
            self.ratingPlaceholderView.alpha = 1
            self.ratingPlaceholderView.isHidden = false
            self.titleLargeLabel.alpha = 1
            self.titleLargeButton.isHidden = false
            self.albumLargeLabel.alpha = 1
            self.albumLargeButton.isHidden = false
            self.artistNameLargeLabel.alpha = 1
            self.artistNameLargeButton.isHidden = false
        }), completion: nil)
        
        rootView.renderAnimationForLargePlayer(animationDuration: animationDuration)

        UIView.animate(withDuration: animationDuration) {
            self.layoutIfNeeded()
        }
    }
    
    func viewWillAppear(_ animated: Bool) {
        refreshView()
    }
    
    func refreshView() {
        refreshPlayer()
        renderAnimation(animationDuration: TimeInterval(0.0))
        
        titleCompactLabel.applyAmperfyStyle()
        titleLargeLabel.applyAmperfyStyle()
        albumLargeLabel.applyAmperfyStyle()
        artistNameCompactLabel.applyAmperfyStyle()
        artistNameLargeLabel.applyAmperfyStyle()

        timeSlider.setUnicolorThumbImage(thumbSize: 10.0, color: .labelColor, for: UIControl.State.normal)
        timeSlider.setUnicolorThumbImage(thumbSize: 30.0, color: .labelColor, for: UIControl.State.highlighted)
    }
    
    // handle dark/light mode change
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        timeSlider.setUnicolorThumbImage(thumbSize: 10.0, color: .labelColor, for: UIControl.State.normal)
        timeSlider.setUnicolorThumbImage(thumbSize: 30.0, color: .labelColor, for: UIControl.State.highlighted)
        refreshLabelColor()
    }
    
    func refreshPlayButtonTitle() {
        var title = ""
        var buttonImg = UIImage()
        if player.isPlaying {
            title = FontAwesomeIcon.Pause.asString
            buttonImg = UIImage.pause
        } else {
            title = FontAwesomeIcon.Play.asString
            buttonImg = UIImage.play
        }
        
        playButton.setTitle(title, for: UIControl.State.normal)
        let barButtonItem = UIBarButtonItem(image: buttonImg, style: .plain, target: self, action: #selector(PlayerView.playButtonPushed))
        rootView?.popupItem.trailingBarButtonItems = [ barButtonItem ]
    }
    
    func fetchSongInfoAndUpdateViews() {
        guard self.appDelegate.storage.settings.isOnlineMode,
              let song = player.currentlyPlaying?.asSong
        else { return }
        
        firstly {
            self.appDelegate.librarySyncer.sync(song: song)
        }.done {
            self.refreshCurrentlyPlayingInfo()
        }.catch { error in
            self.appDelegate.eventLogger.report(topic: "Song Info", error: error)
        }
    }
    
    func refreshCurrentlyPlayingInfo() {
        refreshArtwork()
        refreshLabelColor()
        if let playableInfo = player.currentlyPlaying {
            titleCompactLabel.text = playableInfo.title
            titleLargeLabel.text = playableInfo.title
            albumLargeLabel.text = playableInfo.asSong?.album?.name ?? ""
            albumLargeButton.isEnabled = playableInfo.asSong != nil
            artistNameCompactLabel.text = playableInfo.creatorName
            artistNameLargeLabel.text = playableInfo.creatorName
            rootView?.popupItem.title = playableInfo.title
            rootView?.popupItem.subtitle = playableInfo.creatorName
            rootView?.changeBackgroundGradient(forPlayable: playableInfo)
            lastDisplayedPlayable = playableInfo
        } else {
            switch player.playerMode {
            case .music:
                titleCompactLabel.text = "No music playing"
                titleLargeLabel.text = "No music playing"
                rootView?.popupItem.title = "No music playing"
            case .podcast:
                titleCompactLabel.text = "No podcast playing"
                titleLargeLabel.text = "No podcast playing"
                rootView?.popupItem.title = "No podcast playing"
            }
            albumLargeLabel.text = ""
            artistNameCompactLabel.text = ""
            artistNameLargeLabel.text = ""
            rootView?.popupItem.subtitle = ""
            lastDisplayedPlayable = nil
        }
        switch player.playerMode {
        case .music:
            repeatButton.isHidden = false
            shuffleButton.isHidden = false
            skipBackwardButton.isHidden = !appDelegate.storage.settings.isShowMusicPlayerSkipButtons
            skipForwardButton.isHidden = !appDelegate.storage.settings.isShowMusicPlayerSkipButtons
            skipBackwardButton.alpha = !appDelegate.storage.settings.isShowMusicPlayerSkipButtons ? 0.0 : 1.0
            skipForwardButton.alpha = !appDelegate.storage.settings.isShowMusicPlayerSkipButtons ? 0.0 : 1.0
        case .podcast:
            repeatButton.isHidden = true
            shuffleButton.isHidden = true
            skipBackwardButton.isHidden = true
            skipForwardButton.isHidden = true
        }
    }
    
    func refreshArtwork() {
        if let playableInfo = player.currentlyPlaying {
            artworkImage.display(entity: playableInfo)
            rootView?.popupItem.image = playableInfo.image(setting: appDelegate.storage.settings.artworkDisplayPreference)
        } else {
            switch player.playerMode {
            case .music:
                artworkImage.display(image: UIImage.songArtwork)
                rootView?.popupItem.image = UIImage.songArtwork
            case .podcast:
                artworkImage.display(image: UIImage.podcastArtwork)
                rootView?.popupItem.image = UIImage.podcastArtwork
            }
        }
    }
    
    func refreshLabelColor() {
        artistNameLargeLabel.textColor = subtitleColor(style: traitCollection.userInterfaceStyle)
        artistNameCompactLabel.textColor = subtitleColor(style: traitCollection.userInterfaceStyle)
    }
    
    func subtitleColor(style: UIUserInterfaceStyle) -> UIColor {
        if let artwork = player.currentlyPlaying?.image(setting: appDelegate.storage.settings.artworkDisplayPreference), artwork != player.currentlyPlaying?.defaultImage {
            let customColor: UIColor!
            if traitCollection.userInterfaceStyle == .dark {
                customColor = artwork.averageColor().getWithLightness(of: 0.8)
            } else {
                customColor = artwork.averageColor().getWithLightness(of: 0.2)
            }
            return customColor
        } else {
            return .labelColor
        }
    }

    func refreshTimeInfo() {
        if player.currentlyPlaying != nil {
            timeSlider.minimumValue = 0.0
            timeSlider.maximumValue = Float(player.duration)
            if !timeSlider.isTracking {
                let elapsedClockTime = ClockTime(timeInSeconds: Int(player.elapsedTime))
                elapsedTimeLabel.text = elapsedClockTime.asShortString()
                let remainingTime = ClockTime(timeInSeconds: Int(player.elapsedTime - ceil(player.duration)))
                remainingTimeLabel.text = remainingTime.asShortString()
                timeSlider.value = Float(player.elapsedTime)
            }
            rootView?.popupItem.progress = Float(player.elapsedTime / player.duration)
        } else {
            elapsedTimeLabel.text = "--:--"
            remainingTimeLabel.text = "--:--"
            timeSlider.minimumValue = 0.0
            timeSlider.maximumValue = 1.0
            timeSlider.value = 0.0
            rootView?.popupItem.progress = 0.0
        }
    }
    
    func refreshPlayer() {
        refreshCurrentlyPlayingInfo()
        refreshPlayButtonTitle()
        refreshTimeInfo()
        refreshPrevNextButtons()
        refreshRepeatButton()
        refreshShuffleButton()
        refreshPlaybackRateButton()
        refreshSleepTimerButton()
        refreshDisplayPlaylistButton()
        refreshPlayerModeChangeButton()
    }
    
    func refreshPrevNextButtons() {
        previousButton.imageView?.contentMode = .scaleAspectFit
        nextButton.imageView?.contentMode = .scaleAspectFit
        switch player.playerMode {
        case .music:
            previousButton.setImage(UIImage.backwardFill, for: .normal)
            nextButton.setImage(UIImage.forwardFill, for: .normal)
        case .podcast:
            previousButton.setImage(UIImage.goBackward15, for: .normal)
            nextButton.setImage(UIImage.goForward30, for: .normal)
        }
    }
    
    func refreshRepeatButton() {
        UIView.performWithoutAnimation {
            switch player.repeatMode {
            case .off:
                repeatButton.setTitle(FontAwesomeIcon.Redo.asString, for: UIControl.State.normal)
                repeatButton.isSelected = false
            case .all:
                repeatButton.setTitle(FontAwesomeIcon.Redo.asString + " all", for: UIControl.State.selected)
                repeatButton.isSelected = true
            case .single:
                repeatButton.setTitle(FontAwesomeIcon.Redo.asString + " 1", for: UIControl.State.selected)
                repeatButton.isSelected = true
            }
            repeatButton.layoutIfNeeded()
        }
    }
    
    func refreshShuffleButton() {
        shuffleButton.imageView?.contentMode = .scaleAspectFit
        if player.isShuffle {
            shuffleButton.setImage(UIImage.shuffle.withRenderingMode(.alwaysTemplate), for: .normal)
            shuffleButton.tintColor = .labelColor
        } else {
            shuffleButton.setImage(UIImage.shuffleOff.withRenderingMode(.alwaysTemplate), for: .normal)
            shuffleButton.tintColor = .labelColor
        }
    }
    
    func refreshPlaybackRateButton() {
        let playbackRate = self.player.playbackRate
        var playbackRateString = ""
        var icon = UIImage.gauge
        if (playbackRate < 0.6) {
            playbackRateString = "0.5x"
            icon = UIImage.gaugeDown.withRenderingMode(.alwaysTemplate)
        } else if (playbackRate < 0.8) {
            playbackRateString = "0.75x"
            icon = UIImage.gaugeDown.withRenderingMode(.alwaysTemplate)
        } else if (playbackRate < 1.1) {
            playbackRateString = "1x"
            icon = UIImage.gauge.withRenderingMode(.alwaysTemplate)
        } else if (playbackRate < 1.3) {
            playbackRateString = "1.25x"
            icon = UIImage.gaugeUp.withRenderingMode(.alwaysTemplate)
        } else if (playbackRate < 1.6) {
            playbackRateString = "1.5x"
            icon = UIImage.gaugeUp.withRenderingMode(.alwaysTemplate)
        } else if (playbackRate < 1.8) {
            playbackRateString = "1.75x"
            icon = UIImage.gaugeUp.withRenderingMode(.alwaysTemplate)
        } else if (playbackRate < 2.1) {
            playbackRateString = "2x"
            icon = UIImage.gaugeUp.withRenderingMode(.alwaysTemplate)
        }
        playbackRateButton.setImage(icon, for: .normal)
        playbackRateButton.tintColor = .labelColor
        
        let doubleRate = UIAction(title: "2x", image: playbackRateString == "2x" ? .check : nil, handler: { _ in
            self.player.setPlaybackRate(2.0)
            self.refreshPlaybackRateButton()
        })
        let oneDot75ByRate = UIAction(title: "1.75x", image: playbackRateString == "1.75x" ? .check : nil, handler: { _ in
            self.player.setPlaybackRate(1.75)
            self.refreshPlaybackRateButton()
        })
        let oneDot5ByRate = UIAction(title: "1.5x", image: playbackRateString == "1.5x" ? .check : nil, handler: { _ in
            self.player.setPlaybackRate(1.5)
            self.refreshPlaybackRateButton()
        })
        let oneDot25Rate = UIAction(title: "1.25x", image: playbackRateString == "1.25x" ? .check : nil, handler: { _ in
            self.player.setPlaybackRate(1.25)
            self.refreshPlaybackRateButton()
        })
        let normalRate = UIAction(title: "Normal", image: playbackRateString == "1x" ? .check : nil, handler: { _ in
            self.player.setPlaybackRate(1.0)
            self.refreshPlaybackRateButton()
        })
        let dot75Rate = UIAction(title: "0.75x", image: playbackRateString == "0.75x" ? .check : nil, handler: { _ in
            self.player.setPlaybackRate(0.75)
            self.refreshPlaybackRateButton()
        })
        let dot5Rate = UIAction(title: "0.5x", image: playbackRateString == "0.5x" ? .check : nil, handler: { _ in
            self.player.setPlaybackRate(0.5)
            self.refreshPlaybackRateButton()
        })
        playbackRateButton.menu = UIMenu(title: "Playback Rate", children: [doubleRate, oneDot75ByRate, oneDot5ByRate, oneDot25Rate, normalRate, dot75Rate, dot5Rate])
        playbackRateButton.showsMenuAsPrimaryAction = true
    }
    
    func refreshSleepTimerButton() {
        if appDelegate.sleepTimer != nil || self.appDelegate.player.isShouldPauseAfterFinishedPlaying {
            sleepTimerButton.setImage(UIImage.sleep.withRenderingMode(.alwaysTemplate), for: .normal)
        } else {
            sleepTimerButton.setImage(UIImage.sleepFill.withRenderingMode(.alwaysTemplate), for: .normal)
        }
        playbackRateButton.tintColor = .labelColor
        
        if let timer = appDelegate.sleepTimer {
            let deactivate = UIAction(title: "Off", image: nil, handler: { _ in
                self.appDelegate.sleepTimer?.invalidate()
                self.appDelegate.sleepTimer = nil
                self.refreshSleepTimerButton()
            })
            sleepTimerButton.menu = UIMenu(title: "Will pause at: \(timer.fireDate.asShortHrMinString)", children: [deactivate])
        } else if self.appDelegate.player.isShouldPauseAfterFinishedPlaying {
            let deactivate = UIAction(title: "Off", image: nil, handler: { _ in
                self.appDelegate.player.isShouldPauseAfterFinishedPlaying = false
                self.refreshSleepTimerButton()
            })
            switch player.playerMode {
            case .music:
                sleepTimerButton.menu = UIMenu(title: "Will pause at end of song", children: [deactivate])
            case .podcast:
                sleepTimerButton.menu = UIMenu(title: "Will pause at end of episode", children: [deactivate])
            }
        } else {
            let endOfTrack = UIAction(title: "End of song or episode", image: nil, handler: { _ in
                self.appDelegate.player.isShouldPauseAfterFinishedPlaying = true
                self.refreshSleepTimerButton()
            })
            let sleep5 = UIAction(title: "5 Minutes", image: nil, handler: { _ in
                self.activateSleepTimer(timeInterval: TimeInterval(5 * 60))
                self.refreshSleepTimerButton()
            })
            let sleep10 = UIAction(title: "10 Minutes", image: nil, handler: { _ in
                self.activateSleepTimer(timeInterval: TimeInterval(10 * 60))
                self.refreshSleepTimerButton()
            })
            let sleep15 = UIAction(title: "15 Minutes", image: nil, handler: { _ in
                self.activateSleepTimer(timeInterval: TimeInterval(15 * 60))
                self.refreshSleepTimerButton()
            })
            let sleep30 = UIAction(title: "30 Minutes", image: nil, handler: { _ in
                self.activateSleepTimer(timeInterval: TimeInterval(30 * 60))
                self.refreshSleepTimerButton()
            })
            let sleep45 = UIAction(title: "45 Minutes", image: nil, handler: { _ in
                self.activateSleepTimer(timeInterval: TimeInterval(45 * 60))
                self.refreshSleepTimerButton()
            })
            let sleep60 = UIAction(title: "1 Hour", image: nil, handler: { _ in
                self.activateSleepTimer(timeInterval: TimeInterval(60 * 60))
                self.refreshSleepTimerButton()
            })
            sleepTimerButton.menu = UIMenu(title: "Sleep Timer", children: [endOfTrack, sleep5, sleep10, sleep15, sleep30, sleep45, sleep60])
        }
        sleepTimerButton.showsMenuAsPrimaryAction = true
    }
    
    func activateSleepTimer(timeInterval: TimeInterval) {
        appDelegate.sleepTimer?.invalidate()
        appDelegate.sleepTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { (t) in
            self.appDelegate.player.pause()
            self.appDelegate.eventLogger.info(topic: "Sleep Timer", message: "Sleep timer paused playback.")
            self.appDelegate.sleepTimer?.invalidate()
            self.appDelegate.sleepTimer = nil
            self.refreshSleepTimerButton()
        }
    }
    
    func refreshDisplayPlaylistButton() {
        displayPlaylistButton.imageView?.contentMode = .scaleAspectFit
        if displayStyle == .compact {
            displayPlaylistButton.setImage(UIImage.playerStyleCompact, for: .normal)
        } else {
            displayPlaylistButton.setImage(UIImage.playerStyleLarge, for: .normal)
        }
    }
    
    func refreshPlayerModeChangeButton() {
        playerModeButton.imageView?.contentMode = .scaleAspectFit
        switch player.playerMode {
        case .music:
            playerModeButton.setImage(UIImage.musicalNotes, for: .normal)
        case .podcast:
            playerModeButton.setImage(UIImage.podcast, for: .normal)
        }
    }
    
}

extension PlayerView: MusicPlayable {

    func didStartPlaying() {
        fetchSongInfoAndUpdateViews()
        refreshPlayer()
    }
    
    func didPause() {
        refreshPlayer()
    }
    
    func didStopPlaying() {
        refreshPlayer()
        refreshCurrentlyPlayingInfo()
    }

    func didElapsedTimeChange() {
        refreshTimeInfo()
    }
    
    func didPlaylistChange() {
        refreshPlayer()
    }
    
    func didArtworkChange() {
        refreshArtwork()
    }
    
    func didShuffleChange() {
        refreshShuffleButton()
    }
    
    func didRepeatChange() {
        refreshRepeatButton()
    }

}
