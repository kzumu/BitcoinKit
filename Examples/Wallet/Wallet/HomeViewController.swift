//
//  HomeViewController.swift
//
//  Copyright © 2018 Kishikawa Katsumi
//  Copyright © 2018 BitcoinKit developers
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import UIKit
import BitcoinKit

class HomeViewController: UITableViewController, PeerGroupDelegate {
    var peerGroup: PeerGroup?
    var payments = [Payment]()

    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var syncButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(walletChanged(notification:)), name: Notification.Name.AppController.walletChanged, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBalance()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let _ = AppController.shared.wallet else {
            performSegue(withIdentifier: "createWallet", sender: self)
            return
        }
    }
    
    @IBAction func sync(_ sender: UIButton) {
        guard let wallet = AppController.shared.wallet else { return }
        var addresses: [String] = []
        for i in 0..<AppController.shared.externalIndex + 20 {
            if let address = try? wallet.receiveAddress(index: i) {
                addresses.append(address.base58)
            }
        }

        syncButton.setTitle("Syncing", for: .normal)
        APIClient().getUnspentOutputs(withAddresses: addresses) { [weak self] (utxos) in
            print(utxos)

            let sum = utxos.map {
                $0.amount
                }
                .reduce(0, { (res, amount) -> Decimal in
                    return res + amount
                })
            DispatchQueue.main.async {
                self?.syncButton.setTitle("Start", for: .normal)
                self?.balanceLabel.text = "\(sum) tBCH"
            }
        }
    }
    
    @objc
    func walletChanged(notification: Notification) {
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Transactions"
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return payments.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "transactionCell", for: indexPath)

        let payment = payments[indexPath.row]
        let decimal = Decimal(payment.amount)
        let amountCoinValue = decimal / Decimal(100000000)
        let txid = payment.txid.hex
        cell.textLabel?.text = "\(amountCoinValue) BCH"
        cell.detailTextLabel?.text = txid
        print(txid, amountCoinValue, payment.from, payment.to)

        return cell
    }

    func peerGroupDidStop(_ peerGroup: PeerGroup) {
        peerGroup.delegate = nil
        self.peerGroup = nil
    }
    
    func peerGroupDidReceiveTransaction(_ peerGroup: PeerGroup) {
        updateBalance()
    }

    private func usedAddresses() -> [Address] {
        var addresses = [Address]()
        guard let wallet = AppController.shared.wallet else {
            return []
        }
        for index in 0..<(AppController.shared.externalIndex + 20) {
            if let address = try? wallet.receiveAddress(index: index) {
                addresses.append(address)
            }
        }
        for index in 0..<(AppController.shared.internalIndex + 20) {
            if let address = try? wallet.changeAddress(index: index) {
                addresses.append(address)
            }
        }
        return addresses
    }
    
    func transactions() -> [Payment] {
        let blockStore = try! SQLiteBlockStore.default()

        var payments = [Payment]()
        for address in usedAddresses() {
            let newPayments = try! blockStore.transactions(address: address)
            for p in newPayments where !payments.contains(p){
                payments.append(p)
            }
        }
        return payments
    }

    private func updateBalance() {
        let blockStore = try! SQLiteBlockStore.default()

        var balance: Int64 = 0
        for address in usedAddresses() {
            balance += try! blockStore.calculateBalance(address: address)
        }

        let decimal = Decimal(balance)
        balanceLabel.text = "\(decimal / Decimal(100000000)) BCH"

        payments = transactions()
        tableView.reloadData()
    }
    
}
