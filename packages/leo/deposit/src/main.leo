import aleox_deposit_inner_v1.aleo;

program aleox_deposit_v1.aleo {
    const CREDITS_RESERVED_TOKEN_ID: field = 3443843282313283355522573239085696902919850365217539366784739393210722344986field;

    const RECEIVER_FOR_FIRST_DEPOSIT: address = aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc; // 1field as address

    const USD_DIVISOR_U: u128 = 10_000_000_000_000_000u128; // 10^16; 16 = 22 - 6

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

        let f4: Future = aleox_market_v1.aleo/validateSwapPath(params.longTokenSwapPath);
        let f5: Future = aleox_market_v1.aleo/validateSwapPath(params.shortTokenSwapPath);

        return finalizeCreateDeposit(
            f1,
            f2,
            f3,
            f4,
            f5,
            self.signer,
            params,
        );
    }

    async function finalizeCreateDeposit(
        f1: Future,
        f2: Future,
        f3: Future,
        f4: Future,
        f5: Future,
        account: address,
        params: CreateDepositParams,
    ) {
        let marketConfig: MarketConfig = aleox_store_v1.aleo/marketConfig.get(params.market);
        assert(!marketConfig.isMarketDisabled);

        f4.await();
        f5.await();

        // Add deposit.
        {
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
        }

        f1.await();
        f2.await();
        f3.await();
    }

    async transition cancelDeposit(
        public key: u32,
        public deposit: Deposit,
        public cancelExecutionFee: u128,
    ) -> Future {
        let f1: Future = multi_token_support_program.aleo/transfer_public(
            deposit.initialLongToken, // token_id
            deposit.account, // recipient
            deposit.initialLongTokenAmount, // amount
        );
        let f2: Future = multi_token_support_program.aleo/transfer_public(
            deposit.initialShortToken, // token_id
            deposit.account, // recipient
            deposit.initialShortTokenAmount, // amount
        );
        let f3: Future = multi_token_support_program.aleo/transfer_public(
            CREDITS_RESERVED_TOKEN_ID, // token_id
            deposit.account, // recipient
            deposit.executionFee - cancelExecutionFee, // amount
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

    const PnlFactorForDeposits: u8 = 3u8;

    async transition executeDeposit(
        public params: ExecuteDepositParams,
        public deposit: Deposit,
        public market: Market,
        public generalConfig: GeneralConfig,
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public prices: Prices,
    ) -> (u128, MarketData, Future) {
        assert(!marketConfig.isMarketDisabled);

        assert(prices.minBlock >= deposit.updatedAtBlock &&
            prices.maxBlock <= deposit.updatedAtBlock + generalConfig.requestExpirationBlocks
        );

        let (marketData1, f1): (MarketData, Future) = aleox_market_v1.aleo/distributePositionImpactPool(
            marketConfig,
            marketData,
            params.atBlock,
        );
        marketData = marketData1;

        let (marketData2, f2): (MarketData, Future) = aleox_market_v1.aleo/updateFundingAndBorrowingState(
            market,
            generalConfig,
            marketConfig,
            marketData,
            prices,
            params.atBlock,
        );
        marketData = marketData2;

        aleox_market_v1.aleo/validateMaxPnl(
            marketConfig,
            marketData,
            prices,
            PnlFactorForDeposits,
            PnlFactorForDeposits,
        );

        let longTokenAmount: u128 = 0u128;
        let shortTokenAmount: u128 = 0u128;

        // TODO: swap

        assert(longTokenAmount > 0u128 || shortTokenAmount > 0u128);

        let longTokenUsd: u128 = longTokenAmount * aleox_oracle_v1.aleo/midPrice(prices.longToken);
        let shortTokenUsd: u128 = shortTokenAmount * aleox_oracle_v1.aleo/midPrice(prices.shortToken);
        let tokenUsdDivided: u128 = (longTokenUsd + shortTokenUsd) / USD_DIVISOR_U;

        let priceImpactUsd: i128 = aleox_pricing_v1.aleo/getPriceImpactUsd(
            market,
            prices,
            longTokenUsd as i128,
            shortTokenUsd as i128,
            params.includeVirtualInventoryImpact,
        );
        let priceImpactUsdAbs: u128 = priceImpactUsd.abs() as u128;
        let priceImpactUsdSign: i128 = priceImpactUsd >= 0i128 ? 1i128 : -1i128;

        let (mintAmount1, marketData3, f3): (u128, MarketData, Future) = aleox_deposit_inner_v1.aleo/executeDeposit(
            params,
            ExecuteDepositParams_ {
                account: deposit.account,
                receiver: deposit.receiver,
                isLong: true,
                amount: longTokenAmount,
                priceImpactUsd: (priceImpactUsdAbs * (longTokenUsd / USD_DIVISOR_U) / tokenUsdDivided) as i128 * priceImpactUsdSign,
            },
            market,
            generalConfig,
            marketConfig,
            marketData,
            prices,
        );
        marketData = marketData3;

        let (mintAmount2, marketData4, f4): (u128, MarketData, Future) = aleox_deposit_inner_v1.aleo/executeDeposit(
            params,
            ExecuteDepositParams_ {
                account: deposit.account,
                receiver: deposit.receiver,
                isLong: false,
                amount: shortTokenAmount,
                priceImpactUsd: (priceImpactUsdAbs * (shortTokenUsd / USD_DIVISOR_U) / tokenUsdDivided) as i128 * priceImpactUsdSign,
            },
            market,
            generalConfig,
            marketConfig,
            marketData,
            prices,
        );
        marketData = marketData4;

        let receivedMarketTokens: u128 = mintAmount1 + mintAmount2;
        assert(receivedMarketTokens >= deposit.minMarketTokens);

        let f5: Future = aleox_market_v1.aleo/validateMarketTokenBalance(
            market,
            marketData,
        );

        // TODO: payExecutionFee

        return (receivedMarketTokens, marketData, finalizeExecuteDeposit(
            f1,
            f2,
            f3,
            f4,
            f5,
            params,
            deposit,
            marketConfig,
        ));
    }

    async function finalizeExecuteDeposit(
        f1: Future,
        f2: Future,
        f3: Future,
        f4: Future,
        f5: Future,
        params: ExecuteDepositParams,
        deposit: Deposit,
        marketConfig: MarketConfig,
    ) {
        // Validate whether this is the first deposit.
        let metadata: TokenMetadata = multi_token_support_program.aleo/registered_tokens.get(deposit.market);
        validateFirstDeposit(marketConfig, deposit, metadata.supply);

        f1.await();
        f2.await();
        f3.await();
        f4.await();
        f5.await();

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
    }

    // This method validates that a specified minimum number of market tokens are locked.
    // This can be used to help ensure a minimum amount of liquidity for a market.
    // This also helps to prevent manipulation of the market token price by the first depositor,
    // since it may be possible to deposit a small amount of tokens on the first deposit
    // to cause a high market token price due to rounding of the amount of tokens minted.
    inline validateFirstDeposit(
        marketConfig: MarketConfig,
        deposit: Deposit,
        marketTokenSupply: u128,
    ) {
        // Return if this is not the first deposit.
        if (marketTokenSupply > 0u128) {
            return;
        }

        // Return if there is no minMarketTokens requirement.
        if (marketConfig.minMarketTokensForFirstDeposit == 0u128) {
            return;
        }

        assert(deposit.receiver == RECEIVER_FOR_FIRST_DEPOSIT);
        assert(deposit.minMarketTokens >= marketConfig.minMarketTokensForFirstDeposit);
    }
}
