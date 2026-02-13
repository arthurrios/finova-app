//
//  GroupInvitationViewController.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class GroupInvitationViewController: UIViewController {
    let contentView: GroupInvitationView
    private let viewModel: GroupInvitationViewModel
    weak var flowDelegate: GroupInvitationFlowDelegate?

    init(contentView: GroupInvitationView, viewModel: GroupInvitationViewModel, flowDelegate: GroupInvitationFlowDelegate) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
        contentView.delegate = self
        contentView.configure(
            with: viewModel.invitation,
            permissions: viewModel.permissions
        )
    }
}

// MARK: - GroupInvitationViewDelegate
extension GroupInvitationViewController: GroupInvitationViewDelegate {
    func didTapAccept() {
        contentView.acceptButton.startLoading()

        viewModel.acceptInvitation { [weak self] result in
            self?.contentView.acceptButton.stopLoading()
            switch result {
            case .success:
                self?.flowDelegate?.didAcceptInvitation()
            case .failure(let error):
                let alert = UIAlertController(
                    title: "alert.error".localized,
                    message: error.localizedDescription,
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
                self?.present(alert, animated: true)
            }
        }
    }

    func didTapDecline() {
        viewModel.declineInvitation()
        flowDelegate?.didDeclineInvitation()
    }
}
