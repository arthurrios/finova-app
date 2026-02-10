//
//  ProfileViewModelDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 10/02/26.
//

import UIKit

protocol ProfileViewModelDelegate: AnyObject {
    func didUpdateUserInfo()
    func didUpdateProfileImage(_ image: UIImage?)
}
