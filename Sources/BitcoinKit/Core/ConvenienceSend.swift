//
//  ConvenienceSend.swift
//  BitcoinKit
//
//  Created by 下村一将 on 2018/08/21.
//  Copyright © 2018 BitcoinKit developers. All rights reserved.
//

import Foundation

class ConvenienceSend {
    private func send(toAddress: Address, amount: Int64, changeAddress: Address, wallet: HDWallet,
                      externalIndexEnd: UInt32, internalIndexEnd: UInt32, utxos: [UnspentTransaction]) throws {
        let usedAddresses: [Address] = { //自分が作成したアドレスの配列
            var addresses = [Address]()
            for index in 0..<(externalIndexEnd + 20) { //最後に使用したアドレスの20番後までチェック
                if let address = try? wallet.receiveAddress(index: index) {
                    addresses.append(address)
                }
            }
            for index in 0..<(internalIndexEnd + 20) {
                if let address = try? wallet.changeAddress(index: index) {
                    addresses.append(address)
                }
            }
            return addresses
        }()

        let unsignedTx: UnsignedTransaction = {
            let (selectedUtxos, fee) = (utxos, 500) // TODO: 支払いに使うUtxoを選択
            let totalAmount: Int64 = selectedUtxos.reduce(0) { $0 + $1.output.value }
            let change: Int64 = totalAmount - amount - fee

            let toPubKeyHash: Data = toAddress.data
            let changePubkeyHash: Data = changeAddress.data

            let lockingScriptTo = Script.buildPublicKeyHashOut(pubKeyHash: toPubKeyHash)
            let lockingScriptChange = Script.buildPublicKeyHashOut(pubKeyHash: changePubkeyHash)

            let toOutput = TransactionOutput(value: amount, lockingScript: lockingScriptTo)
            let changeOutput = TransactionOutput(value: change, lockingScript: lockingScriptChange)

            // この後、signatureScriptやsequenceは更新される
            let unsignedInputs = utxos.map { TransactionInput(previousOutput: $0.outpoint, signatureScript: Data(), sequence: UInt32.max) }
            let tx = Transaction(version: 1, inputs: unsignedInputs, outputs: [toOutput, changeOutput], lockTime: 0)
            return UnsignedTransaction(tx: tx, utxos: utxos)
        }()

        let signedTx: Transaction = try {
            let keys = usedKeys(wallet: wallet, externalIndex: externalIndexEnd, internalIndex: internalIndexEnd)
            var inputsToSign = unsignedTx.tx.inputs
            var transactionToSign: Transaction {
                return Transaction(version: unsignedTx.tx.version, inputs: inputsToSign, outputs: unsignedTx.tx.outputs, lockTime: unsignedTx.tx.lockTime) // 作る必要ある？
            }

            // Signing
            let hashType = SighashType.BCH.ALL
            for (i, utxo) in unsignedTx.utxos.enumerated() {
                let pubkeyHash: Data = Script.getPublicKeyHash(from: utxo.output.lockingScript)

                // 自分がスクリプトを作ったときのpubKeyHashであるPrivateKeyを抽出
                let keysOfUtxo: [PrivateKey] = keys.filter { $0.publicKey().pubkeyHash == pubkeyHash }
                guard let key = keysOfUtxo.first else {
                    print("No keys to this txout : \(utxo.output.value)")
                    continue
                }
                print("Value of signing txout : \(utxo.output.value)")

                let sighash: Data = transactionToSign.signatureHash(for: utxo.output, inputIndex: i, hashType: SighashType.BCH.ALL)
                let signature: Data = try Crypto.sign(sighash, privateKey: key)
                let txin = inputsToSign[i]
                let pubkey = key.publicKey()

                let unlockingScript = Script.buildPublicKeyUnlockingScript(signature: signature, pubkey: pubkey, hashType: hashType)

                // TODO: sequenceの更新
                inputsToSign[i] = TransactionInput(previousOutput: txin.previousOutput, signatureScript: unlockingScript, sequence: txin.sequence)
            }
            print("aaaaa", transactionToSign.outputs)
            return transactionToSign
            }()

        APIClient().postTx(withRawTx: signedTx.serialized().hex) { (str1, str2) in
            print("Posted -> \(str1 ?? "") : \(str2 ?? "")")
        }
    }

    private func usedKeys(wallet: HDWallet, externalIndex: UInt32, internalIndex: UInt32) -> [PrivateKey] {
        var keys = [PrivateKey]()
        // Receive key
        for index in 0..<(externalIndex + 20) {
            if let key = try? wallet.privateKey(index: index) {
                keys.append(key)
            }
        }
        // Change key
        for index in 0..<(internalIndex + 20) {
            if let key = try? wallet.changePrivateKey(index: index) {
                keys.append(key)
            }
        }

        return keys
    }
}
