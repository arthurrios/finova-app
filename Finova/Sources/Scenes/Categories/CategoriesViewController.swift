//
//  CategoriesViewController.swift
//  Finova
//
//  Created by Arthur Rios on 31/07/25.
//

import Foundation
import UIKit

final class CategoriesViewController: UIViewController {
    let contentView: CategoriesView
    let viewModel: CategoriesViewModel
    weak var flowDelegate: CategoriesFlowDelegate?
    
    init(
        contentView: CategoriesView,
        viewModel: CategoriesViewModel,
        flowDelegate: CategoriesFlowDelegate
    ) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Update tab bar selection when categories appears
        flowDelegate?.categoriesDidAppear()
    }
}
