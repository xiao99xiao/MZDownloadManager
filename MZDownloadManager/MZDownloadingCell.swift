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
    
    func updateCellForRowAtIndexPath(indexPath : NSIndexPath, downloadInfoDict: [String : AnyObject]) {
        let fileName = downloadInfoDict[kMZDownloadKeyFileName] as! String
        
        self.lblTitle?.text = "File Title: \(fileName)"
        
        if let details = downloadInfoDict[kMZDownloadKeyDetails] as? String {
            self.lblDetails?.text = details
            self.progressDownload?.progress = Float(downloadInfoDict[kMZDownloadKeyProgress] as! String) ?? 0.0
        }
    }
}
