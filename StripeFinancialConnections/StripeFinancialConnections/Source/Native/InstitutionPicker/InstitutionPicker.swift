//
//  InstitutionPicker.swift
//  StripeFinancialConnections
//
//  Created by Vardges Avetisyan on 6/7/22.
//

import Foundation
import UIKit
@_spi(STP) import StripeCore
@_spi(STP) import StripeUICore

@available(iOSApplicationExtension, unavailable)
protocol InstitutionPickerDelegate: AnyObject {
    func institutionPicker(_ picker: InstitutionPicker, didSelect institution: FinancialConnectionsInstitution)
    func institutionPickerDidSelectManuallyAddYourAccount(_ picker: InstitutionPicker)
}

@available(iOSApplicationExtension, unavailable)
class InstitutionPicker: UIViewController {
    
    // MARK: - Properties
    
    private let dataSource: InstitutionDataSource
    weak var delegate: InstitutionPickerDelegate?
    
    private lazy var loadingView: ActivityIndicator = {
        let activityIndicator = ActivityIndicator(size: .large)
        activityIndicator.color = .textDisabled
        activityIndicator.backgroundColor = .customBackgroundColor
        return activityIndicator
    }()
    private lazy var searchBar: InstitutionSearchBar = {
        let searchBar = InstitutionSearchBar()
        searchBar.delegate = self
        return searchBar
    }()
    private lazy var contentContainerView: UIView = {
        let contentContainerView = UIView()
        contentContainerView.backgroundColor = .clear
        return contentContainerView
    }()
    private var _featuredInstitutionGridView: Any? = nil
    @available(iOS 13.0, *)
    private var featuredInstitutionGridView: FeaturedInstitutionGridView {
        if _featuredInstitutionGridView == nil {
            let featuredInstitutionGridView = FeaturedInstitutionGridView()
            featuredInstitutionGridView.delegate = self
            _featuredInstitutionGridView = featuredInstitutionGridView
        }
        return _featuredInstitutionGridView as! FeaturedInstitutionGridView
    }
    private var _institutionSearchTableView: Any? = nil
    @available(iOS 13.0, *)
    private var institutionSearchTableView: InstitutionSearchTableView {
        if _institutionSearchTableView == nil {
            let institutionSearchTableView = InstitutionSearchTableView(allowManualEntry: dataSource.manifest.allowManualEntry)
            institutionSearchTableView.delegate = self
            _institutionSearchTableView = institutionSearchTableView
        }
        return _institutionSearchTableView as! InstitutionSearchTableView
    }
    // Only used for iOS12 fallback where we don't ahve the diffable datasource
    private lazy var institutions: [FinancialConnectionsInstitution]? = nil
    
    // MARK: - Debouncing Support
    
    private var fetchInstitutionsDispatchWorkItem: DispatchWorkItem?
    private var lastInstitutionSearchFetchDate = Date()
    
    // MARK: - Init
    
    init(dataSource: InstitutionDataSource) {
        self.dataSource = dataSource
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UIViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        
        showLoadingView(true)
        fetchFeaturedInstitutions { [weak self] in
            self?.showLoadingView(false)
        }
    }
    
    private func setupView() {
        view.backgroundColor = UIColor.customBackgroundColor
        
        view.addAndPinSubview(loadingView)
        view.addAndPinSubviewToSafeArea(
            CreateMainView(
                searchBar: (dataSource.manifest.institutionSearchDisabled == true) ? nil : searchBar,
                contentContainerView: contentContainerView
            )
        )
        if #available(iOS 13.0, *) {
            contentContainerView.addAndPinSubview(featuredInstitutionGridView)
            contentContainerView.addAndPinSubview(institutionSearchTableView)
        }
        
        toggleContentContainerViewVisbility()
        
        let dismissSearchBarTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapOutsideOfSearchBar))
        dismissSearchBarTapGestureRecognizer.delegate = self
        view.addGestureRecognizer(dismissSearchBarTapGestureRecognizer)
    }
    
    private func toggleContentContainerViewVisbility() {
        if #available(iOS 13.0, *) {
            let isUserCurrentlySearching = !searchBar.text.isEmpty
            featuredInstitutionGridView.isHidden = isUserCurrentlySearching
            institutionSearchTableView.isHidden = !featuredInstitutionGridView.isHidden
        }
    }
    
    @IBAction private func didTapOutsideOfSearchBar() {
        searchBar.resignFirstResponder()
    }
    
    private func didSelectInstitution(_ institution: FinancialConnectionsInstitution) {
        searchBar.resignFirstResponder()
        if #available(iOS 13.0, *) {
            // clear search results
            searchBar.text = ""
            institutionSearchTableView.loadInstitutions([])
            toggleContentContainerViewVisbility()
        }
        delegate?.institutionPicker(self, didSelect: institution)
    }
    
    private func showLoadingView(_ show: Bool) {
        loadingView.isHidden = !show
        if show {
            loadingView.startAnimating()
        } else {
            loadingView.stopAnimating()
        }
        view.bringSubviewToFront(loadingView) // defensive programming to avoid loadingView being hiddden
    }
}

// MARK: - Data

@available(iOSApplicationExtension, unavailable)
extension InstitutionPicker {
    
    private func fetchFeaturedInstitutions(completionHandler: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
        dataSource
            .fetchFeaturedInstitutions()
            .observe(on: .main) { [weak self] result in
                guard let self = self else { return }
                switch(result) {
                case .success(let institutions):
                    if #available(iOS 13.0, *) {
                        self.featuredInstitutionGridView.loadInstitutions(institutions)
                    }
                case .failure(_):
                    // TODO: add handling for failure (Stripe.js currently shows a terminal error)
                    break
                }
                completionHandler()
            }
    }
    
    private func fetchInstitutions(searchQuery: String) {
        fetchInstitutionsDispatchWorkItem?.cancel()
        if #available(iOS 13.0, *) {
            institutionSearchTableView.showError(false)
        }
        
        guard !searchQuery.isEmpty else {
            // clear data because search query is empty
            if #available(iOS 13.0, *) {
                institutionSearchTableView.loadInstitutions([])
            }
            return
        }
        
        if #available(iOS 13.0, *) {
            institutionSearchTableView.showLoadingView(true)
        }
        let newFetchInstitutionsDispatchWorkItem = DispatchWorkItem(block: { [weak self] in
            guard let self = self else { return }
            
            if #available(iOS 13.0, *) {
                let lastInstitutionSearchFetchDate = Date()
                self.lastInstitutionSearchFetchDate = lastInstitutionSearchFetchDate
                self.dataSource
                    .fetchInstitutions(searchQuery: searchQuery)
                    .observe(on: DispatchQueue.main) { [weak self] result in
                        guard let self = self else { return }
                        guard lastInstitutionSearchFetchDate == self.lastInstitutionSearchFetchDate else {
                            // ignore any search result that came before
                            // the lastest search attempt
                            return
                        }
                        switch(result) {
                        case .success(let institutions):
                            self.institutionSearchTableView.loadInstitutions(institutions)
                            if institutions.isEmpty {
                                self.institutionSearchTableView.showNoResultsNotice(query: searchQuery)
                            }
                        case .failure(_):
                            self.institutionSearchTableView.loadInstitutions([])
                            self.institutionSearchTableView.showError(true)
                        }
                        self.institutionSearchTableView.showLoadingView(false)
                    }
            }
        })
        self.fetchInstitutionsDispatchWorkItem = newFetchInstitutionsDispatchWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.queryDelay, execute: newFetchInstitutionsDispatchWorkItem)
    }
}

// MARK: - InstitutioNSearchBarDelegate

@available(iOSApplicationExtension, unavailable)
extension InstitutionPicker: InstitutionSearchBarDelegate {
    
    func institutionSearchBar(_ searchBar: InstitutionSearchBar, didChangeText text: String) {
        toggleContentContainerViewVisbility()
        fetchInstitutions(searchQuery: text)
    }
}

// MARK: - UIGestureRecognizerDelegate

@available(iOSApplicationExtension, unavailable)
extension InstitutionPicker: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let touchPoint = touch.location(in: view)
        return !searchBar.frame.contains(touchPoint) && !contentContainerView.frame.contains(touchPoint)
    }
}

// MARK: - FeaturedInstitutionGridViewDelegate

@available(iOS 13.0, *)
@available(iOSApplicationExtension, unavailable)
extension InstitutionPicker: FeaturedInstitutionGridViewDelegate {
    
    func featuredInstitutionGridView(
        _ view: FeaturedInstitutionGridView,
        didSelectInstitution institution: FinancialConnectionsInstitution
    ) {
        didSelectInstitution(institution)
    }
}

// MARK: - InstitutionSearchTableViewDelegate

@available(iOS 13.0, *)
@available(iOSApplicationExtension, unavailable)
extension InstitutionPicker: InstitutionSearchTableViewDelegate {
    
    func institutionSearchTableView(
        _ tableView: InstitutionSearchTableView,
        didSelectInstitution institution: FinancialConnectionsInstitution
    ) {
        didSelectInstitution(institution)
    }
    
    func institutionSearchTableViewDidSelectManuallyAddYourAccount(_ tableView: InstitutionSearchTableView) {
        delegate?.institutionPickerDidSelectManuallyAddYourAccount(self)
    }
}

// MARK: - Constants

@available(iOSApplicationExtension, unavailable)
extension InstitutionPicker {
    enum Constants {
        static let queryDelay = TimeInterval(0.2)
    }
}

// MARK: - Helpers

private func CreateMainView(
    searchBar: UIView?,
    contentContainerView: UIView
) -> UIView {
    let verticalStackView = UIStackView(
        arrangedSubviews: [
            CreateHeaderView(
                searchBar: searchBar
            ),
            contentContainerView,
        ]
    )
    verticalStackView.axis = .vertical
    verticalStackView.spacing = 16
    return verticalStackView
}

private func CreateHeaderView(
    searchBar: UIView?
) -> UIView {
    let verticalStackView = UIStackView(
        arrangedSubviews: [
            CreateHeaderTitleLabel(),
        ]
    )
    if let searchBar = searchBar {
        verticalStackView.addArrangedSubview(searchBar)
    }
    verticalStackView.axis = .vertical
    verticalStackView.spacing = 24
    verticalStackView.isLayoutMarginsRelativeArrangement = true
    verticalStackView.directionalLayoutMargins = NSDirectionalEdgeInsets(
        top: 16,
        leading: 24,
        bottom: 0,
        trailing: 24
    )
    verticalStackView.distribution = .fillProportionally
    return verticalStackView
}

private func CreateHeaderTitleLabel() -> UIView {
    let headerTitleLabel = UILabel()
    headerTitleLabel.textColor = .textPrimary
    headerTitleLabel.font = .stripeFont(forTextStyle: .subtitle)
    headerTitleLabel.text = STPLocalizedString("Select your bank", "The title of the 'Institution Picker' screen where users get to select an institution (ex. a bank like Bank of America).")
    return headerTitleLabel
}
