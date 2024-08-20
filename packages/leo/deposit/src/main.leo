import multi_token_support_program.aleo;
import aleox_store_v1.aleo;
import aleox_market_v1.aleo;
import aleox_oracle_v1.aleo;

program aleox_deposit_v1.aleo {
    const CREDITS_RESERVED_TOKEN_ID: field = 3443843282313283355522573239085696902919850365217539366784739393210722344986field;

    struct Deposit {
        account: address,
        receiver: address,
        market: field,
        initialLongToken: field,
        initialShortToken: field,
        initialLongTokenAmount: u128,
        initialShortTokenAmount: u128,
        longTokenSwapPath: [field; 2],
        shortTokenSwapPath: [field; 2],
        minMarketTokens: u128,
        executionFee: u128,
        shouldUnwrapNativeToken: bool,
        updatedAtBlock: u32,
    }

    mapping deposits: u32 => Deposit; // deposit key => deposit

    mapping depositCount: u8 => u32; // 0u8 => deposit count

    mapping depositList: u32 => u32; // index => deposit key

    mapping depositByKey: u32 => u32; // deposit key => index

    mapping depositNonce: u8 => u32; // 0u8 => deposit key generator

    struct CreateDepositParams {
        receiver: address,
        market: field,
        initialLongToken: field,
        initialShortToken: field,
        initialLongTokenAmount: u128,
        initialShortTokenAmount: u128,
        longTokenSwapPath: [field; 2],
        shortTokenSwapPath: [field; 2],
        minMarketTokens: u128,
        executionFee: u128,
        shouldUnwrapNativeToken: bool,
    }

    async transition createDeposit(public params: CreateDepositParams) -> Future {
        assert(params.initialLongTokenAmount != 0u128 || params.initialShortTokenAmount != 0u128);
        assert(params.receiver != 0field as address);

        // If the initialLongToken and initialShortToken are the same, only the initialLongTokenAmount would
        // be non-zero, the initialShortTokenAmount would be zero.
        let f1: Future = multi_token_support_program.aleo/transfer_public_as_signer(
            params.initialLongToken, // token_id
            self.address, // recipient
            params.initialLongTokenAmount, // amount
        );
        let f2: Future = multi_token_support_program.aleo/transfer_public_as_signer(
            params.initialShortToken, // token_id
            self.address, // recipient
            params.initialShortTokenAmount, // amount
        );
        let f3: Future = multi_token_support_program.aleo/transfer_public_as_signer(
            CREDITS_RESERVED_TOKEN_ID, // token_id
            self.address, // recipient
            params.executionFee, // amount
        );

        return finalizeCreateDeposit(f1, f2, f3, self.signer, params);
    }

    async function finalizeCreateDeposit(f1: Future, f2: Future, f3: Future, account: address, params: CreateDepositParams) {
        let marketConfig: MarketConfig = aleox_store_v1.aleo/marketConfig.get(params.market);
        assert(marketConfig.isMarketDisabled);

        // Validate swap path.
        for i: u8 in 0u8..2u8 {
            let m: field = params.longTokenSwapPath[i];
            let cfg: MarketConfig = aleox_store_v1.aleo/marketConfig.get(m);
            assert(cfg.isMarketDisabled);
            let mkt: Market = aleox_market_v1.aleo/markets.get(m);
            assert(mkt.longToken != mkt.shortToken);

            m = params.shortTokenSwapPath[i];
            cfg = aleox_store_v1.aleo/marketConfig.get(m);
            assert(cfg.isMarketDisabled);
            mkt = aleox_market_v1.aleo/markets.get(m);
            assert(mkt.longToken != mkt.shortToken);
        }

        let deposit: Deposit = Deposit {
            account,
            receiver: params.receiver,
            market: params.market,
            initialLongToken: params.initialLongToken,
            initialShortToken: params.initialShortToken,
            initialLongTokenAmount: params.initialLongTokenAmount,
            initialShortTokenAmount: params.initialShortTokenAmount,
            longTokenSwapPath: params.longTokenSwapPath,
            shortTokenSwapPath: params.shortTokenSwapPath,
            minMarketTokens: params.minMarketTokens,
            executionFee: params.executionFee,
            shouldUnwrapNativeToken: params.shouldUnwrapNativeToken,
            updatedAtBlock: block.height,
        };

        let key: u32 = depositNonce.get_or_use(0u8, 0u32);
        depositNonce.set(0u8, key + 1u32);

        deposits.set(key, deposit);

        let index: u32 = depositCount.get_or_use(0u8, 0u32);
        depositCount.set(0u8, index + 1u32);
        depositList.set(index, key);
        depositByKey.set(key, index);

        f1.await();
        f2.await();
        f3.await();
    }

    async transition cancelDeposit(
        public key: u32,
        public deposit: Deposit,
        public cancelExecutionFee: u128,
    ) -> Future {
        let f1: Future = multi_token_support_program.aleo/transfer_public_as_signer(
            deposit.initialLongToken, // token_id
            deposit.account, // recipient
            deposit.initialLongTokenAmount, // amount
        );
        let f2: Future = multi_token_support_program.aleo/transfer_public_as_signer(
            deposit.initialShortToken, // token_id
            deposit.account, // recipient
            deposit.initialShortTokenAmount, // amount
        );
        let f3: Future = multi_token_support_program.aleo/transfer_public_as_signer(
            CREDITS_RESERVED_TOKEN_ID, // token_id
            deposit.account, // recipient
            deposit.executionFee > cancelExecutionFee ? deposit.executionFee.sub_wrapped(cancelExecutionFee) : 0u128, // amount
        );

        return finalizeCancelDeposit(f1, f2, f3, key, deposit, cancelExecutionFee);
    }

    async function finalizeCancelDeposit(
        f1: Future,
        f2: Future,
        f3: Future,
        key: u32,
        deposit: Deposit,
        cancelExecutionFee: u128,
    ) {
        assert_eq(deposits.get(key), deposit);

        // TODO: validate cancelExecutionFee

        // Remove deposit.
        {
            deposits.remove(key);

            let index: u32 = depositByKey.get(key);
            assert_eq(depositList.get(index), key);

            let lastIndex: u32 = depositCount.get(0u8) - 1u32;
            depositCount.set(0u8, lastIndex);

            // If the deposit is not the last one, move the last deposit to the removed deposit's position.
            if (index < lastIndex) {
                let keyOfLastDeposit: u32 = depositList.get(lastIndex);
                depositList.set(index, keyOfLastDeposit);
                depositByKey.set(keyOfLastDeposit, index);
            }
            // Remove the last deposit.
            depositList.remove(lastIndex);
            depositByKey.remove(key);
        }

        f1.await();
        f2.await();
        f3.await();
    }

    struct ExecuteDepositParams {
        key_: u32, // 'key' is a reserved keyword
        prices: Prices,
        keeper: address,
        includeVirtualInventoryImpact: bool,
    }

    async transition executeDeposit(
        public params: ExecuteDepositParams,
        public deposit: Deposit,
    ) -> Future {
        return finalizeExecuteDeposit(params, deposit);
    }

    async function finalizeExecuteDeposit(
        params: ExecuteDepositParams,
        deposit: Deposit,
    ) {
        let key: u32 = params.key_;

        // Remove deposit.
        {
            deposits.remove(key);

            let index: u32 = depositByKey.get(key);
            assert_eq(depositList.get(index), key);

            let lastIndex: u32 = depositCount.get(0u8) - 1u32;
            depositCount.set(0u8, lastIndex);

            // If the deposit is not the last one, move the last deposit to the removed deposit's position.
            if (index < lastIndex) {
                let keyOfLastDeposit: u32 = depositList.get(lastIndex);
                depositList.set(index, keyOfLastDeposit);
                depositByKey.set(keyOfLastDeposit, index);
            }
            // Remove the last deposit.
            depositList.remove(lastIndex);
            depositByKey.remove(key);
        }

        assert(params.prices.minBlock >= deposit.updatedAtBlock);
    }
}
