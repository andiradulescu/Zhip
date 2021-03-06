//
//  BackupWalletCoordinator.swift
//  Zupreme
//
//  Created by Alexander Cyon on 2018-12-08.
//  Copyright © 2018 Open Zesame. All rights reserved.
//

import Foundation

import UIKit
import Zesame

import RxSwift
import RxCocoa

final class BackupWalletCoordinator: BaseCoordinator<BackupWalletCoordinator.NavigationStep> {
    enum NavigationStep {
        case backUp
        case cancel
    }

    private let useCase: WalletUseCase
    private let wallet: Driver<Wallet>

    init(navigationController: UINavigationController, useCase: WalletUseCase, wallet: Driver<Wallet>? = nil) {
        self.useCase = useCase
        if let wallet = wallet {
            self.wallet = wallet
        } else {
            self.wallet = useCase.wallet.map {
                guard let wallet = $0 else {
                    incorrectImplementation("Should have saved wallet earlier")
                }
                return wallet
            }.asDriverOnErrorReturnEmpty()
        }
        super.init(navigationController: navigationController)
    }

    override func start(didStart: Completion? = nil) {
        toBackUpWallet()
    }
}

// MARK: Private
private extension BackupWalletCoordinator {

    func toBackUpWallet() {

        let viewModel = BackupWalletViewModel(wallet: wallet)

        push(scene: BackupWallet.self, viewModel: viewModel) { [unowned self] userDid in
            switch userDid {
            case .revealKeystore: self.toRevealKeystore()
            case .revealPrivateKey: self.toDecryptKeystoreToRevealKeyPair()
            case .cancel: self.cancel()
            case .backupWallet: self.finish()
            }
        }
    }

    func toDecryptKeystoreToRevealKeyPair() {
        presentModalCoordinator(makeCoordinator: {
            DecryptKeystoreCoordinator(navigationController: $0, useCase: useCase, wallet: wallet)
        }, navigationHandler: { userFinished, dismissModalFlow in
                switch userFinished {
                case .backingUpKeyPair: dismissModalFlow(true)
                case .dismiss: dismissModalFlow(true)
                }
        })
    }

    func toRevealKeystore() {
        let viewModel = BackUpKeystoreViewModel(wallet: wallet)

        modallyPresent(scene: BackUpKeystore.self, viewModel: viewModel) { userDid, dismissScene in
            switch userDid {
            case .finished: dismissScene(true, nil)
            }
        }
    }

    func cancel() {
        navigator.next(.cancel)
    }

    func finish() {
        let userFinished: NavigationStep = .backUp
        navigator.next(userFinished)
    }

}
