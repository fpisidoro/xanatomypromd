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
        
        // Test the simple cache
        MetalTestManager.runMetalTests()
        
        // Visual test should work without breakpoints
        MetalTestManager.createVisualTest(in: self)
    }
}

