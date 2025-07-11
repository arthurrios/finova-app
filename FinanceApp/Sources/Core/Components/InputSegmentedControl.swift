//
//  InputSegmentedControl.swift
//  FinanceApp
//
//  Created by Arthur Rios on 13/06/25.
//

import Foundation
import UIKit

class InputSegmentedControl: UIView {
  private let segmentedControl: UISegmentedControl = {
    let items = TransactionMode.allCases.map { $0.title }
    let control = UISegmentedControl(items: items)
    control.selectedSegmentIndex = 0
    control.translatesAutoresizingMaskIntoConstraints = false
    return control
  }()

  var onSelectionChanged: ((TransactionMode) -> Void)?

  init() {
    super.init(frame: .zero)
    setupView()
    styleSegmentedControl()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    addSubview(segmentedControl)

    segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)

    setupConstraints()
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      segmentedControl.topAnchor.constraint(equalTo: topAnchor),
      segmentedControl.leadingAnchor.constraint(equalTo: leadingAnchor),
      segmentedControl.trailingAnchor.constraint(equalTo: trailingAnchor),
      segmentedControl.bottomAnchor.constraint(equalTo: bottomAnchor),
      segmentedControl.heightAnchor.constraint(equalToConstant: Metrics.inputHeight)
    ])
  }

  private func styleSegmentedControl() {
    segmentedControl.backgroundColor = Colors.gray200
    segmentedControl.selectedSegmentTintColor = Colors.mainMagenta
    segmentedControl.layer.borderWidth = 1
    segmentedControl.layer.borderColor = Colors.gray300.cgColor
    segmentedControl.layer.cornerRadius = CornerRadius.large

    segmentedControl.setTitleTextAttributes(
      [
        .foregroundColor: Colors.gray700,
        .font: Fonts.input.font
      ], for: .normal)

    segmentedControl.setTitleTextAttributes(
      [
        .foregroundColor: Colors.gray100,
        .font: Fonts.input.font
      ], for: .selected)
  }

  @objc
  private func segmentChanged() {
    let selectedMode = TransactionMode(rawValue: segmentedControl.selectedSegmentIndex) ?? .normal
    onSelectionChanged?(selectedMode)
  }

  func getSelectedMode() -> TransactionMode {
    return TransactionMode(rawValue: segmentedControl.selectedSegmentIndex) ?? .normal
  }

  func setSelectedMode(_ mode: TransactionMode) {
    segmentedControl.selectedSegmentIndex = mode.rawValue
  }
}
