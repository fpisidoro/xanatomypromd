//
//  ViewController.swift
//  xanatomypromd
//
//  Created by fpisidoro on 7/16/25.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        DICOMTestManager.runQuickTests()  // Test the fix!
    }
}

