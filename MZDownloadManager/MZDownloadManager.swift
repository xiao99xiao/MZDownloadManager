//
//  MZDownloadManager.swift
//  MZDownloadManager
//
//  Created by Hamid Ismail on 19/04/2016.
//  Copyright © 2016 ideamakerz. All rights reserved.
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

@objc protocol MZDownloadManagerDelegate {
    /**A delegate method called each time whenever any download task's progress is updated
     */
    func downloadRequestDidUpdateProgress(downloadInfo: [String : AnyObject], index: Int)
    /**A delegate method called when interrupted tasks are repopulated
     */
    func downloadRequestDidPopulatedInterruptedTasks(downloadInfo: [[String : AnyObject]])
    /**A delegate method called each time whenever new download task is start downloading
     */
    optional func downloadRequestStarted(downloadInfo: [String : AnyObject], index: Int)
    /**A delegate method called each time whenever running download task is paused. If task is already paused the action will be ignored
     */
    optional func downloadRequestDidPaused(downloadInfo: [String : AnyObject], index: Int)
    /**A delegate method called each time whenever any download task is resumed. If task is already downloading the action will be ignored
     */
    optional func downloadRequestDidResumed(downloadInfo: [String : AnyObject], index: Int)
    /**A delegate method called each time whenever any download task is resumed. If task is already downloading the action will be ignored
     */
    optional func downloadRequestDidRetry(downloadInfo: [String : AnyObject], index: Int)
    /**A delegate method called each time whenever any download task is cancelled by the user
     */
    optional func downloadRequestCanceled(downloadInfo: [String : AnyObject], index: Int)
    /**A delegate method called each time whenever any download task is finished successfully
     */
    optional func downloadRequestFinished(downloadInfo: [String : AnyObject], index: Int)
    /**A delegate method called each time whenever any download task is failed due to any reason
     */
    optional func downloadRequestDidFailedWithError(error: NSError, downloadInfo: [String : AnyObject], index: Int)
    
}

class MZDownloadManager: NSObject {
    
    var sessionManager: NSURLSession!
    var downloadingArray  : [[String : AnyObject]] = []
    var delegate: MZDownloadManagerDelegate?
    
    convenience init(session sessionIdentifer: String, delegate: MZDownloadManagerDelegate) {
        self.init()
        
        self.delegate = delegate
        self.sessionManager = self.backgroundSession(sessionIdentifer)
        self.populateOtherDownloadTasks()
    }
    
    private func backgroundSession(sessionIdentifer: String) -> NSURLSession {
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
}

// MARK: Helper functions

extension MZDownloadManager {
    
    func downloadTasks() -> NSArray {
        return self.tasksForKeyPath("downloadTasks")
    }
    
    func tasksForKeyPath(keyPath: NSString) -> NSArray {
        var tasks: NSArray = NSArray()
        let semaphore : dispatch_semaphore_t = dispatch_semaphore_create(0)
        sessionManager.getTasksWithCompletionHandler { (dataTasks, uploadTasks, downloadTasks) -> Void in
            if keyPath == "downloadTasks" {
                if let pendingTasks: NSArray = downloadTasks {
                    tasks = pendingTasks
                    debugPrint("pending tasks \(tasks)")
                }
            }
            
            dispatch_semaphore_signal(semaphore)
        }
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
        return tasks
    }
    
    func addDownloadTask(fileName: NSString, fileURL: NSString) {
        
        let url = NSURL(string: fileURL as String)!
        let request = NSURLRequest(URL: url)
        let downloadTask = sessionManager.downloadTaskWithRequest(request)
        
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
        
        downloadingArray.append(downloadInfo)
        delegate?.downloadRequestStarted?(downloadInfo, index: downloadingArray.count - 1)
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
    
    func presentNotificationForDownload(notifAction: String, notifBody: String) {
        let application = UIApplication.sharedApplication()
        let applicationState = application.applicationState
        
        if applicationState == UIApplicationState.Background {
            let localNotification = UILocalNotification()
            localNotification.alertBody = notifBody
            localNotification.alertAction = notifAction
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

extension MZDownloadManager: NSURLSessionDelegate {
    
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
                    
                    downloadDict[kMZDownloadKeyProgress] = progress
                    downloadDict[kMZDownloadKeyDetails] = detailLabelText
                    
                    self.delegate?.downloadRequestDidUpdateProgress(downloadDict, index: indexOfObject)
                })
                break
            }
        }
    }
    
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        for (index, downloadDict) in downloadingArray.enumerate() {
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
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        self.delegate?.downloadRequestDidFailedWithError?(error, downloadInfo: downloadDict, index: index)
                    })
                }
                
                break
            }
        }
    }
    
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
        debugPrint("task id: \(task.taskIdentifier)")
        /***** Any interrupted tasks due to any reason will be populated in failed state after init *****/
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
                    
                    self.delegate?.downloadRequestDidPopulatedInterruptedTasks(self.downloadingArray)
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

                            self.downloadingArray.removeAtIndex(indexOfObject)
                            
                            if error == nil {
                                self.delegate?.downloadRequestFinished?(downloadInfo, index: indexOfObject)
                            } else {
                                self.delegate?.downloadRequestCanceled?(downloadInfo, index: indexOfObject)
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

                            if let error = error {
                                self.delegate?.downloadRequestDidFailedWithError?(error, downloadInfo: downloadInfo, index: indexOfObject)
                            } else {
                                let error: NSError = NSError(domain: "MZDownloadManagerDomain", code: 1000, userInfo: [NSLocalizedDescriptionKey : "Unknown error occurred"])
                                self.delegate?.downloadRequestDidFailedWithError?(error, downloadInfo: downloadInfo, index: indexOfObject)
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

extension MZDownloadManager {
    func pauseDownloadTaskAtIndex(index: Int) {
        
        var downloadInfo = downloadingArray[index]
        
        guard downloadInfo[kMZDownloadKeyStatus] as! String != RequestStatus.Paused.description() else {
            return
        }
        
        let downloadTask = downloadInfo[kMZDownloadKeyTask] as! NSURLSessionDownloadTask
        downloadTask.suspend()
        downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Paused.description()
        downloadInfo[kMZDownloadKeyStartTime] = NSDate()
        
        downloadingArray[index] = downloadInfo
        
        delegate?.downloadRequestDidPaused?(downloadInfo, index: index)
    }
    
    func resumeDownloadTaskAtIndex(index: Int) {
        
        var downloadInfo = downloadingArray[index]
        
        guard downloadInfo[kMZDownloadKeyStatus] as! String != RequestStatus.Downloading.description() else {
            return
        }
        
        let downloadTask = downloadInfo[kMZDownloadKeyTask] as! NSURLSessionDownloadTask
        downloadTask.resume()
        downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Downloading.description()
        
        downloadingArray[index] = downloadInfo
        
        delegate?.downloadRequestDidResumed?(downloadInfo, index: index)
    }
    
    func retryDownloadTaskAtIndex(index: Int) {
        var downloadInfo = downloadingArray[index]
        
        guard downloadInfo[kMZDownloadKeyStatus] as! String != RequestStatus.Downloading.description() else {
            return
        }

        let downloadTask = downloadInfo[kMZDownloadKeyTask] as! NSURLSessionDownloadTask
        
        downloadTask.resume()
        downloadInfo[kMZDownloadKeyStatus] = RequestStatus.Downloading.description()
        downloadInfo[kMZDownloadKeyStartTime] = NSDate()
        downloadInfo[kMZDownloadKeyTask] = downloadTask
        
        downloadingArray[index] = downloadInfo
        
    }
    
    func cancelTaskAtIndex(index: Int) {

        let downloadInfo = downloadingArray[index]
        let downloadTask = downloadInfo[kMZDownloadKeyTask] as! NSURLSessionDownloadTask
        
        downloadTask.cancel()
    }
    
}
