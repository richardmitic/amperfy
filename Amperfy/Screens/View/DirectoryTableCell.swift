//
//  DirectoryTableCell.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 25.05.21.
//  Copyright (c) 2021 Maximilian Bauer. All rights reserved.
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
import CoreData
import AmperfyKit

class DirectoryTableCell: BasicTableCell {
    
    @IBOutlet weak var infoLabel: UILabel!
    @IBOutlet weak var artworkImage: LibraryEntityImage!
    @IBOutlet weak var iconLabel: UILabel!
    
    static let rowHeight: CGFloat = 40.0 + margin.bottom + margin.top
    
    private var folder: MusicFolder?
    private var directory: Directory?
    var entity: AbstractLibraryEntity? {
        return directory
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        appDelegate.notificationHandler.register(self, selector: #selector(self.artworkDownloadFinishedSuccessful(notification:)), name: .downloadFinishedSuccess, object: appDelegate.artworkDownloadManager)
    }
    
    deinit {
        appDelegate.notificationHandler.remove(self, name: .downloadFinishedSuccess, object: appDelegate.artworkDownloadManager)
    }

    func display(folder: MusicFolder) {
        self.folder = folder
        self.directory = nil
        refresh()
    }
    
    func display(directory: Directory) {
        self.folder = nil
        self.directory = directory
        if let artwork = directory.artwork {
            appDelegate.artworkDownloadManager.download(object: artwork)
        }
        refresh()
    }
    
    @objc private func artworkDownloadFinishedSuccessful(notification: Notification) {
        if let downloadNotification = DownloadNotification.fromNotification(notification),
           let artwork = entity?.artwork,
           artwork.uniqueID == downloadNotification.id {
            refresh()
        }
    }
    
    private func refresh() {
        iconLabel.isHidden = true
        artworkImage.isHidden = true
        
        if let directory = directory {
            infoLabel.text = directory.name
            artworkImage.display(entity: directory)
            if let artwork = directory.artwork, let directoryImage = artwork.image, directoryImage != directory.defaultImage {
                artworkImage.isHidden = false
            } else {
                iconLabel.isHidden = false
            }
        } else if let folder = folder {
            infoLabel.text = folder.name
            iconLabel.isHidden = false
        }
    }

}
