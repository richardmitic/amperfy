import XCTest
@testable import Amperfy

class SsPodcastEpisodesParserTest: AbstractSsParserTest {
    
    var testPodcast: Podcast?
    
    override func setUp() {
        super.setUp()
        xmlData = getTestFileData(name: "podcasts_example_1")
        testPodcast = library.createPodcast()
        ssParserDelegate = SsPodcastEpisodeParserDelegate(podcast: testPodcast!, library: library, syncWave: syncWave, subsonicUrlCreator: subsonicUrlCreator)
    }
    
    override func checkCorrectParsing() {
        guard let podcast = testPodcast else { XCTFail(); return }
        XCTAssertEqual(podcast.episodes.count, 2)

        // episodes are sorted by publish date
        var episode = podcast.episodes[1]
        XCTAssertEqual(episode.id, "34")
        XCTAssertEqual(episode.playInfo!.title, "Scorpions have re-evolved eyes")
        XCTAssertEqual(episode.playInfo!.id, "")
        XCTAssertEqual(episode.depiction, "This week Dr Chris fills us in on the UK's largest free science festival, plus all this week's big scientific discoveries.")
        XCTAssertEqual(episode.publishDate.timeIntervalSince1970, 1296744403) //"2011-02-03T14:46:43"
        XCTAssertEqual(episode.streamId, "523")
        XCTAssertEqual(episode.remoteStatus, .completed)
        XCTAssertEqual(episode.podcast, podcast)
        XCTAssertNil(episode.playInfo!.artist)
        XCTAssertNil(episode.playInfo!.album)
        XCTAssertNil(episode.playInfo!.disk)
        XCTAssertEqual(episode.playInfo!.track, 0)
        XCTAssertEqual(episode.playInfo!.genre?.name, "Podcast")
        XCTAssertEqual(episode.playInfo!.duration, 3146)
        XCTAssertEqual(episode.playInfo!.year, 2011)
        XCTAssertEqual(episode.playInfo!.bitrate, 128000)
        XCTAssertEqual(episode.playInfo!.contentType, "audio/mpeg")
        XCTAssertNil(episode.playInfo!.url)
        XCTAssertEqual(episode.playInfo!.size, 78421341)
        XCTAssertEqual(episode.artwork?.url, "www-24")
        XCTAssertEqual(episode.artwork?.type, "")
        XCTAssertEqual(episode.artwork?.id, "24")

        episode = podcast.episodes[0]
        XCTAssertEqual(episode.id, "35")
        XCTAssertEqual(episode.playInfo!.title, "Scar tissue and snake venom treatment")
        XCTAssertEqual(episode.playInfo!.id, "")
        XCTAssertEqual(episode.depiction, "This week Dr Karl tells the gruesome tale of a surgeon who operated on himself.")
        XCTAssertEqual(episode.publishDate.timeIntervalSince1970, 1315068472) // "2011-09-03T16:47:52"
        XCTAssertEqual(episode.streamId, "524")
        XCTAssertEqual(episode.remoteStatus, .completed)
        XCTAssertEqual(episode.podcast, podcast)
        XCTAssertNil(episode.playInfo!.artist)
        XCTAssertNil(episode.playInfo!.album)
        XCTAssertNil(episode.playInfo!.disk)
        XCTAssertEqual(episode.playInfo!.track, 0)
        XCTAssertEqual(episode.playInfo!.genre?.name, "Podcast")
        XCTAssertEqual(episode.playInfo!.duration, 3099)
        XCTAssertEqual(episode.playInfo!.year, 2011)
        XCTAssertEqual(episode.playInfo!.bitrate, 128000)
        XCTAssertEqual(episode.playInfo!.contentType, "audio/mpeg")
        XCTAssertNil(episode.playInfo!.url)
        XCTAssertEqual(episode.playInfo!.size, 45624671)
        XCTAssertEqual(episode.artwork?.url, "www-27")
        XCTAssertEqual(episode.artwork?.type, "")
        XCTAssertEqual(episode.artwork?.id, "27")
    }

}