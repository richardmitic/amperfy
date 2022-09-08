//
//  BackgroundLibrarySyncer.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 12.04.22.
//  Copyright (c) 2022 Maximilian Bauer. All rights reserved.
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
import os.log
import PromiseKit

public class BackgroundLibrarySyncer: AbstractBackgroundLibrarySyncer {
    
    private let persistentStorage: PersistentStorage
    private let library: LibraryStorage
    private let backendApi: BackendApi
    private let playableDownloadManager: DownloadManageable
    private let eventLogger: EventLogger
    
    private let log = OSLog(subsystem: "Amperfy", category: "BackgroundLibrarySyncer")
    private let activeDispatchGroup = DispatchGroup()
    private let syncSemaphore = DispatchSemaphore(value: 0)
    private var isRunning = false
    private var isCurrentlyActive = false
    
    init(persistentStorage: PersistentStorage, backendApi: BackendApi, playableDownloadManager: DownloadManageable, eventLogger: EventLogger) {
        self.persistentStorage = persistentStorage
        self.library = LibraryStorage(context: self.persistentStorage.context)
        self.backendApi = backendApi
        self.playableDownloadManager = playableDownloadManager
        self.eventLogger = eventLogger
    }
    
    var isActive: Bool { return isCurrentlyActive }
    
    public func start() {
        isRunning = true
        if !isCurrentlyActive {
            isCurrentlyActive = true
            syncAlbumSongsInBackground()
        }
    }
    
    public func stop() {
        isRunning = false
    }

    public func stopAndWait() {
        isRunning = false
        activeDispatchGroup.wait()
    }
    
    private func syncAlbumSongsInBackground() {
        DispatchQueue.global().async {
            self.activeDispatchGroup.enter()
            os_log("start", log: self.log, type: .info)
            
            if self.isRunning, self.persistentStorage.settings.isOnlineMode, Reachability.isConnectedToNetwork() {
                firstly {
                    AutoDownloadLibrarySyncer(persistentStorage: self.persistentStorage, backendApi: self.backendApi, playableDownloadManager: self.playableDownloadManager)
                        .syncLatestLibraryElements()
                }.catch { error in
                    self.eventLogger.report(topic: "Latest Library Elements Background Sync", error: error, displayPopup: false)
                }.finally {
                    self.syncSemaphore.signal()
                }
                self.syncSemaphore.wait()
            }

            while self.isRunning, self.persistentStorage.settings.isOnlineMode, Reachability.isConnectedToNetwork() {
                firstly { () -> Promise<Void> in
                    let albumToSync = self.library.getAlbumWithoutSyncedSongs()
                    guard let albumToSync = albumToSync else {
                        self.isRunning = false
                        return Promise.value
                    }
                    return albumToSync.fetchFromServer(storage: self.persistentStorage, backendApi: self.backendApi, playableDownloadManager: self.playableDownloadManager)
                }.catch { error in
                    self.eventLogger.report(topic: "Album Background Sync", error: error, displayPopup: false)
                }.finally {
                    self.syncSemaphore.signal()
                }
                self.syncSemaphore.wait()
            }
            
            os_log("stopped", log: self.log, type: .info)
            self.isCurrentlyActive = false
            self.activeDispatchGroup.leave()
        }
    }

}
