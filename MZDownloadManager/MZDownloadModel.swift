//
//  MZDownloadModel.swift
//  MZDownloadManager
//
//  Created by Hamid Ismail on 19/04/2016.
//  Copyright © 2016 ideamakerz. All rights reserved.
//

import UIKit

class MZDownloadModel: NSObject {
    
    var fileName: String!
    var fileURL: String!
    
    var remainingTime: (hours: Int, minutes: Int, seconds: Int)?
    
    var progress: Float = 0
    
    convenience init(fileName: String, fileURL: String) {
        self.init()
        
        self.fileName = fileName
        self.fileURL = fileURL
    }
}

/*
let kMZDownloadKeyURL        : String = "URL"
let kMZDownloadKeyStartTime  : String = "startTime"
let kMZDownloadKeyFileName   : String = "fileName"
let kMZDownloadKeyProgress   : String = "progress"
let kMZDownloadKeyTask       : String = "downloadTask"
let kMZDownloadKeyStatus     : String = "requestStatus"
let kMZDownloadKeyDetails    : String = "downloadDetails"
let kMZDownloadKeyResumeData : String = "resumedata"
*/