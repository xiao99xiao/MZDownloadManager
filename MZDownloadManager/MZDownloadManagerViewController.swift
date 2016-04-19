//
//  MZDownloadManagerViewController.swift
//  MZDownloadManager
//
//  Created by Muhammad Zeeshan on 22/10/2014.
//  Copyright (c) 2014 ideamakerz. All rights reserved.
//

import UIKit

let alertControllerViewTag: Int = 500

class MZDownloadManagerViewController: UIViewController {
    
    @IBOutlet var bgDownloadTableView : UITableView?
    
    var selectedIndexPath : NSIndexPath!
    
    lazy var downloadManager: MZDownloadManager = {
        [unowned self] in
        let sessionIdentifer: String = "com.iosDevelopment.MZDownloadManager.BackgroundSession"
        let downloadmanager = MZDownloadManager(session: sessionIdentifer, delegate: self)
        return downloadmanager
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func refreshCellForIndex(downloadInfo: [String : AnyObject], index: Int) {
        let indexPath = NSIndexPath.init(forRow: index, inSection: 0)
        let cell = bgDownloadTableView?.cellForRowAtIndexPath(indexPath) as! MZDownloadingCell
        cell.updateCellForRowAtIndexPath(indexPath, downloadInfoDict: downloadInfo)
    }
}

// MARK: UITableViewDatasource Handler Extension

extension MZDownloadManagerViewController: UITableViewDataSource {
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return downloadManager.downloadingArray.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        let cellIdentifier : NSString = "MZDownloadingCell"
        let cell : MZDownloadingCell = tableView.dequeueReusableCellWithIdentifier(cellIdentifier as String, forIndexPath: indexPath) as! MZDownloadingCell
        
        let downloadInfo = downloadManager.downloadingArray[indexPath.row]
        cell.updateCellForRowAtIndexPath(indexPath, downloadInfoDict: downloadInfo)
        
        return cell
        
    }
}

extension MZDownloadManagerViewController: UITableViewDelegate {
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        selectedIndexPath = indexPath
        
        let downloadInfo = downloadManager.downloadingArray[indexPath.row]
        self.showAppropriateActionController(downloadInfo[kMZDownloadKeyStatus] as! String)
        
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
    }
    
}

// MARK: UIAlertController Handler Extension

extension MZDownloadManagerViewController {
    
    func showAppropriateActionController(requestStatus: String) {
        
        if requestStatus == RequestStatus.Downloading.description() {
            self.showAlertControllerForPause()
        } else if requestStatus == RequestStatus.Failed.description() {
            self.showAlertControllerForRetry()
        } else if requestStatus == RequestStatus.Paused.description() {
            self.showAlertControllerForStart()
        }
    }
    
    func showAlertControllerForPause() {
        
        let pauseAction = UIAlertAction(title: "Pause", style: .Default) { (alertAction: UIAlertAction) in
            self.downloadManager.pauseDownloadTaskAtIndex(self.selectedIndexPath.row)
        }
        
        let removeAction = UIAlertAction(title: "Remove", style: .Destructive) { (alertAction: UIAlertAction) in
            self.downloadManager.cancelTaskAtIndex(self.selectedIndexPath.row)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: nil)
        
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)
        alertController.view.tag = alertControllerViewTag
        alertController.addAction(pauseAction)
        alertController.addAction(removeAction)
        alertController.addAction(cancelAction)
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    func showAlertControllerForRetry() {
        
        let retryAction = UIAlertAction(title: "Retry", style: .Default) { (alertAction: UIAlertAction) in
            self.downloadManager.retryDownloadTaskAtIndex(self.selectedIndexPath.row)
        }
        
        let removeAction = UIAlertAction(title: "Remove", style: .Destructive) { (alertAction: UIAlertAction) in
            self.downloadManager.cancelTaskAtIndex(self.selectedIndexPath.row)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: nil)
        
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)
        alertController.view.tag = alertControllerViewTag
        alertController.addAction(retryAction)
        alertController.addAction(removeAction)
        alertController.addAction(cancelAction)
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    func showAlertControllerForStart() {
        
        let startAction = UIAlertAction(title: "Start", style: .Default) { (alertAction: UIAlertAction) in
            self.downloadManager.resumeDownloadTaskAtIndex(self.selectedIndexPath.row)
        }
        
        let removeAction = UIAlertAction(title: "Remove", style: .Destructive) { (alertAction: UIAlertAction) in
            self.downloadManager.cancelTaskAtIndex(self.selectedIndexPath.row)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: nil)
        
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)
        alertController.view.tag = alertControllerViewTag
        alertController.addAction(startAction)
        alertController.addAction(removeAction)
        alertController.addAction(cancelAction)
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    func safelyDismissAlertController() {
        /***** Dismiss alert controller if and only if it exists and it belongs to MZDownloadManager *****/
        /***** E.g App will eventually crash if download is completed and user tap remove *****/
        /***** As it was already removed from the array *****/
        if let controller = self.presentedViewController {
            guard controller is UIAlertController && controller.view.tag == alertControllerViewTag else {
                return
            }
            controller.dismissViewControllerAnimated(true, completion: nil)
        }
    }
}

extension MZDownloadManagerViewController: MZDownloadManagerDelegate {
    
    func downloadRequestStarted(downloadInfo: [String : AnyObject], index: Int) {
        let indexPath = NSIndexPath.init(forRow: index, inSection: 0)
        bgDownloadTableView?.insertRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimation.Fade)
    }
    
    func downloadRequestDidPopulatedInterruptedTasks(downloadInfo: [[String : AnyObject]]) {
        bgDownloadTableView?.reloadData()
    }
    
    func downloadRequestDidUpdateProgress(downloadInfo: [String : AnyObject], index: Int) {
        self.refreshCellForIndex(downloadInfo, index: index)
    }
    
    func downloadRequestDidPaused(downloadInfo: [String : AnyObject], index: Int) {
        self.refreshCellForIndex(downloadInfo, index: index)
    }
    
    func downloadRequestDidResumed(downloadInfo: [String : AnyObject], index: Int) {
        self.refreshCellForIndex(downloadInfo, index: index)
    }
    
    func downloadRequestCanceled(downloadInfo: [String : AnyObject], index: Int) {
        
        self.safelyDismissAlertController()
        
        let indexPath = NSIndexPath.init(forRow: index, inSection: 0)
        self.bgDownloadTableView?.deleteRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimation.Left)
    }
    
    func downloadRequestFinished(downloadInfo: [String : AnyObject], index: Int) {
        
        self.safelyDismissAlertController()
        self.bgDownloadTableView?.reloadData()
        
        downloadManager.presentNotificationForDownload("Ok", notifBody: "Download did completed")
        
        let indexPath = NSIndexPath.init(forRow: index, inSection: 0)
        self.bgDownloadTableView?.deleteRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimation.Left)
        
//        let docDirectoryPath : NSString = fileDest.stringByAppendingPathComponent(fileName as String)
//        NSNotificationCenter.defaultCenter().postNotificationName(DownloadCompletedNotif as String, object: docDirectoryPath)
    }
    
    func downloadRequestDidFailedWithError(error: NSError, downloadInfo: [String : AnyObject], index: Int) {
        self.safelyDismissAlertController()
        self.refreshCellForIndex(downloadInfo, index: index)
    }
}


