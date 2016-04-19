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
    var downloadingArray  : [[String : AnyObject]] = []
    
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
                    debugPrint("pending tasks \(tasks)")
                }
            } else if keyPath == "tasks" {
                tasks = ([dataTasks, uploadTasks, downloadTasks] as AnyObject).valueForKeyPath("@unionOfArrays.self") as! NSArray
                
                debugPrint("pending task\(tasks)")
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
        
        debugPrint("session manager:\(sessionManager) url:\(url) request:\(request)")
        
        downloadTask.resume()
        
        var downloadInfo: [String : AnyObject] = Dictionary()
        downloadInfo[kMZDownloadKeyURL] = fileURL
        downloadInfo[kMZDownloadKeyFileName] = fileName
        
        let jsonData     : NSData = try! NSJSONSerialization.dataWithJSONObject(downloadInfo, options: NSJSONWritingOptions.PrettyPrinted)
        let jsonString   : NSString = NSString(data: jsonData, encoding: NSUTF8StringEncoding)!
        downloadTask.taskDescription = jsonString as String
        
        downloadInfo[kMZDownloadKeyStartTime] = NSDate()
        downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Downloading.description()
        downloadInfo[kMZDownloadKeyTask] = downloadTask
        
        let indexPath = NSIndexPath(forRow: self.downloadingArray.count, inSection: 0)
        
        downloadingArray.append(downloadInfo)
        bgDownloadTableView?.insertRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimation.Fade)
        
        delegate?.downloadRequestStarted?(downloadTask)
    }
    
    func populateOtherDownloadTasks() {
        
        let downloadTasks = self.downloadTasks()
        
        for downloadTask in downloadTasks {

            let taskDescStr: String? = downloadTask.taskDescription
            let taskDescription: NSData = (taskDescStr?.dataUsingEncoding(NSUTF8StringEncoding))!
            
            var downloadInfo: [String : AnyObject] = Dictionary()
            do {
                downloadInfo = try NSJSONSerialization.JSONObjectWithData(taskDescription, options: .AllowFragments) as! [String : AnyObject]
                downloadInfo[kMZDownloadKeyTask] = downloadTask
                downloadInfo[kMZDownloadKeyStartTime] = NSDate()
                
                if downloadTask.state == .Running {
                    downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Downloading.description()
                    downloadingArray.append(downloadInfo)
                } else if(downloadTask.state == .Suspended) {
                    downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Paused.description()
                    downloadingArray.append(downloadInfo)
                } else {
                    downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Failed.description()
                }
                
            } catch let jsonError as NSError {
                debugPrint("Error while retreiving json value:\(jsonError)")
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
        
        let downloadInfo = downloadingArray[indexPath.row]
        cell.updateCellForRowAtIndexPath(indexPath, downloadInfoDict: downloadInfo)
        
        return cell
        
    }
}

extension MZDownloadManagerViewController: UITableViewDelegate {
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        selectedIndexPath = indexPath
        
        let downloadInfo = downloadingArray[indexPath.row]
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
            
            var downloadInfo = self.downloadingArray[self.selectedIndexPath.row]
            let downloadTask = downloadInfo[kMZDownloadKeyTask] as! NSURLSessionDownloadTask
            let cell = self.bgDownloadTableView?.cellForRowAtIndexPath(self.selectedIndexPath) as! MZDownloadingCell
            
            downloadTask.suspend()
            downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Paused.description()
            downloadInfo[kMZDownloadKeyStartTime] = NSDate()
            
            self.downloadingArray[self.selectedIndexPath.row] = downloadInfo
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
            
            var downloadInfo = self.downloadingArray[self.selectedIndexPath.row]
            let downloadTask = downloadInfo[kMZDownloadKeyTask] as! NSURLSessionDownloadTask
            let cell = self.bgDownloadTableView?.cellForRowAtIndexPath(self.selectedIndexPath) as! MZDownloadingCell
            
            downloadTask.resume()
            downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Downloading.description()
            downloadInfo[kMZDownloadKeyStartTime] = NSDate()
            downloadInfo[kMZDownloadKeyTask] = downloadTask
            
            self.downloadingArray[self.selectedIndexPath.row] = downloadInfo
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
            
            var downloadInfo = self.downloadingArray[self.selectedIndexPath.row]
            let downloadTask = downloadInfo[kMZDownloadKeyTask] as! NSURLSessionDownloadTask
            let cell = self.bgDownloadTableView?.cellForRowAtIndexPath(self.selectedIndexPath) as! MZDownloadingCell
            
            downloadTask.resume()
            downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Downloading.description()
            
            self.downloadingArray[self.selectedIndexPath.row] = downloadInfo
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
        
        let downloadInfo = self.downloadingArray[self.selectedIndexPath.row]
        let downloadTask = downloadInfo[kMZDownloadKeyTask] as! NSURLSessionDownloadTask
        
        downloadTask.cancel()
        
        downloadingArray.removeAtIndex(selectedIndexPath.row)
        bgDownloadTableView?.deleteRowsAtIndexPaths([self.selectedIndexPath], withRowAnimation: UITableViewRowAnimation.Left)
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
        for (indexOfObject, object) in self.downloadingArray.enumerate() {
            var downloadDict = object
            if downloadTask.isEqual(downloadDict[kMZDownloadKeyTask]) {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    
                    let receivedBytesCount = Double(downloadTask.countOfBytesReceived)
                    let totalBytesCount = Double(downloadTask.countOfBytesExpectedToReceive)
                    let progress = Float(receivedBytesCount / totalBytesCount)
                    
                    let taskStartedDate = downloadDict[kMZDownloadKeyStartTime] as! NSDate
                    let timeInterval = taskStartedDate.timeIntervalSinceNow
                    let downloadTime = NSTimeInterval(-1 * timeInterval)
                    
                    let speed = Float(totalBytesWritten) / Float(downloadTime)
                    
                    let indexPath = NSIndexPath(forRow: indexOfObject, inSection: 0)
                    
                    let remainingContentLength = totalBytesExpectedToWrite - totalBytesWritten
                    let remainingTime = remainingContentLength / Int64(speed)
                    let hours = Int(remainingTime) / 3600
                    let minutes = (Int(remainingTime) - hours * 3600) / 60
                    let seconds = Int(remainingTime) - hours * 3600 - minutes * 60
                    let fileSizeUnit = MZUtility.calculateFileSizeInUnit(totalBytesExpectedToWrite)
                    let unit = MZUtility.calculateUnit(totalBytesExpectedToWrite)
                    let fileSizeInUnits = NSString(format: "%.2f \(unit)", fileSizeUnit)
                    let fileSizeDownloaded = MZUtility.calculateFileSizeInUnit(totalBytesWritten)
                    let downloadedSizeUnit = MZUtility.calculateUnit(totalBytesWritten)
                    let downloadedFileSizeUnits = NSString(format: "%.2f \(downloadedSizeUnit)", fileSizeDownloaded)
                    let speedSize = MZUtility.calculateFileSizeInUnit(Int64(speed))
                    let speedUnit = MZUtility.calculateUnit(Int64(speed))
                    let speedInUnits = NSString(format: "%.2f \(speedUnit)", speedSize)
                    let remainingTimeStr = NSMutableString()
                    let detailLabelText = NSMutableString()
                    
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
                        
                        downloadDict[kMZDownloadKeyProgress] = progress
                        downloadDict[kMZDownloadKeyDetails] = detailLabelText
                    }
                })
                break
            }
        }
    }
    
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        for downloadDict in downloadingArray {
            if downloadTask.isEqual(downloadDict[kMZDownloadKeyTask]) {
                let fileName = downloadDict[kMZDownloadKeyFileName] as! NSString
                let destinationPath = fileDest.stringByAppendingPathComponent(fileName as String)
                let fileURL = NSURL(fileURLWithPath: destinationPath as String)
                debugPrint("directory path = \(destinationPath)")
                
                let fileManager : NSFileManager = NSFileManager.defaultManager()
                do {
                    try fileManager.moveItemAtURL(location, toURL: fileURL)
                } catch let error as NSError {
                    debugPrint("Error while moving downloaded file to destination path:\(error)")
                    let errorMessage : NSString = error.localizedDescription as NSString
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        self.delegate?.downloadRequestDidFailedWithError?(error, downloadTask: downloadTask)
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
                
                let fileName = taskInfoDict?.objectForKey(kMZDownloadKeyFileName) as! NSString
                let fileURL = taskInfoDict?.objectForKey(kMZDownloadKeyURL) as! NSString
                var downloadInfo: [String : AnyObject] = Dictionary()
                downloadInfo[kMZDownloadKeyFileName] = fileName
                downloadInfo[kMZDownloadKeyURL] = kMZDownloadKeyURL
                downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Failed.description()
                
                let resumeData = error?.userInfo[NSURLSessionDownloadTaskResumeData] as? NSData
                
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    var newTask = task
                    if self.isValidResumeData(resumeData) == true {
                        newTask = self.sessionManager.downloadTaskWithResumeData(resumeData!)
                    } else {
                        newTask = self.sessionManager.downloadTaskWithURL(NSURL(string: fileURL as String)!)
                    }
                    
                    newTask.taskDescription = task.taskDescription
                    downloadInfo[kMZDownloadKeyTask] = newTask as! NSURLSessionDownloadTask
                    
                    self.downloadingArray.append(downloadInfo)
                    
                    self.safelyDismissAlertController()
                    self.bgDownloadTableView?.reloadData()
                    
                })
                
            } catch let jsonError as NSError {
                debugPrint("Error while retreiving json value: didCompleteWithError \(jsonError.localizedDescription)")
            }
        } else {
            for(indexOfObject, object) in self.downloadingArray.enumerate() {
                var downloadInfo = object
                if task.isEqual(downloadInfo[kMZDownloadKeyTask]) {
                    if error?.code == NSURLErrorCancelled || error == nil {
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            self.safelyDismissAlertController()
                            let fileName = downloadInfo[kMZDownloadKeyFileName] as! NSString
                            
                            self.presentNotificationForDownload(fileName)
                            
                            self.downloadingArray.removeAtIndex(indexOfObject)
                            let indexPath : NSIndexPath = NSIndexPath(forRow: indexOfObject, inSection: 0)
                            self.bgDownloadTableView?.deleteRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimation.Left)
                            
                            if error == nil {
                                self.delegate?.downloadRequestFinished?(fileName)
                            } else {
                                self.delegate?.downloadRequestCanceled?(task as! NSURLSessionDownloadTask)
                            }
                            
                        })
                    } else {
                        let fileURL = downloadInfo[kMZDownloadKeyURL] as! NSString
                        let resumeData = error?.userInfo[NSURLSessionDownloadTaskResumeData] as? NSData
                        
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            
                            var newTask = task
                            if self.isValidResumeData(resumeData) == true {
                                newTask = self.sessionManager.downloadTaskWithResumeData(resumeData!)
                            } else {
                                newTask = self.sessionManager.downloadTaskWithURL(NSURL(string: fileURL as String)!)
                            }
                            
                            newTask.taskDescription = task.taskDescription
                            downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Failed.description()
                            downloadInfo[kMZDownloadKeyTask] = newTask as! NSURLSessionDownloadTask
                            
                            self.downloadingArray[indexOfObject] = downloadInfo

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
        
        debugPrint("All tasks are finished")
    }
}
