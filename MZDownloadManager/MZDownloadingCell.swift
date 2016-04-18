//
//  MZDownloadingCell.swift
//  MZDownloadManager
//
//  Created by Muhammad Zeeshan on 22/10/2014.
//  Copyright (c) 2014 ideamakerz. All rights reserved.
//

import UIKit

class MZDownloadingCell: UITableViewCell {

    @IBOutlet var lblTitle : UILabel?
    @IBOutlet var lblDetails : UILabel?
    @IBOutlet var progressDownload : UIProgressView?

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    func updateCellForRowAtIndexPath(indexPath : NSIndexPath, downloadInfoDict: NSMutableDictionary) {
        let fileName         : NSString = downloadInfoDict.objectForKey(kMZDownloadKeyFileName) as! NSString
        
        self.lblTitle?.text = "File Title: \(fileName)"
        
        if let _ = downloadInfoDict.objectForKey(kMZDownloadKeyDetails) as? NSString {
            let progress         : NSString = downloadInfoDict.objectForKey(kMZDownloadKeyProgress) as! NSString
            self.lblDetails?.text = downloadInfoDict.objectForKey(kMZDownloadKeyDetails) as! NSString as String
            self.progressDownload?.progress = progress.floatValue
        }
    }
}
