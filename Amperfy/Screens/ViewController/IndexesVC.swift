//
//  IndexesVC.swift
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
import PromiseKit

class IndexesVC: SingleFetchedResultsTableViewController<DirectoryMO> {
    
    var musicFolder: MusicFolder!
    private var fetchedResultsController: MusicFolderDirectoriesFetchedResultsController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        appDelegate.userStatistics.visited(.indexes)
        
        fetchedResultsController = MusicFolderDirectoriesFetchedResultsController(for: musicFolder, managedObjectContext: appDelegate.persistentStorage.context, isGroupedInAlphabeticSections: false)
        singleFetchedResultsController = fetchedResultsController
        
        navigationItem.title = musicFolder.name
        configureSearchController(placeholder: "Search in \"Directories\"")
        tableView.register(nibName: DirectoryTableCell.typeName)
        tableView.rowHeight = DirectoryTableCell.rowHeight
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard appDelegate.persistentStorage.settings.isOnlineMode else { return }
        firstly {
            self.appDelegate.backendApi.createLibrarySyncer().syncIndexes(musicFolder: musicFolder, persistentContainer: self.appDelegate.persistentStorage.persistentContainer)
        }.catch { error in
            self.appDelegate.eventLogger.report(topic: "Indexes Sync", error: error)
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: DirectoryTableCell = dequeueCell(for: tableView, at: indexPath)
        let directory = fetchedResultsController.getWrappedEntity(at: indexPath)
        cell.display(directory: directory)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let directory = fetchedResultsController.getWrappedEntity(at: indexPath)
        performSegue(withIdentifier: Segues.toDirectories.rawValue, sender: directory)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == Segues.toDirectories.rawValue {
            let vc = segue.destination as! DirectoriesVC
            let directory = sender as! Directory
            vc.directory = directory
        }
    }
    
    override func updateSearchResults(for searchController: UISearchController) {
        fetchedResultsController.search(searchText: searchController.searchBar.text ?? "")
        tableView.reloadData()
    }

}
