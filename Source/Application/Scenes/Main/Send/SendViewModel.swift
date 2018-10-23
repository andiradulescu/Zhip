//
//  SendViewModel.swift
//  Zupreme
//
//  Created by Alexander Cyon on 2018-09-08.
//  Copyright © 2018 Open Zesame. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa
import Zesame

final class SendViewModel {

    private weak var navigator: SendNavigator?
    private let useCase: TransactionsUseCase
    private let wallet: Driver<Wallet>

    init(navigator: SendNavigator, wallet: Driver<Wallet>, useCase: TransactionsUseCase) {
        self.navigator = navigator
        self.useCase = useCase
        self.wallet = wallet
    }
}

extension SendViewModel: ViewModelType {

    struct Input: InputType {
        struct FromView {
            let sendTrigger: Driver<Void>
            let recepientAddress: Driver<String>
            let amountToSend: Driver<String>
            let gasLimit: Driver<String>
            let gasPrice: Driver<String>
            let encryptionPassphrase: Driver<String>
        }
        let fromView: FromView
        let fromController: ControllerInput
        
        init(fromView: FromView, fromController: ControllerInput) {
            self.fromView = fromView
            self.fromController = fromController
        }
    }

    struct Output {
        let walletBalance: Driver<WalletBalance>
        let isRecipientAddressValid: Driver<Bool>
        let transactionId: Driver<String>
    }

    func transform(input: Input) -> Output {

        let fromView = input.fromView

        let fetchBalanceSubject = BehaviorSubject<Void>(value: ())

        let fetchTrigger = Driver.merge(fetchBalanceSubject.asDriverOnErrorReturnEmpty(), wallet.mapToVoid())

        let balanceResponse: Driver<BalanceResponse> = fetchTrigger.withLatestFrom(wallet).flatMapLatest {
            self.useCase
                .getBalance(for: $0.address)
                .asDriverOnErrorReturnEmpty()
        }

        let zeroBalance = wallet.map { WalletBalance(wallet: $0) }

        let walletBalance: Driver<WalletBalance> = Driver.combineLatest(wallet, balanceResponse) {
            return WalletBalance(wallet: $0, balance: $1.balance, nonce: $1.nonce)
        }

        let balance = Driver.merge(zeroBalance, walletBalance)

        let recipient = fromView.recepientAddress.map {
           try? Address(hexString: $0)
        }

        let amount = fromView.amountToSend.map { Double($0) }.filterNil()
        let gasLimit = fromView.gasLimit.map { Double($0) }.filterNil()
        let gasPrice = fromView.gasPrice.map { Double($0) }.filterNil()

        let payment = Driver.combineLatest(recipient.filterNil(), amount, gasLimit, gasPrice, balanceResponse) {
            Payment(to: $0, amount: $1, gasLimit: $2, gasPrice: $3, nonce: $4.nonce)
        }.filterNil()

        let transactionId: Driver<String> = fromView.sendTrigger
            .withLatestFrom(Driver.combineLatest(payment, wallet, fromView.encryptionPassphrase) { (payment: $0, wallet: $1, passphrase: $2) })
            .flatMapLatest {
                self.useCase.sendTransaction(for: $0.payment, wallet: $0.wallet, encryptionPassphrase: $0.passphrase)
                    .asDriverOnErrorReturnEmpty()
                    // Trigger fetching of balance after successfull send
                    .do(onNext: { _ in
                        // TODO: poll API using transaction ID later on
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            fetchBalanceSubject.onNext(())
                        }
                    })
        }

        return Output(
            walletBalance: balance,
            isRecipientAddressValid: recipient.map { $0 != nil },
            transactionId: transactionId
        )
    }
}
