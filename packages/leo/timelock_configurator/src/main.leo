import aleox_timelock_v1.aleo;
import aleox_oracle_signers_v1.aleo;

program aleox_timelock_configurator_v1.aleo {
    const ACTION_ADD_ORACLE_SIGNER: u8 = 0u8;
    const ACTION_REMOVE_ORACLE_SIGNER: u8 = 1u8;

    struct ActionAddOracleSigner {
        action: u8,
        account: address,
    }

    struct ActionRemoveOracleSigner {
        action: u8,
        account: address,
    }

    async transition signalAddOracleSigner(public account: address) -> Future {
        assert(account != 0field as address);

        let hash: field = BHP256::hash_to_field(ActionAddOracleSigner {
            action: ACTION_ADD_ORACLE_SIGNER,
            account,
        });

        let f: Future = aleox_timelock_v1.aleo/signalPendingAction(hash);

        return finalizeSignalAddOracleSigner(f);
    }

    async function finalizeSignalAddOracleSigner(f: Future) {
        f.await();
    }

    async transition addOracleSignerAfterSignal(public account: address) -> Future {
        let hash: field = BHP256::hash_to_field(ActionAddOracleSigner {
            action: ACTION_ADD_ORACLE_SIGNER,
            account,
        });

        let f1: Future = aleox_timelock_v1.aleo/validateAndClearAction(hash);

        let f2: Future = aleox_oracle_signers_v1.aleo/addSigner(account);

        return finalizeAddOracleSignerAfterSignal(f1, f2);
    }

    async function finalizeAddOracleSignerAfterSignal(f1: Future, f2: Future) {
        f1.await();
        f2.await();
    }

    async transition signalRemoveOracleSigner(public account: address) -> Future {
        assert(account != 0field as address);

        let hash: field = BHP256::hash_to_field(ActionRemoveOracleSigner {
            action: ACTION_REMOVE_ORACLE_SIGNER,
            account,
        });

        let f: Future = aleox_timelock_v1.aleo/signalPendingAction(hash);

        return finalizeSignalRemoveOracleSigner(f);
    }

    async function finalizeSignalRemoveOracleSigner(f: Future) {
        f.await();
    }

    async transition removeOracleSignerAfterSignal(public account: address) -> Future {
        let hash: field = BHP256::hash_to_field(ActionRemoveOracleSigner {
            action: ACTION_REMOVE_ORACLE_SIGNER,
            account,
        });

        let f1: Future = aleox_timelock_v1.aleo/validateAndClearAction(hash);

        let f2: Future = aleox_oracle_signers_v1.aleo/removeSigner(account);

        return finalizeRemoveOracleSignerAfterSignal(f1, f2);
    }

    async function finalizeRemoveOracleSignerAfterSignal(f1: Future, f2: Future) {
        f1.await();
        f2.await();
    }
}
