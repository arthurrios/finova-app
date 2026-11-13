//
//  AllocationTagsFlowDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import Foundation

protocol AllocationTagsFlowDelegate: AnyObject {
    func dismissAllocationTags()
    /// Pushed straight after creating a tag too: a tag with no categories does nothing, so the edit
    /// screen is where the work actually happens.
    func navigateToAllocationTagEdit(tag: AllocationTag)
}

protocol AllocationTagEditFlowDelegate: AnyObject {
    func dismissAllocationTagEdit()
    func navigateToAllocationTagCategories(tag: AllocationTag)
}

protocol AllocationTagCategoriesFlowDelegate: AnyObject {
    func dismissAllocationTagCategories()
}
