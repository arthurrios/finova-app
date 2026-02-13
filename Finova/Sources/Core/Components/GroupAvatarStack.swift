//
//  GroupAvatarStack.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class GroupAvatarStack: UIView {
    private let maxVisible = 3
    private let avatarSize: CGFloat = 28
    private let overlap: CGFloat = 8

    private var avatarViews: [UIView] = []
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with names: [String], totalCount: Int? = nil) {
        avatarViews.forEach { $0.removeFromSuperview() }
        avatarViews.removeAll()

        let visibleNames = Array(names.prefix(maxVisible))
        let total = totalCount ?? names.count
        let remaining = total - visibleNames.count

        for (index, name) in visibleNames.enumerated() {
            let avatarView = createAvatarView(initial: String(name.prefix(1)).uppercased())
            let xOffset = CGFloat(index) * (avatarSize - overlap)
            avatarView.frame = CGRect(x: xOffset, y: 0, width: avatarSize, height: avatarSize)
            avatarView.layer.cornerRadius = avatarSize / 2
            avatarView.layer.borderWidth = 2
            avatarView.layer.borderColor = Colors.gray100.cgColor
            addSubview(avatarView)
            avatarViews.append(avatarView)
        }

        var itemCount = visibleNames.count

        if remaining > 0 {
            let overflowView = createOverflowView(count: remaining)
            let xOffset = CGFloat(visibleNames.count) * (avatarSize - overlap)
            overflowView.frame = CGRect(x: xOffset, y: 0, width: avatarSize, height: avatarSize)
            overflowView.layer.cornerRadius = avatarSize / 2
            overflowView.layer.borderWidth = 2
            overflowView.layer.borderColor = Colors.gray100.cgColor
            addSubview(overflowView)
            avatarViews.append(overflowView)
            itemCount += 1
        }

        let totalWidth = itemCount == 0 ? 0 :
            CGFloat(itemCount) * avatarSize - CGFloat(max(0, itemCount - 1)) * overlap

        widthConstraint?.isActive = false
        heightConstraint?.isActive = false
        widthConstraint = widthAnchor.constraint(equalToConstant: totalWidth)
        heightConstraint = heightAnchor.constraint(equalToConstant: avatarSize)
        widthConstraint?.isActive = true
        heightConstraint?.isActive = true
    }

    private func createOverflowView(count: Int) -> UIView {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.clipsToBounds = true

        let label = UILabel()
        label.text = "+\(count)"
        label.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        label.textColor = Colors.gray600
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }

    private func createAvatarView(initial: String) -> UIView {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta.withAlphaComponent(0.2)
        view.clipsToBounds = true

        let label = UILabel()
        label.text = initial
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Colors.mainMagenta
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }
}
