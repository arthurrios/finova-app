//
//  GroupInvitationFlowDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

protocol GroupInvitationFlowDelegate: AnyObject {
    func didAcceptInvitation()
    func didDeclineInvitation()
    func didDismissInvitation()
}

protocol GroupInvitationViewDelegate: AnyObject {
    func didTapAccept()
    func didTapDecline()
    func didTapClose()
}
