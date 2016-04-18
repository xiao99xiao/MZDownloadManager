//
//  MZDownloadManagerViewController.swift
//  MZDownloadManager
//
//  Created by Muhammad Zeeshan on 22/10/2014.
//  Copyright (c) 2014 ideamakerz. All rights reserved.
//

import UIKit

let kMZDownloadKeyURL        : String = "URL"
let kMZDownloadKeyStartTime  : String = "startTime"
let kMZDownloadKeyFileName   : String = "fileName"
let kMZDownloadKeyProgress   : String = "progress"
let kMZDownloadKeyTask       : String = "downloadTask"
let kMZDownloadKeyStatus     : String = "requestStatus"
let kMZDownloadKeyDetails    : String = "downloadDetails"
let kMZDownloadKeyResumeData : String = "resumedata"

private let sessionIdentifer: String = "com.iosDevelopment.MZDownloadManager.BackgroundSession"

enum RequestStatus: Int {
    case Unknown, GettingInfo, Downloading, Paused, Failed
    
    func description() -> String {
        switch self {
            case .GettingInfo:
                return "GettingInfo"
            case .Downloading:
                return "Downloading"
            case .Paused:
                return "Paused"
            case .Failed:
                return "Failed"
            default:
                return "Unknown"
        }
    }
}

let alertControllerViewTag: Int = 500

@objc protocol MZDownloadDelegate {
    /**A delegate method called each time whenever new download task is start downloading
    */
    optional func downloadRequestStarted(downloadTask: NSURLSessionDownloadTask)
    /**A delegate method called each time whenever any download task is cancelled by the user
    */
    optional func downloadRequestCanceled(downloadTask: NSURLSessionDownloadTask)
    /**A delegate method called each time whenever any download task is finished successfully
    */
    optional func downloadRequestFinished(fileName: NSString)
    
    optional func downloadRequestDidFailedWithError(error: NSError, downloadTask: NSURLSessionDownloadTask)
}

class MZDownloadManagerViewController: UIViewController {
    
    @IBOutlet var bgDownloadTableView : UITableView?
    
    var sessionManager    : NSURLSession!
    var downloadingArray  : NSMutableArray!
    
    var selectedIndexPath : NSIndexPath!
    
    var delegate          : MZDownloadDelegate?

    var isViewLoaded      : Bool! = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.isViewLoaded = true
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - My Methods -
    
    func backgroundSession() -> NSURLSession {
        struct sessionStruct {
            static var onceToken : dispatch_once_t = 0;
            static var session   : NSURLSession? = nil
        }
        
        dispatch_once(&sessionStruct.onceToken, { () -> Void in
            let sessionConfiguration : NSURLSessionConfiguration
            
            sessionConfiguration = NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier(sessionIdentifer)
            sessionStruct.session = NSURLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        })
        return sessionStruct.session!
    }
    
    func tasks() -> NSArray {
        return self.tasksForKeyPath("tasks")
    }
    
    func dataTasks() -> NSArray {
        return self.tasksForKeyPath("dataTasks")
    }
    
    func uploadTasks() -> NSArray {
        return self.tasksForKeyPath("uploadTasks")
    }
    
    func downloadTasks() -> NSArray {
        return self.tasksForKeyPath("downloadTasks")
    }
    
    func tasksForKeyPath(keyPath: NSString) -> NSArray {
        var tasks     : NSArray! = NSArray()
        let semaphore : dispatch_semaphore_t = dispatch_semaphore_create(0)
        sessionManager.getTasksWithCompletionHandler { (dataTasks, uploadTasks, downloadTasks) -> Void in
            if keyPath == "dataTasks" {
                tasks = dataTasks
            } else if keyPath == "uploadTasks" {
                tasks = uploadTasks
                
            } else if keyPath == "downloadTasks" {
                if let pendingTasks: NSArray = downloadTasks {
                    tasks = pendingTasks
                    print("pending tasks \(tasks)")
                }
            } else if keyPath == "tasks" {
                tasks = ([dataTasks, uploadTasks, downloadTasks] as AnyObject).valueForKeyPath("@unionOfArrays.self") as! NSArray
                
                print("pending task\(tasks)")
            }
            
            dispatch_semaphore_signal(semaphore)
        }
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
        return tasks
    }
    
    func addDownloadTask(fileName: NSString, fileURL: NSString) {
        
        let url          : NSURL = NSURL(string: fileURL as String)!
        let request      : NSURLRequest = NSURLRequest(URL: url)
        let downloadTask : NSURLSessionDownloadTask = sessionManager.downloadTaskWithRequest(request)
        
        print("session manager:\(sessionManager) url:\(url) request:\(request)")
        
        downloadTask.resume()
        
        let downloadInfo : NSMutableDictionary = NSMutableDictionary()
        downloadInfo.setObject(fileURL, forKey: kMZDownloadKeyURL)
        downloadInfo.setObject(fileName, forKey: kMZDownloadKeyFileName)
        
        let jsonData     : NSData = try! NSJSONSerialization.dataWithJSONObject(downloadInfo, options: NSJSONWritingOptions.PrettyPrinted)
        let jsonString   : NSString = NSString(data: jsonData, encoding: NSUTF8StringEncoding)!
        downloadTask.taskDescription = jsonString as String
        
        downloadInfo.setObject(NSDate(), forKey: kMZDownloadKeyStartTime)
        downloadInfo.setObject(RequestStatus.Downloading.description(), forKey: kMZDownloadKeyStatus)
        downloadInfo.setObject(downloadTask, forKey: kMZDownloadKeyTask)
        
        let indexPath    : NSIndexPath = NSIndexPath(forRow: self.downloadingArray.count, inSection: 0)
        
        self.downloadingArray.addObject(downloadInfo)
        bgDownloadTableView?.insertRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimation.Fade)
        
        self.delegate?.downloadRequestStarted?(downloadTask)
    }
    
    func populateOtherDownloadTasks() {
        
        let downloadTasks : NSArray = self.downloadTasks()
        
        for downloadTask in downloadTasks {

            let taskDescStr: String? = downloadTask.taskDescription
            let taskDescription: NSData = (taskDescStr?.dataUsingEncoding(NSUTF8StringEncoding))!
            
            var downloadInfo: NSMutableDictionary?
            do {
                downloadInfo = try NSJSONSerialization.JSONObjectWithData(taskDescription, options: .AllowFragments).mutableCopy() as? NSMutableDictionary
            } catch let jsonError as NSError {
                print("Error while retreiving json value:\(jsonError)")
                downloadInfo = NSMutableDictionary()
            }
            
            downloadInfo?.setObject(downloadTask, forKey: kMZDownloadKeyTask)
            downloadInfo?.setObject(NSDate(), forKey: kMZDownloadKeyStartTime)
            
            let taskState       : NSURLSessionTaskState = downloadTask.state
            
            if taskState == NSURLSessionTaskState.Running {
                downloadInfo?.setObject(RequestStatus.Downloading.description(), forKey: kMZDownloadKeyStatus)
                self.downloadingArray.addObject(downloadInfo!)
            } else if(taskState == NSURLSessionTaskState.Suspended) {
                downloadInfo?.setObject(RequestStatus.Paused.description(), forKey: kMZDownloadKeyStatus)
                self.downloadingArray.addObject(downloadInfo!)
            } else {
                downloadInfo?.setObject(RequestStatus.Failed.description(), forKey: kMZDownloadKeyStatus)
            }

            if let _ = downloadInfo {
                
            } else {
                downloadTask.cancel()
            }
            
        }
    }

    func presentNotificationForDownload(fileName : NSString) {
        let application = UIApplication.sharedApplication()
        let applicationState = application.applicationState
        
        if applicationState == UIApplicationState.Background {
            let localNotification = UILocalNotification()
            localNotification.alertBody = "Downloading complete of \(fileName)"
            localNotification.alertAction = "Background Transfer Download!"
            localNotification.soundName = UILocalNotificationDefaultSoundName
            localNotification.applicationIconBadgeNumber += 1
            application.presentLocalNotificationNow(localNotification)
        }
    }
    
    func isValidResumeData(resumeData: NSData?) -> Bool {
        
        guard resumeData != nil || resumeData?.length > 0 else {
            return false
        }

        do {
            var resumeDictionary : AnyObject!
            resumeDictionary = try NSPropertyListSerialization.propertyListWithData(resumeData!, options: .Immutable, format: nil)
            var localFilePath : NSString? = resumeDictionary?.objectForKey("NSURLSessionResumeInfoLocalPath") as? NSString
            
            if localFilePath == nil || localFilePath?.length < 1 {
               localFilePath = NSTemporaryDirectory() + (resumeDictionary["NSURLSessionResumeInfoTempFileName"] as! String)
            }
            
            let fileManager : NSFileManager! = NSFileManager.defaultManager()
            debugPrint("resume data file exists: \(fileManager.fileExistsAtPath(localFilePath! as String))")
            return fileManager.fileExistsAtPath(localFilePath! as String)
        } catch let error as NSError {
            debugPrint("resume data is nil: \(error)")
            return false
        }
    }
}

// MARK: UITableViewDatasource Handler Extension

extension MZDownloadManagerViewController: UITableViewDataSource {
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.downloadingArray.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        let cellIdentifier : NSString = "MZDownloadingCell"
        let cell : MZDownloadingCell = tableView.dequeueReusableCellWithIdentifier(cellIdentifier as String, forIndexPath: indexPath) as! MZDownloadingCell
        
        let downloadInfo = self.downloadingArray.objectAtIndex(indexPath.row) as! NSMutableDictionary
        cell.updateCellForRowAtIndexPath(indexPath, downloadInfoDict: downloadInfo)
        
        return cell
        
    }
}

extension MZDownloadManagerViewController: UITableViewDelegate {
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        selectedIndexPath = indexPath
        let downloadInfoDict : NSMutableDictionary = self.downloadingArray.objectAtIndex(indexPath.row) as! NSMutableDictionary
        let downloadStatus = downloadInfoDict.objectForKey(kMZDownloadKeyStatus) as! String
        
        self.showAppropriateActionController(downloadStatus)
        
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
            
            let downloadInfo = self.downloadingArray.objectAtIndex(self.selectedIndexPath.row) as! NSMutableDictionary
            let downloadTask = downloadInfo.objectForKey(kMZDownloadKeyTask) as! NSURLSessionDownloadTask
            let cell = self.bgDownloadTableView?.cellForRowAtIndexPath(self.selectedIndexPath) as! MZDownloadingCell
            
            downloadTask.suspend()
            downloadInfo.setObject(RequestStatus.Paused.description(), forKey: kMZDownloadKeyStatus)
            downloadInfo.setObject(NSDate(), forKey: kMZDownloadKeyStartTime)
            
            self.downloadingArray.replaceObjectAtIndex(self.selectedIndexPath.row, withObject: downloadInfo)
            cell.updateCellForRowAtIndexPath(self.selectedIndexPath, downloadInfoDict: downloadInfo)
        }
        
        let removeAction = UIAlertAction(title: "Remove", style: .Destructive) { (alertAction: UIAlertAction) in
            self.removeRequest()
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
            
            let downloadInfo = self.downloadingArray.objectAtIndex(self.selectedIndexPath.row) as! NSMutableDictionary
            let downloadTask = downloadInfo.objectForKey(kMZDownloadKeyTask) as! NSURLSessionDownloadTask
            let cell = self.bgDownloadTableView?.cellForRowAtIndexPath(self.selectedIndexPath) as! MZDownloadingCell
            
            downloadTask.resume()
            downloadInfo.setObject(RequestStatus.Downloading.description(), forKey: kMZDownloadKeyStatus)
            downloadInfo.setObject(NSDate(), forKey: kMZDownloadKeyStartTime)
            downloadInfo.setObject(downloadTask, forKey: kMZDownloadKeyTask)
            
            self.downloadingArray.replaceObjectAtIndex(self.selectedIndexPath.row, withObject: downloadInfo)
            cell.updateCellForRowAtIndexPath(self.selectedIndexPath, downloadInfoDict: downloadInfo)
        }
        
        let removeAction = UIAlertAction(title: "Remove", style: .Destructive) { (alertAction: UIAlertAction) in
            self.removeRequest()
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
            
            let downloadInfo = self.downloadingArray.objectAtIndex(self.selectedIndexPath.row) as! NSMutableDictionary
            let downloadTask = downloadInfo.objectForKey(kMZDownloadKeyTask) as! NSURLSessionDownloadTask
            let cell = self.bgDownloadTableView?.cellForRowAtIndexPath(self.selectedIndexPath) as! MZDownloadingCell
            
            downloadTask.resume()
            downloadInfo.setObject(RequestStatus.Downloading.description(), forKey: kMZDownloadKeyStatus)
            
            self.downloadingArray.replaceObjectAtIndex(self.selectedIndexPath.row, withObject: downloadInfo)
            cell.updateCellForRowAtIndexPath(self.selectedIndexPath, downloadInfoDict: downloadInfo)
        }
        
        let removeAction = UIAlertAction(title: "Remove", style: .Destructive) { (alertAction: UIAlertAction) in
            self.removeRequest()
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: nil)
        
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)
        alertController.view.tag = alertControllerViewTag
        alertController.addAction(startAction)
        alertController.addAction(removeAction)
        alertController.addAction(cancelAction)
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    /***** Common function for removing download task from array *****/
    func removeRequest() {
        
        let downloadInfo = self.downloadingArray.objectAtIndex(self.selectedIndexPath.row) as! NSMutableDictionary
        let downloadTask = downloadInfo.objectForKey(kMZDownloadKeyTask) as! NSURLSessionDownloadTask
        
        downloadTask.cancel()
        
        self.downloadingArray.removeObjectAtIndex(self.selectedIndexPath.row)
        self.bgDownloadTableView?.deleteRowsAtIndexPaths([self.selectedIndexPath], withRowAnimation: UITableViewRowAnimation.Left)
    }
    
    func safelyDismissAlertController() {
        /***** Dismiss alert controller if and only if it exists and it belongs to MZDownloadManager *****/
        /***** E.g App will eventually crash if download is completed and user tap remove *****/
        /***** As it was already removed from the array *****/
        if isViewLoaded == true {
            if let controller = self.presentedViewController {
                guard controller is UIAlertController && controller.view.tag == alertControllerViewTag else {
                    return
                }
                controller.dismissViewControllerAnimated(true, completion: nil)
            }
        }
    }
}

extension MZDownloadManagerViewController: NSURLSessionDelegate {
    
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        for (indexOfObject, downloadDict) in self.downloadingArray.enumerate() {
            if downloadTask.isEqual(downloadDict.objectForKey(kMZDownloadKeyTask)) {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    
                    let receivedBytesCount      : Double = Double(downloadTask.countOfBytesReceived)
                    let totalBytesCount         : Double = Double(downloadTask.countOfBytesExpectedToReceive)
                    let progress                : Float = Float(receivedBytesCount / totalBytesCount)
                    
                    let taskStartedDate         : NSDate = downloadDict.objectForKey(kMZDownloadKeyStartTime) as! NSDate
                    let timeInterval            : NSTimeInterval = taskStartedDate.timeIntervalSinceNow
                    let downloadTime            : NSTimeInterval = NSTimeInterval(-1 * timeInterval)
                    
                    let speed                   : Float = Float(totalBytesWritten) / Float(downloadTime)
                    
                    let indexPath               : NSIndexPath = NSIndexPath(forRow: indexOfObject, inSection: 0)
                    
                    let remainingContentLength  : Int64 = totalBytesExpectedToWrite - totalBytesWritten
                    let remainingTime           : Int64 = remainingContentLength / Int64(speed)
                    let hours                   : Int = Int(remainingTime) / 3600
                    let minutes                 : Int = (Int(remainingTime) - hours * 3600) / 60
                    let seconds                 : Int = Int(remainingTime) - hours * 3600 - minutes * 60
                    let fileSizeUnit            : Float = MZUtility.calculateFileSizeInUnit(totalBytesExpectedToWrite)
                    let unit                    : NSString = MZUtility.calculateUnit(totalBytesExpectedToWrite)
                    let fileSizeInUnits         : NSString = NSString(format: "%.2f \(unit)", fileSizeUnit)
                    let fileSizeDownloaded      : Float = MZUtility.calculateFileSizeInUnit(totalBytesWritten)
                    let downloadedSizeUnit      : NSString = MZUtility.calculateUnit(totalBytesWritten)
                    let downloadedFileSizeUnits : NSString = NSString(format: "%.2f \(downloadedSizeUnit)", fileSizeDownloaded)
                    let speedSize               : Float = MZUtility.calculateFileSizeInUnit(Int64(speed))
                    let speedUnit               : NSString = MZUtility.calculateUnit(Int64(speed))
                    let speedInUnits            : NSString = NSString(format: "%.2f \(speedUnit)", speedSize)
                    let remainingTimeStr        : NSMutableString = NSMutableString()
                    let detailLabelText         : NSMutableString = NSMutableString()
                    
                    if self.isViewLoaded == true {
                        if hours > 0 {
                            remainingTimeStr.appendString("\(hours) Hours ")
                        }
                        if minutes > 0 {
                            remainingTimeStr.appendString("\(minutes) Min ")
                        }
                        if seconds > 0 {
                            remainingTimeStr.appendString("\(seconds) sec")
                        }
                        
                        detailLabelText.appendFormat("File Size: \(fileSizeInUnits)\nDownloaded: \(downloadedFileSizeUnits) (%.2f%%)\nSpeed: \(speedInUnits)/sec\n", progress*100.0)
                        
                        if  progress == 1.0 {
                            detailLabelText.appendString("Time Left: Please wait...")
                        } else {
                            detailLabelText.appendString("Time Left: \(remainingTimeStr)")
                        }
                        
                        let cell: MZDownloadingCell? = self.bgDownloadTableView?.cellForRowAtIndexPath(indexPath) as? MZDownloadingCell
                        cell?.progressDownload?.progress = progress
                        cell?.lblDetails?.text = detailLabelText as String
                        
                        downloadDict.setObject("\(progress)", forKey: kMZDownloadKeyProgress)
                        downloadDict.setObject(detailLabelText, forKey: kMZDownloadKeyDetails)
                    }
                })
                break
            }
        }
    }
    
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        for downloadDict in self.downloadingArray {
            if downloadTask.isEqual(downloadDict.objectForKey(kMZDownloadKeyTask)) {
                let fileName        : NSString = downloadDict.objectForKey(kMZDownloadKeyFileName) as! NSString
                let destinationPath : NSString = fileDest.stringByAppendingPathComponent(fileName as String)
                let fileURL         : NSURL = NSURL(fileURLWithPath: destinationPath as String)
                debugPrint("directory path = \(destinationPath)")
                
                let fileManager : NSFileManager = NSFileManager.defaultManager()
                do {
                    try fileManager.moveItemAtURL(location, toURL: fileURL)
                } catch let error as NSError {
                    debugPrint("Error while moving downloaded file to destination path:\(error)")
                    let errorMessage : NSString = error.localizedDescription as NSString
                    
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        MZUtility.showAlertViewWithTitle(kAlertTitle, msg: errorMessage)
                    })
                }
                
                break
            }
        }
    }
    
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
        debugPrint("task id: \(task.taskIdentifier)")
        if error?.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey]?.integerValue == NSURLErrorCancelledReasonUserForceQuitApplication || error?.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey]?.integerValue == NSURLErrorCancelledReasonBackgroundUpdatesDisabled {
            
            do {
                let taskDescriptionData: NSData = (task.taskDescription?.dataUsingEncoding(NSUTF8StringEncoding))!
                let taskInfoDict = try NSJSONSerialization.JSONObjectWithData(taskDescriptionData, options: .AllowFragments).mutableCopy() as? NSMutableDictionary
                
                let fileName        : NSString = taskInfoDict?.objectForKey(kMZDownloadKeyFileName) as! NSString
                let fileURL         : NSString = taskInfoDict?.objectForKey(kMZDownloadKeyURL) as! NSString
                let downloadInfo    : NSMutableDictionary = NSMutableDictionary()
                downloadInfo.setObject(fileName, forKey: kMZDownloadKeyFileName)
                downloadInfo.setObject(fileURL, forKey: kMZDownloadKeyURL)
                downloadInfo.setObject(RequestStatus.Failed.description(), forKey: kMZDownloadKeyStatus)
                
                let resumeData = error?.userInfo[NSURLSessionDownloadTaskResumeData] as? NSData
                
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    var newTask = task
                    if self.isValidResumeData(resumeData) == true {
                        newTask = self.sessionManager.downloadTaskWithResumeData(resumeData!)
                    } else {
                        newTask = self.sessionManager.downloadTaskWithURL(NSURL(string: fileURL as String)!)
                    }
                    
                    newTask.taskDescription = task.taskDescription
                    downloadInfo.setObject(newTask as! NSURLSessionDownloadTask, forKey: kMZDownloadKeyTask)
                    
                    self.downloadingArray.addObject(downloadInfo)
                    
                    self.safelyDismissAlertController()
                    self.bgDownloadTableView?.reloadData()
                    
                })
                
            } catch let jsonError as NSError {
                print("Error while retreiving json value: didCompleteWithError \(jsonError.localizedDescription)")
            }
        } else {
            for(indexOfObject, downloadInfo) in self.downloadingArray.enumerate() {
                if task.isEqual(downloadInfo.objectForKey(kMZDownloadKeyTask)) {
                    if error?.code == NSURLErrorCancelled || error == nil {
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            self.safelyDismissAlertController()
                            let fileName : NSString = downloadInfo.objectForKey(kMZDownloadKeyFileName) as! NSString
                            
                            self.presentNotificationForDownload(fileName)
                            
                            self.downloadingArray.removeObjectAtIndex(indexOfObject)
                            let indexPath : NSIndexPath = NSIndexPath(forRow: indexOfObject, inSection: 0)
                            self.bgDownloadTableView?.deleteRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimation.Left)
                            
                            if error == nil {
                                self.delegate?.downloadRequestFinished?(fileName)
                            } else {
                                self.delegate?.downloadRequestCanceled?(task as! NSURLSessionDownloadTask)
                            }
                            
                        })
                    } else {
                        let fileURL     : NSString = downloadInfo.objectForKey(kMZDownloadKeyURL) as! NSString
                        let resumeData = error?.userInfo[NSURLSessionDownloadTaskResumeData] as? NSData
                        
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            
                            var newTask = task
                            if self.isValidResumeData(resumeData) == true {
                                newTask = self.sessionManager.downloadTaskWithResumeData(resumeData!)
                            } else {
                                newTask = self.sessionManager.downloadTaskWithURL(NSURL(string: fileURL as String)!)
                            }
                            
                            newTask.taskDescription = task.taskDescription
                            downloadInfo.setObject(RequestStatus.Failed.description(), forKey: kMZDownloadKeyStatus)
                            downloadInfo.setObject(newTask as! NSURLSessionDownloadTask, forKey: kMZDownloadKeyTask)
                            
                            self.downloadingArray.replaceObjectAtIndex(indexOfObject, withObject: downloadInfo)
                            
                            self.safelyDismissAlertController()
                            self.bgDownloadTableView?.reloadData()
                            
                            if let error = error {
                                self.delegate?.downloadRequestDidFailedWithError?(error, downloadTask: task as! NSURLSessionDownloadTask)
                            } else {
                                let error: NSError = NSError(domain: "MZDownloadManagerDomain", code: 1000, userInfo: [NSLocalizedDescriptionKey : "Unknown error occurred"])
                                self.delegate?.downloadRequestDidFailedWithError?(error, downloadTask: task as! NSURLSessionDownloadTask)
                            }
                            
                        })
                    }
                    break;
                }
            }
        }
    }
    
    func URLSessionDidFinishEventsForBackgroundURLSession(session: NSURLSession) {
        let appDelegate : AppDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
        
        if let _ = appDelegate.backgroundSessionCompletionHandler {
            let completionHandler = appDelegate.backgroundSessionCompletionHandler
            appDelegate.backgroundSessionCompletionHandler = nil
            completionHandler!()
        }
        
        print("All tasks are finished")
    }
}
