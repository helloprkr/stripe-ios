//
//  AuthFlowDataManager.swift
//  StripeFinancialConnections
//
//  Created by Vardges Avetisyan on 6/7/22.
//

import Foundation
@_spi(STP) import StripeCore

protocol AuthFlowDataManager: AnyObject {
    var manifest: FinancialConnectionsSessionManifest { get }
    var authorizationSession: FinancialConnectionsAuthorizationSession? { get }
    var delegate: AuthFlowDataManagerDelegate? { get set }
    
    // MARK: - Read Calls
    
    func nextPane() -> FinancialConnectionsSessionManifest.NextPane

    // MARK: - Mutating Calls
    
    func consentAcquired()
    func picked(institution: FinancialConnectionsInstitution)
}

protocol AuthFlowDataManagerDelegate: AnyObject {
    func authFlowDataManagerDidUpdateNextPane(_ dataManager: AuthFlowDataManager)
    func authFlowDataManagerDidUpdateManifest(_ dataManager: AuthFlowDataManager)
    func authFlow(dataManager: AuthFlowDataManager,
                  failedToUpdateManifest error: Error)
}

class AuthFlowAPIDataManager: AuthFlowDataManager {
    
    // MARK: - Types
    
    struct VersionedNextPane {
        let pane: FinancialConnectionsSessionManifest.NextPane
        let version: Int
    }

    // MARK: - Properties
    
    weak var delegate: AuthFlowDataManagerDelegate?
    private(set) var manifest: FinancialConnectionsSessionManifest {
        didSet {
            delegate?.authFlowDataManagerDidUpdateManifest(self)
        }
    }
    private let api: FinancialConnectionsAPIClient
    private let clientSecret: String
    
    private(set) var authorizationSession: FinancialConnectionsAuthorizationSession?
    private var currentNextPane: VersionedNextPane {
        didSet {
            delegate?.authFlowDataManagerDidUpdateNextPane(self)
        }
    }

    // MARK: - Init
    
    init(with initial: FinancialConnectionsSessionManifest,
         api: FinancialConnectionsAPIClient,
         clientSecret: String) {
        self.manifest = initial
        self.currentNextPane = VersionedNextPane(pane: initial.nextPane, version: 0)
        self.api = api
        self.clientSecret = clientSecret
    }

    // MARK: - FlowDataManager

    func consentAcquired() {
        let version = currentNextPane.version + 1
        api.markConsentAcquired(clientSecret: clientSecret)
            .observe(on: .main) { [weak self] result in
                guard let self = self else { return }
                switch(result) {
                case .failure(let error):
                    self.delegate?.authFlow(dataManager: self, failedToUpdateManifest: error)
                case .success(let manifest):
                    self.update(nextPane: manifest.nextPane, for: version)
                    self.manifest = manifest
                }
        }
    }
    
    func picked(institution: FinancialConnectionsInstitution) {
        let version = currentNextPane.version + 1
        api.createAuthorizationSession(clientSecret: clientSecret, institutionId: institution.id)
            .observe(on: .main) { [weak self] result in
                guard let self = self else { return }
                switch(result) {
                case .failure(let error):
                    print(error)
                    // TODO(vardges): need to think about this
                    // the duality of state of manifest vs auth_session
                    // needs to be consolidated elegantly
                case .success(let authorizationSession):
                    self.authorizationSession = authorizationSession
                    self.update(nextPane: authorizationSession.nextPane, for: version)
                }
            }
    }
    
    func nextPane() -> FinancialConnectionsSessionManifest.NextPane {
        return currentNextPane.pane
    }
}

// MARK: - Helpers

private extension AuthFlowAPIDataManager {
    func update(nextPane: FinancialConnectionsSessionManifest.NextPane, for version: Int) {
        if version > self.currentNextPane.version {
            self.currentNextPane = VersionedNextPane(pane: nextPane, version: version)
        }
    }
}
