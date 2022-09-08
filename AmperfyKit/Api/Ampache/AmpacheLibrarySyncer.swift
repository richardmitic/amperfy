//
//  AmpacheLibrarySyncer.swift
//  AmperfyKit
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

import Foundation
import CoreData
import os.log
import UIKit
import PromiseKit

class AmpacheLibrarySyncer: LibrarySyncer {
    
    private let ampacheXmlServerApi: AmpacheXmlServerApi
    private let log = OSLog(subsystem: "Amperfy", category: "AmpacheLibSyncer")
    
    var isSyncAllowed: Bool {
        return Reachability.isConnectedToNetwork()
    }
    
    init(ampacheXmlServerApi: AmpacheXmlServerApi) {
        self.ampacheXmlServerApi = ampacheXmlServerApi
    }
    
    func syncInitial(persistentStorage: PersistentStorage, statusNotifyier: SyncCallbacks?) -> Promise<Void> {
        let library = LibraryStorage(context: persistentStorage.context)
        
        return firstly {
            ampacheXmlServerApi.requesetLibraryMetaData()
        }.get { auth in
            let syncWave = library.createSyncWave()
            syncWave.setMetaData(fromLibraryChangeDates: auth.libraryChangeDates)
            library.saveContext()
        }.then { auth -> Promise<Data> in
            statusNotifyier?.notifySyncStarted(ofType: .genre, totalCount: auth.genreCount)
            return self.ampacheXmlServerApi.requestGenres()
        }.then { data in
            persistentStorage.persistentContainer.performAsync { companion in
                let parserDelegate = GenreParserDelegate(library: companion.library, syncWave: companion.syncWave, parseNotifier: statusNotifyier)
                try self.parse(data: data, delegate: parserDelegate)
            }
        }.then {
            self.ampacheXmlServerApi.requesetLibraryMetaData()
        }.then { auth -> Promise<Void> in
            statusNotifyier?.notifySyncStarted(ofType: .artist, totalCount: auth.artistCount)
            let pollCountArtist = auth.artistCount / AmpacheXmlServerApi.maxItemCountToPollAtOnce
            let artistPromises: [() -> Promise<Void>] = Array(0...pollCountArtist).compactMap { index in return {
                return firstly {
                    self.ampacheXmlServerApi.requestArtists(startIndex: index*AmpacheXmlServerApi.maxItemCountToPollAtOnce)
                }.then { data in
                    persistentStorage.persistentContainer.performAsync { companion in
                        let parserDelegate = ArtistParserDelegate(library: companion.library, syncWave: companion.syncWave, parseNotifier: statusNotifyier)
                        try self.parse(data: data, delegate: parserDelegate)
                    }
                }
            }}
            return artistPromises.resolveSequentially()
        }.then {
            self.ampacheXmlServerApi.requesetLibraryMetaData()
        }.then { auth -> Promise<AuthentificationHandshake> in
            statusNotifyier?.notifySyncStarted(ofType: .album, totalCount: auth.albumCount)
            let pollCountAlbum = auth.albumCount / AmpacheXmlServerApi.maxItemCountToPollAtOnce
            let albumPromises: [() -> Promise<Void>] = Array(0...pollCountAlbum).compactMap { index in return {
                firstly {
                    self.ampacheXmlServerApi.requestAlbums(startIndex: index*AmpacheXmlServerApi.maxItemCountToPollAtOnce)
                }.then { data in
                    persistentStorage.persistentContainer.performAsync { companion in
                        let parserDelegate = AlbumParserDelegate(library: companion.library, syncWave: companion.syncWave, parseNotifier: statusNotifyier)
                        try self.parse(data: data, delegate: parserDelegate)
                    }
                }
            }}
            return albumPromises.resolveSequentially().map{ (auth) }
        }.then { (auth) -> Promise<Data> in
            statusNotifyier?.notifySyncStarted(ofType: .playlist, totalCount: auth.playlistCount)
            return self.ampacheXmlServerApi.requestPlaylists()
        }.then { data in
            persistentStorage.persistentContainer.performAsync { companion in
                let parserDelegate = PlaylistParserDelegate(library: companion.library, parseNotifier: statusNotifyier)
                try self.parse(data: data, delegate: parserDelegate)
            }
        }.then {
            self.ampacheXmlServerApi.requesetLibraryMetaData()
        }.then { auth in
            self.ampacheXmlServerApi.requestServerPodcastSupport().map{ ($0, auth) }
        }.then { (isSupported, auth) -> Promise<Void> in
            if isSupported {
                statusNotifyier?.notifySyncStarted(ofType: .podcast, totalCount: auth.podcastCount)
                return firstly {
                    self.ampacheXmlServerApi.requestPodcasts()
                }.then { data in
                    persistentStorage.persistentContainer.performAsync { companion in
                        let parserDelegate = PodcastParserDelegate(library: companion.library, syncWave: companion.syncWave, parseNotifier: statusNotifyier)
                        try self.parse(data: data, delegate: parserDelegate)
                    }
                }.then { data in
                    persistentStorage.persistentContainer.performAsync { companion in
                        companion.syncWave.syncState = .Done
                    }
                }
            } else {
               return persistentStorage.persistentContainer.performAsync { companion in
                   companion.syncWave.syncState = .Done
               }
           }
        }
    }
    
    func sync(genre: Genre, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        let albumSyncPromises = genre.albums.compactMap { album in return {
            self.sync(album: album, persistentContainer: persistentContainer)
        }}
        return albumSyncPromises.resolveSequentially()
    }
    
    func sync(artist: Artist, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        return firstly {
            ampacheXmlServerApi.requestArtistInfo(id: artist.id)
        }.then { data in
            persistentContainer.performAsync { companion in
                let parserDelegate = ArtistParserDelegate(library: companion.library, syncWave: companion.syncWave)
                do {
                    try self.parse(data: data, delegate: parserDelegate)
                } catch {
                    if let responseError = error as? ResponseError, let ampacheError = responseError.asAmpacheError, !ampacheError.isRemoteAvailable {
                        os_log("Artist <%s> is remote deleted", log: self.log, type: .info, artist.name)
                        artist.remoteStatus = .deleted
                    } else {
                        throw error
                    }
                }
            }
        }.then { () -> Promise<Void> in
            guard artist.remoteStatus == .available else { return Promise.value }
            return firstly {
                self.ampacheXmlServerApi.requestArtistAlbums(id: artist.id)
            }.then { data in
                persistentContainer.performAsync { companion in
                    let artistAsync = Artist(managedObject: companion.context.object(with: artist.managedObject.objectID) as! ArtistMO)
                    let oldAlbums = Set(artistAsync.albums)
                    let parserDelegate = AlbumParserDelegate(library: companion.library, syncWave: companion.syncWave)
                    try self.parse(data: data, delegate: parserDelegate)
                    let removedAlbums = oldAlbums.subtracting(parserDelegate.albumsParsed)
                    for album in removedAlbums {
                        os_log("Album <%s> is remote deleted", log: self.log, type: .info, album.name)
                        album.remoteStatus = .deleted
                        album.songs.forEach{
                            os_log("Song <%s> is remote deleted", log: self.log, type: .info, $0.displayString)
                            $0.remoteStatus = .deleted
                        }
                    }
                }
            }.then {
                self.ampacheXmlServerApi.requestArtistSongs(id: artist.id)
            }.then { data in
                persistentContainer.performAsync { companion in
                    let artistAsync = Artist(managedObject: companion.context.object(with: artist.managedObject.objectID) as! ArtistMO)
                    let oldSongs = Set(artistAsync.songs)
                    let parserDelegate = SongParserDelegate(library: companion.library, syncWave: companion.syncWave)
                    try self.parse(data: data, delegate: parserDelegate)
                    let removedSongs = oldSongs.subtracting(parserDelegate.parsedSongs)
                    removedSongs.lazy.compactMap{$0.asSong}.forEach {
                        os_log("Song <%s> is remote deleted", log: self.log, type: .info, $0.displayString)
                        $0.remoteStatus = .deleted
                    }
                }
            }
        }
    }
    
    func sync(album: Album, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        return firstly {
            ampacheXmlServerApi.requestAlbumInfo(id: album.id)
        }.then { data in
            persistentContainer.performAsync { companion in
                let parserDelegate = AlbumParserDelegate(library: companion.library, syncWave: companion.syncWave)
                do {
                    try self.parse(data: data, delegate: parserDelegate)
                } catch {
                    if let responseError = error as? ResponseError, let ampacheError = responseError.asAmpacheError, !ampacheError.isRemoteAvailable {
                        let albumAsync = Album(managedObject: companion.context.object(with: album.managedObject.objectID) as! AlbumMO)
                        os_log("Album <%s> is remote deleted", log: self.log, type: .info, albumAsync.name)
                        albumAsync.markAsRemoteDeleted()
                    } else {
                        throw error
                    }
                }
            }
        }.then { () -> Promise<Void> in
            guard album.remoteStatus == .available else { return Promise.value }
            return firstly {
                self.ampacheXmlServerApi.requestAlbumSongs(id: album.id)
            }.then { data in
                persistentContainer.performAsync { companion in
                    let albumAsync = Album(managedObject: companion.context.object(with: album.managedObject.objectID) as! AlbumMO)
                    let oldSongs = Set(albumAsync.songs)
                    let parserDelegate = SongParserDelegate(library: companion.library, syncWave: companion.syncWave)
                    try self.parse(data: data, delegate: parserDelegate)
                    let removedSongs = oldSongs.subtracting(parserDelegate.parsedSongs)
                    removedSongs.lazy.compactMap{$0.asSong}.forEach {
                        os_log("Song <%s> is remote deleted", log: self.log, type: .info, $0.displayString)
                        $0.remoteStatus = .deleted
                        albumAsync.managedObject.removeFromSongs($0.managedObject)
                    }
                    albumAsync.isSongsMetaDataSynced = true
                }
            }
        }
    }
    
    func sync(song: Song, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        return firstly {
            ampacheXmlServerApi.requestSongInfo(id: song.id)
        }.then { data in
            persistentContainer.performAsync { companion in
                let parserDelegate = SongParserDelegate(library: companion.library, syncWave: companion.syncWave)
                try self.parse(data: data, delegate: parserDelegate)
            }
        }
    }
    
    func sync(podcast: Podcast, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        return firstly {
            ampacheXmlServerApi.requestServerPodcastSupport()
        }.then { isSupported -> Promise<Void> in
            guard isSupported else { return Promise.value }
            return firstly {
                self.ampacheXmlServerApi.requestPodcastEpisodes(id: podcast.id)
            }.then { data in
                persistentContainer.performAsync { companion in
                    let podcastAsync = Podcast(managedObject: companion.context.object(with: podcast.managedObject.objectID) as! PodcastMO)
                    let oldEpisodes = Set(podcastAsync.episodes)
                    
                    let parserDelegate = PodcastEpisodeParserDelegate(podcast: podcastAsync, library: companion.library, syncWave: companion.syncWave)
                    try self.parse(data: data, delegate: parserDelegate)
                    
                    let deletedEpisodes = oldEpisodes.subtracting(parserDelegate.parsedEpisodes)
                    deletedEpisodes.forEach {
                        os_log("Podcast Episode <%s> is remote deleted", log: self.log, type: .info, $0.displayString)
                        $0.podcastStatus = .deleted
                    }
                }
            }
        }
    }
    
    func syncMusicFolders(persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        return firstly {
            ampacheXmlServerApi.requestCatalogs()
        }.then { data in
            persistentContainer.performAsync { companion in
                let parserDelegate = CatalogParserDelegate(library: companion.library, syncWave: companion.syncWave)
                try self.parse(data: data, delegate: parserDelegate)
            }
        }
    }
    
    func syncIndexes(musicFolder: MusicFolder, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        return firstly {
            ampacheXmlServerApi.requestArtistWithinCatalog(id: musicFolder.id)
        }.then { data in
            persistentContainer.performAsync { companion in
                let parserDelegate = ArtistParserDelegate(library: companion.library, syncWave: companion.syncWave)
                try self.parse(data: data, delegate: parserDelegate)
                
                let musicFolderAsync = MusicFolder(managedObject: companion.context.object(with: musicFolder.managedObject.objectID) as! MusicFolderMO)
                let directoriesBeforeFetch = Set(musicFolderAsync.directories)
                var directoriesAfterFetch: Set<Directory> = Set()
                for artist in parserDelegate.artistsParsed {
                    let artistDirId = "artist-\(artist.id)"
                    var curDir: Directory!
                    if let foundDir = companion.library.getDirectory(id: artistDirId) {
                        curDir = foundDir
                    } else {
                        curDir = companion.library.createDirectory()
                        curDir.id = artistDirId
                    }
                    curDir.name = artist.name
                    musicFolderAsync.managedObject.addToDirectories(curDir.managedObject)
                    directoriesAfterFetch.insert(curDir)
                }
                
                let removedDirectories = directoriesBeforeFetch.subtracting(directoriesAfterFetch)
                removedDirectories.forEach{ companion.library.deleteDirectory(directory: $0) }
            }
        }
    }
    
    func sync(directory: Directory, persistentStorage: PersistentStorage) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        if directory.id.starts(with: "album-") {
            let albumId = String(directory.id.dropFirst("album-".count))
            return self.sync(directory: directory, thatIsAlbumId: albumId, persistentStorage: persistentStorage)
        } else if directory.id.starts(with: "artist-") {
            let artistId = String(directory.id.dropFirst("artist-".count))
            return self.sync(directory: directory, thatIsArtistId: artistId, persistentStorage: persistentStorage)
        } else {
            return Promise.value
        }
    }
    
    private func sync(directory: Directory, thatIsAlbumId albumId: String, persistentStorage: PersistentStorage) -> Promise<Void> {
        let library = LibraryStorage(context: persistentStorage.context)
        guard let album = library.getAlbum(id: albumId) else { return Promise.value }
        let songsBeforeFetch = Set(directory.songs)
        
        return firstly {
            self.sync(album: album, persistentContainer: persistentStorage.persistentContainer)
        }.then {
            persistentStorage.persistentContainer.performAsync { companion in
                let directoryAsync = Directory(managedObject: companion.context.object(with: directory.managedObject.objectID) as! DirectoryMO)
                let songsBeforeFetchAsync = Set(songsBeforeFetch.compactMap {
                    Song(managedObject: companion.context.object(with: $0.managedObject.objectID) as! SongMO)
                })
                
                directoryAsync.songs.forEach { directoryAsync.managedObject.removeFromSongs($0.managedObject) }
                let songsToRemove = songsBeforeFetchAsync.subtracting(Set(album.songs.compactMap{$0.asSong}))
                songsToRemove.lazy.compactMap{$0.asSong}.forEach{
                    directoryAsync.managedObject.removeFromSongs($0.managedObject)
                }
                album.songs.compactMap{$0.asSong}.forEach{
                    directoryAsync.managedObject.addToSongs($0.managedObject)
                }
            }
        }
    }
    
    private func sync(directory: Directory, thatIsArtistId artistId: String, persistentStorage: PersistentStorage) -> Promise<Void> {
        let library = LibraryStorage(context: persistentStorage.context)
        guard let artist = library.getArtist(id: artistId) else { return Promise.value }
        let directoriesBeforeFetch = Set(directory.subdirectories)
        
        return firstly {
            self.sync(artist: artist, persistentContainer: persistentStorage.persistentContainer)
        }.then {
            persistentStorage.persistentContainer.performAsync { companion in
                let directoryAsync = Directory(managedObject: companion.context.object(with: directory.managedObject.objectID) as! DirectoryMO)
                let artistAsync = Artist(managedObject: companion.context.object(with: artist.managedObject.objectID) as! ArtistMO)
                let directoriesBeforeFetchAsync = Set(directoriesBeforeFetch.compactMap {
                    Directory(managedObject: companion.context.object(with: $0.managedObject.objectID) as! DirectoryMO)
                })
                
                var directoriesAfterFetch: Set<Directory> = Set()
                let artistAlbums = companion.library.getAlbums(whichContainsSongsWithArtist: artistAsync)
                for album in artistAlbums {
                    let albumDirId = "album-\(album.id)"
                    var albumDir: Directory!
                    if let foundDir = companion.library.getDirectory(id: albumDirId) {
                        albumDir = foundDir
                    } else {
                        albumDir = companion.library.createDirectory()
                        albumDir.id = albumDirId
                    }
                    albumDir.name = album.name
                    albumDir.artwork = album.artwork
                    directoryAsync.managedObject.addToSubdirectories(albumDir.managedObject)
                    directoriesAfterFetch.insert(albumDir)
                }
                
                let directoriesToRemove = directoriesBeforeFetchAsync.subtracting(directoriesAfterFetch)
                directoriesToRemove.forEach{
                    directoryAsync.managedObject.removeFromSubdirectories($0.managedObject)
                }
            }
        }
    }
    
    func syncRecentSongs(persistentStorage: PersistentStorage) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        os_log("Sync recently added songs", log: log, type: .info)
        return firstly {
            ampacheXmlServerApi.requestRecentSongs(count: 50)
        }.then { data in
            persistentStorage.persistentContainer.performAsync { companion in
                let oldRecentSongs = Set(companion.library.getRecentSongs())
                
                let parserDelegate = SongParserDelegate(library: companion.library, syncWave: companion.syncWave)
                try self.parse(data: data, delegate: parserDelegate)
                
                let notRecentSongsAnymore = oldRecentSongs.subtracting(parserDelegate.parsedSongs)
                notRecentSongsAnymore.filter{ !$0.id.isEmpty }.forEach { $0.isRecentlyAdded = false }
                parserDelegate.parsedSongs.filter{ !$0.id.isEmpty }.forEach { $0.isRecentlyAdded = true }
            }
        }
    }
    
    func syncLatestLibraryElements(persistentStorage: PersistentStorage) -> Promise<Void> {
        return syncRecentSongs(persistentStorage: persistentStorage)
    }
    
    func syncFavoriteLibraryElements(persistentStorage: PersistentStorage) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        return firstly {
            self.ampacheXmlServerApi.requestFavoriteArtists()
        }.then { data in
            persistentStorage.persistentContainer.performAsync { companion in
                os_log("Sync favorite artists", log: self.log, type: .info)
                let oldFavoriteArtists = Set(companion.library.getFavoriteArtists())
                
                let parserDelegate = ArtistParserDelegate(library: companion.library, syncWave: companion.syncWave)
                try self.parse(data: data, delegate: parserDelegate)
                
                let notFavoriteArtistsAnymore = oldFavoriteArtists.subtracting(parserDelegate.artistsParsed)
                notFavoriteArtistsAnymore.forEach { $0.isFavorite = false }
            }
        }.then {
            self.ampacheXmlServerApi.requestFavoriteAlbums()
        }.then { data in
            persistentStorage.persistentContainer.performAsync { companion in
                os_log("Sync favorite albums", log: self.log, type: .info)
                let oldFavoriteAlbums = Set(companion.library.getFavoriteAlbums())
                
                let parserDelegate = AlbumParserDelegate(library: companion.library, syncWave: companion.syncWave)
                try self.parse(data: data, delegate: parserDelegate)
                
                let notFavoriteAlbumsAnymore = oldFavoriteAlbums.subtracting(parserDelegate.albumsParsed)
                notFavoriteAlbumsAnymore.forEach { $0.isFavorite = false }
            }
        }.then {
            self.ampacheXmlServerApi.requestFavoriteSongs()
        }.then { data in
            persistentStorage.persistentContainer.performAsync { companion in
                os_log("Sync favorite songs", log: self.log, type: .info)
                let oldFavoriteSongs = Set(companion.library.getFavoriteSongs())
                
                let parserDelegate = SongParserDelegate(library: companion.library, syncWave: companion.syncWave)
                try self.parse(data: data, delegate: parserDelegate)
                
                let notFavoriteSongsAnymore = oldFavoriteSongs.subtracting(parserDelegate.parsedSongs)
                notFavoriteSongsAnymore.forEach { $0.isFavorite = false }
            }
        }
    }
    
    func requestRandomSongs(playlist: Playlist, count: Int, persistentStorage: PersistentStorage) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        return firstly {
            ampacheXmlServerApi.requestRandomSongs(count: count)
        }.then { data in
            persistentStorage.persistentContainer.performAsync { companion in
                let parserDelegate = SongParserDelegate(library: companion.library, syncWave: companion.syncWave, parseNotifier: nil)
                try self.parse(data: data, delegate: parserDelegate)
                playlist.getManagedObject(in: companion.context, library: companion.library).append(playables: parserDelegate.parsedSongs)
            }
        }
    }
    
    func requestPodcastEpisodeDelete(podcastEpisode: PodcastEpisode) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        return firstly {
            ampacheXmlServerApi.requestPodcastEpisodeDelete(id: podcastEpisode.id)
        }.then { data in
            self.parseForError(data: data)
        }
    }

    func syncDownPlaylistsWithoutSongs(persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        return firstly {
            ampacheXmlServerApi.requestPlaylists()
        }.then { data in
            persistentContainer.performAsync { companion in
                let parserDelegate = PlaylistParserDelegate(library: companion.library, parseNotifier: nil)
                try self.parse(data: data, delegate: parserDelegate)
            }
        }
    }
    
    func syncDown(playlist: Playlist, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        os_log("Download playlist \"%s\" from server", log: log, type: .info, playlist.name)
        return firstly {
            validatePlaylistId(playlist: playlist, persistentContainer: persistentContainer)
        }.get {
            os_log("Sync songs of playlist \"%s\"", log: self.log, type: .info, playlist.name)
        }.then {
            self.ampacheXmlServerApi.requestPlaylistSongs(id: playlist.id)
        }.then { data in
            persistentContainer.performAsync { companion in
                let playlistAsync = playlist.getManagedObject(in: companion.context, library: companion.library)
                let parserDelegate = PlaylistSongsParserDelegate(playlist: playlistAsync, library: companion.library, syncWave: companion.syncWave)
                try self.parse(data: data, delegate: parserDelegate)
                playlistAsync.ensureConsistentItemOrder()
            }
        }
    }
    
    func syncUpload(playlistToAddSongs playlist: Playlist, songs: [Song], persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed, !songs.isEmpty else { return Promise.value }
        os_log("Upload SongsAdded on playlist \"%s\"", log: log, type: .info, playlist.name)
        return firstly {
            validatePlaylistId(playlist: playlist, persistentContainer: persistentContainer)
        }.then { () -> Promise<Void> in
            let playlistAddSongPromises = songs.compactMap { song in return {
                return firstly {
                    self.ampacheXmlServerApi.requestPlaylistAddSong(playlistId: playlist.id, songId: song.id)
                }.then { data in
                    self.parseForError(data: data)
                }
            }}
            return playlistAddSongPromises.resolveSequentially()
        }
    }
    
    func syncUpload(playlistToDeleteSong playlist: Playlist, index: Int, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        os_log("Upload SongDelete on playlist \"%s\" at index: %i", log: log, type: .info, playlist.name, index)
        return firstly {
            self.validatePlaylistId(playlist: playlist, persistentContainer: persistentContainer)
        }.then {
            self.ampacheXmlServerApi.requestPlaylistDeleteItem(id: playlist.id, index: index)
        }.then { data in
            self.parseForError(data: data)
        }
    }
    
    func syncUpload(playlistToUpdateName playlist: Playlist, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        os_log("Upload name on playlist to: \"%s\"", log: log, type: .info, playlist.name)
        return firstly {
            self.ampacheXmlServerApi.requestPlaylistEditOnlyName(id: playlist.id, name: playlist.name)
        }.then { data in
            self.parseForError(data: data)
        }
    }
    
    func syncUpload(playlistToUpdateOrder playlist: Playlist, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed, playlist.songCount > 0 else { return Promise.value }
        os_log("Upload OrderChange on playlist \"%s\"", log: log, type: .info, playlist.name)
        let songIds = playlist.playables.compactMap{ $0.id }
        guard !songIds.isEmpty else { return Promise.value }
        return firstly {
            self.ampacheXmlServerApi.requestPlaylistEdit(id: playlist.id, songsIds: songIds)
        }.then { data in
            self.parseForError(data: data)
        }
    }
    
    func syncUpload(playlistIdToDelete id: String) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        os_log("Upload Delete playlist \"%s\"", log: log, type: .info, id)
        return firstly {
            self.ampacheXmlServerApi.requestPlaylistDelete(id: id)
        }.then { data in
            self.parseForError(data: data)
        }
    }
    
    private func validatePlaylistId(playlist: Playlist, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        return firstly {
            self.ampacheXmlServerApi.requestPlaylist(id: playlist.id)
        }.then { data in
            persistentContainer.performAsync { companion in
                let playlistAsync = playlist.getManagedObject(in: companion.context, library: companion.library)
                let parserDelegate = PlaylistParserDelegate(library: companion.library, parseNotifier: nil, playlistToValidate: playlistAsync)
                try self.parse(data: data, delegate: parserDelegate)
            }
        }.then { () -> Promise<Void> in
            guard playlist.id == "" else { return Promise.value }
            os_log("Create playlist on server", log: self.log, type: .info)
            return firstly {
                self.ampacheXmlServerApi.requestPlaylistCreate(name: playlist.name)
            }.then { data in
                persistentContainer.performAsync { companion in
                    let playlistAsync = playlist.getManagedObject(in: companion.context, library: companion.library)
                    let parserDelegate = PlaylistParserDelegate(library: companion.library, parseNotifier: nil, playlistToValidate: playlistAsync)
                    try self.parse(data: data, delegate: parserDelegate)
                }
            }.then { () -> Promise<Void> in
                if playlist.id == "" {
                    os_log("Playlist id was not assigned after creation", log: self.log, type: .info)
                    return Promise(error: BackendError.incorrectServerBehavior(message: "Playlist id was not assigned after creation"))
                } else {
                    return Promise.value
                }
            }
        }
    }
    
    func syncDownPodcastsWithoutEpisodes(persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        return firstly {
            self.ampacheXmlServerApi.requestServerPodcastSupport()
        }.then { isSupported -> Promise<Void> in
            guard isSupported else { return Promise.value}
            return firstly {
                self.ampacheXmlServerApi.requestPodcasts()
            }.then { data in
                persistentContainer.performAsync { companion in
                    let oldPodcasts = Set(companion.library.getRemoteAvailablePodcasts())
                    
                    let parserDelegate = PodcastParserDelegate(library: companion.library, syncWave: companion.syncWave)
                    try self.parse(data: data, delegate: parserDelegate)
                    
                    let deletedPodcasts = oldPodcasts.subtracting(parserDelegate.parsedPodcasts)
                    deletedPodcasts.forEach {
                        os_log("Podcast <%s> is remote deleted", log: self.log, type: .info, $0.title)
                        $0.remoteStatus = .deleted
                    }
                }
            }
        }
    }
    
    func scrobble(song: Song, date: Date?) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        if let date = date {
            os_log("Scrobbled at %s: %s", log: log, type: .info, date.description, song.displayString)
        } else {
            os_log("Scrobble now: %s", log: log, type: .info, song.displayString)
        }
        return firstly {
            self.ampacheXmlServerApi.requestRecordPlay(songId: song.id, date: date)
        }.then { data in
            self.parseForError(data: data)
        }
    }
    
    func setRating(song: Song, rating: Int) -> Promise<Void> {
        guard isSyncAllowed, rating >= 0 && rating <= 5 else { return Promise.value }
        os_log("Rate %i stars: %s", log: log, type: .info, rating, song.displayString)
        return firstly {
            self.ampacheXmlServerApi.requestRate(songId: song.id, rating: rating)
        }.then { data in
            self.parseForError(data: data)
        }
    }
    
    func setRating(album: Album, rating: Int) -> Promise<Void> {
        guard isSyncAllowed, rating >= 0 && rating <= 5 else { return Promise.value }
        os_log("Rate %i stars: %s", log: log, type: .info, rating, album.name)
        return firstly {
            self.ampacheXmlServerApi.requestRate(albumId: album.id, rating: rating)
        }.then { data in
            self.parseForError(data: data)
        }
    }
    
    func setRating(artist: Artist, rating: Int) -> Promise<Void> {
        guard isSyncAllowed, rating >= 0 && rating <= 5 else { return Promise.value }
        os_log("Rate %i stars: %s", log: log, type: .info, rating, artist.name)
        return firstly {
            self.ampacheXmlServerApi.requestRate(artistId: artist.id, rating: rating)
        }.then { data in
            self.parseForError(data: data)
        }
    }
    
    func setFavorite(song: Song, isFavorite: Bool) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        os_log("Set Favorite %s: %s", log: log, type: .info, isFavorite ? "TRUE" : "FALSE", song.displayString)
        return firstly {
            self.ampacheXmlServerApi.requestSetFavorite(songId: song.id, isFavorite: isFavorite)
        }.then { data in
            self.parseForError(data: data)
        }
    }
    
    func setFavorite(album: Album, isFavorite: Bool) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        os_log("Set Favorite %s: %s", log: log, type: .info, isFavorite ? "TRUE" : "FALSE", album.name)
        return firstly {
            self.ampacheXmlServerApi.requestSetFavorite(albumId: album.id, isFavorite: isFavorite)
        }.then { data in
            self.parseForError(data: data)
        }
    }
    
    func setFavorite(artist: Artist, isFavorite: Bool) -> Promise<Void> {
        guard isSyncAllowed else { return Promise.value }
        os_log("Set Favorite %s: %s", log: log, type: .info, isFavorite ? "TRUE" : "FALSE", artist.name)
        return firstly {
            self.ampacheXmlServerApi.requestSetFavorite(artistId: artist.id, isFavorite: isFavorite)
        }.then { data in
            self.parseForError(data: data)
        }
    }

    func searchArtists(searchText: String, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed, searchText.count > 0 else { return Promise.value }
        os_log("Search artists via API: \"%s\"", log: log, type: .info, searchText)
        return firstly {
            ampacheXmlServerApi.requestSearchArtists(searchText: searchText)
        }.then { data in
            persistentContainer.performAsync { companion in
                let parserDelegate = ArtistParserDelegate(library: companion.library, syncWave: companion.syncWave)
                try self.parse(data: data, delegate: parserDelegate)
            }
        }
    }
    
    func searchAlbums(searchText: String, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed, searchText.count > 0 else { return Promise.value }
        os_log("Search albums via API: \"%s\"", log: log, type: .info, searchText)
        return firstly {
            ampacheXmlServerApi.requestSearchAlbums(searchText: searchText)
        }.then { data in
            persistentContainer.performAsync { companion in
                let parserDelegate = AlbumParserDelegate(library: companion.library, syncWave: companion.syncWave)
                try self.parse(data: data, delegate: parserDelegate)
            }
        }
    }
    
    func searchSongs(searchText: String, persistentContainer: NSPersistentContainer) -> Promise<Void> {
        guard isSyncAllowed, searchText.count > 0 else { return Promise.value }
        os_log("Search songs via API: \"%s\"", log: log, type: .info, searchText)
        return firstly {
            ampacheXmlServerApi.requestSearchSongs(searchText: searchText)
        }.then { data in
            persistentContainer.performAsync { companion in
                let parserDelegate = SongParserDelegate(library: companion.library, syncWave: companion.syncWave)
                try self.parse(data: data, delegate: parserDelegate)
            }
        }
    }
    
    private func parseForError(data: Data) -> Promise<Void> {
        Promise<Void> { seal in
            let parserDelegate = AmpacheXmlParser()
            try self.parse(data: data, delegate: parserDelegate)
            seal.fulfill(Void())
        }
    }
    
    private func parse(data: Data, delegate: AmpacheXmlParser) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        if let error = parser.parserError {
            os_log("Error during response parsing: %s", log: self.log, type: .error, error.localizedDescription)
            throw BackendError.parser
        }
        if let error = delegate.error, let ampacheError = error.asAmpacheError, ampacheError.shouldErrorBeDisplayedToUser {
            throw error
        }
    }

}
