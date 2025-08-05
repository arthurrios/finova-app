//
//  SubCategoryTableCell.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/25.
//

import UIKit

// MARK: - SubCategoryTableCellDelegate
protocol SubCategoryTableCellDelegate: AnyObject {
    func didTapEditSubCategory(_ subCategory: SubCategory)
    func didTapDeleteSubCategory(_ subCategory: SubCategory)
}

final class SubCategoryTableCell: UITableViewCell {
    static let reuseID = "SubCategoryTableCell"
    
    private var subCategory: SubCategory?
    private var actionContainerWidthConstraint: NSLayoutConstraint?
    private var panStartX: CGFloat = 0
    weak var delegate: SubCategoryTableCellDelegate?
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let editButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "edit"), for: .normal)
        button.tintColor = Colors.mainMagenta
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let trashButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "trash"), for: .normal)
        button.tintColor = Colors.mainMagenta
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let actionContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let actionIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "trash")
        imageView.tintColor = Colors.gray100
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let actionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.buttonSM.font
        label.textColor = Colors.gray100
        label.text = "delete.action.label".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var panGR: UIPanGestureRecognizer = {
        let gestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gestureRecognizer.delegate = self
        gestureRecognizer.cancelsTouchesInView = false
        gestureRecognizer.delaysTouchesBegan = false
        gestureRecognizer.delaysTouchesEnded = false
        return gestureRecognizer
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
        setupButtonActions()
        clipsToBounds = false
        contentView.clipsToBounds = false
        contentView.addGestureRecognizer(panGR)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        contentView.backgroundColor = Colors.gray100
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(editButton)
        contentView.addSubview(trashButton)
        
        contentView.addSubview(actionContainerView)
        actionContainerView.addSubview(actionIconView)
        actionContainerView.addSubview(actionLabel)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: editButton.leadingAnchor, constant: -Metrics.spacing3),
            
            editButton.trailingAnchor.constraint(equalTo: trashButton.leadingAnchor, constant: -Metrics.spacing3),
            editButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            editButton.widthAnchor.constraint(equalToConstant: 20),
            editButton.heightAnchor.constraint(equalToConstant: 20),
            
            trashButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            trashButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            trashButton.widthAnchor.constraint(equalToConstant: 20),
            trashButton.heightAnchor.constraint(equalToConstant: 20),
            
            actionContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            actionContainerView.leadingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            actionIconView.leadingAnchor.constraint(equalTo: actionContainerView.leadingAnchor, constant: Metrics.spacing6),
            actionIconView.centerYAnchor.constraint(equalTo: actionContainerView.centerYAnchor),
            actionIconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),
            actionIconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            
            actionLabel.leadingAnchor.constraint(equalTo: actionIconView.trailingAnchor, constant: Metrics.spacing3),
            actionLabel.centerYAnchor.constraint(equalTo: actionContainerView.centerYAnchor)
        ])
        
        actionContainerWidthConstraint = actionContainerView.widthAnchor.constraint(equalTo: contentView.widthAnchor)
        actionContainerWidthConstraint?.isActive = true
    }
    
    private func setupButtonActions() {
        editButton.addTarget(self, action: #selector(editButtonTapped), for: .touchUpInside)
        trashButton.addTarget(self, action: #selector(trashButtonTapped), for: .touchUpInside)
    }
    
    @objc private func editButtonTapped() {
        guard let subCategory = subCategory else { return }
        delegate?.didTapEditSubCategory(subCategory)
    }
    
    @objc private func trashButtonTapped() {
        guard let subCategory = subCategory else { return }
        delegate?.didTapDeleteSubCategory(subCategory)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translationX = gesture.translation(in: self).x
        let fullWidth = contentView.bounds.width
        
        switch gesture.state {
        case .began:
            panStartX = contentView.frame.origin.x
            
        case .changed:
            let rawX = panStartX + translationX
            let clampedX = max(-fullWidth, min(0, rawX))
            contentView.frame.origin.x = clampedX
            
        case .ended, .cancelled:
            let shouldOpen = contentView.frame.origin.x < -fullWidth / 3
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    self.contentView.frame.origin.x = shouldOpen ? -fullWidth : 0
                },
                completion: { _ in
                    if shouldOpen && self.contentView.frame.origin.x <= -fullWidth + 0.1 {
                        guard let subCategory = self.subCategory else { return }
                        self.delegate?.didTapDeleteSubCategory(subCategory)
                    }
                })
            
        default:
            break
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.frame.origin.x = 0
    }
    
    func configure(with subCategory: SubCategory, delegate: SubCategoryTableCellDelegate) {
        self.subCategory = subCategory
        self.delegate = delegate
        
        titleLabel.text = subCategory.name
        
        // Configure border styling like transaction table
        configureBorderStyling()
    }
    
    private func configureBorderStyling() {
        // Get the table view to determine position
        guard let tableView = self.superview as? UITableView,
              let indexPath = tableView.indexPath(for: self) else {
            return
        }
        
        let totalRows = tableView.numberOfRows(inSection: indexPath.section)
        let isFirstCell = indexPath.row == 0
        let isLastCell = indexPath.row == totalRows - 1
        
        if isFirstCell && isLastCell {
            // Single cell - rounded on all corners with all borders
            layer.cornerRadius = CornerRadius.small
            layer.borderWidth = 1
            layer.borderColor = Colors.gray200.cgColor
        } else if isFirstCell {
            // First cell - rounded on top corners with all borders
            layer.cornerRadius = CornerRadius.small
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            layer.borderWidth = 1
            layer.borderColor = Colors.gray200.cgColor
            // Add bottom border
            let bottomBorder = UIView()
            bottomBorder.backgroundColor = Colors.gray200
            bottomBorder.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(bottomBorder)
            NSLayoutConstraint.activate([
                bottomBorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                bottomBorder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                bottomBorder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                bottomBorder.heightAnchor.constraint(equalToConstant: 1)
            ])
        } else if isLastCell {
            // Last cell - rounded on bottom corners with all borders
            layer.cornerRadius = CornerRadius.small
            layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            layer.borderWidth = 1
            layer.borderColor = Colors.gray200.cgColor
        } else {
            // Middle cell - no rounded corners, no side borders, just bottom border
            layer.cornerRadius = 0
            layer.borderWidth = 0
            // Add bottom border only
            let bottomBorder = UIView()
            bottomBorder.backgroundColor = Colors.gray200
            bottomBorder.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(bottomBorder)
            NSLayoutConstraint.activate([
                bottomBorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                bottomBorder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                bottomBorder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                bottomBorder.heightAnchor.constraint(equalToConstant: 1)
            ])
            
            // Add left and right borders for middle cells
            let leftBorder = UIView()
            leftBorder.backgroundColor = Colors.gray200
            leftBorder.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(leftBorder)
            
            let rightBorder = UIView()
            rightBorder.backgroundColor = Colors.gray200
            rightBorder.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(rightBorder)
            
            NSLayoutConstraint.activate([
                leftBorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                leftBorder.topAnchor.constraint(equalTo: contentView.topAnchor),
                leftBorder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                leftBorder.widthAnchor.constraint(equalToConstant: 1),
                
                rightBorder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                rightBorder.topAnchor.constraint(equalTo: contentView.topAnchor),
                rightBorder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                rightBorder.widthAnchor.constraint(equalToConstant: 1)
            ])
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension SubCategoryTableCell {
    override public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === panGR,
              let otherPan = otherGestureRecognizer as? UIPanGestureRecognizer
        else {
            return false
        }
        
        let vel = otherPan.velocity(in: contentView)
        return abs(vel.y) > abs(vel.x)
    }
    
    override public func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
        guard let pan = gr as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: contentView)
        return abs(velocity.x) > abs(velocity.y)
    }
    
    override public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === panGR,
              let otherPan = otherGestureRecognizer as? UIPanGestureRecognizer
        else {
            return false
        }
        let vel = otherPan.velocity(in: contentView)
        
        return abs(vel.y) > abs(vel.x)
    }
} 