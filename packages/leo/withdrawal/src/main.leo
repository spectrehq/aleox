import multi_token_support_program.aleo;
import aleox_store_v1.aleo;
import aleox_market_v1.aleo;
import aleox_oracle_v1.aleo;
import aleox_pricing_v1.aleo;
import aleox_fee_v1.aleo;

program aleox_withdrawal_v1.aleo {
    const CREDITS_RESERVED_TOKEN_ID: field = 3443843282313283355522573239085696902919850365217539366784739393210722344986field;

    const USD_DIVISOR_U: u128 = 10_000_000_000_000_000u128; // 10^16; 16 = 22 - 6

    struct Withdrawal {
        account: address,
        receiver: address,
        market: field,
        marketTokenAmount: u128,
        longTokenSwapPath: [field; 2],
        shortTokenSwapPath: [field; 2],
        minLongTokenAmount: u128,
        minShortTokenAmount: u128,
        executionFee: u128,
        shouldUnwrapNativeToken: bool,
        updatedAtBlock: u32,
    }

    mapping withdrawals: u32 => Withdrawal; // withdrawal key => withdrawal

    mapping withdrawalCount: u8 => u32; // 0u8 => withdrawal count

    mapping withdrawalList: u32 => u32; // index => withdrawal key

    mapping withdrawalByKey: u32 => u32; // withdrawal key => index

    mapping withdrawalNonce: u8 => u32; // 0u8 => withdrawal key generator

    struct CreateWithdrawalParams {
        receiver: address,
        market: field,
        marketTokenAmount: u128,
        longTokenSwapPath: [field; 2],
        shortTokenSwapPath: [field; 2],
        minLongTokenAmount: u128,
        minShortTokenAmount: u128,
        executionFee: u128,
        shouldUnwrapNativeToken: bool,
    }

    async transition createWithdrawal(public params: CreateWithdrawalParams) -> Future {
        assert(params.receiver != 0field as address);
        assert(params.marketTokenAmount > 0u128);

        let f1: Future = multi_token_support_program.aleo/transfer_public_as_signer(
            params.market, // token_id
            self.address, // recipient
            params.marketTokenAmount, // amount
        );
        let f2: Future = multi_token_support_program.aleo/transfer_public_as_signer(
            CREDITS_RESERVED_TOKEN_ID, // token_id
            self.address, // recipient
            params.executionFee, // amount
        );

        let f3: Future = aleox_market_v1.aleo/validateSwapPath(params.longTokenSwapPath);
        let f4: Future = aleox_market_v1.aleo/validateSwapPath(params.shortTokenSwapPath);

        return finalizeCreateWithdrawal(
            f1,
            f2,
            f3,
            f4,
            self.signer,
            params,
        );
    }

    async function finalizeCreateWithdrawal(
        f1: Future,
        f2: Future,
        f3: Future,
        f4: Future,
        account: address,
        params: CreateWithdrawalParams,
    ) {
        let marketConfig: MarketConfig = aleox_store_v1.aleo/marketConfig.get(params.market);
        assert(!marketConfig.isMarketDisabled);

        f1.await();
        f2.await();
        f3.await();
        f4.await();

        // Add withdrawal.
        {
            let withdrawal: Withdrawal = Withdrawal {
                account,
                receiver: params.receiver,
                market: params.market,
                marketTokenAmount: params.marketTokenAmount,
                longTokenSwapPath: params.longTokenSwapPath,
                shortTokenSwapPath: params.shortTokenSwapPath,
                minLongTokenAmount: params.minLongTokenAmount,
                minShortTokenAmount: params.minShortTokenAmount,
                executionFee: params.executionFee,
                shouldUnwrapNativeToken: params.shouldUnwrapNativeToken,
                updatedAtBlock: block.height,
            };

            let key: u32 = withdrawalNonce.get_or_use(0u8, 0u32);
            withdrawalNonce.set(0u8, key + 1u32);

            withdrawals.set(key, withdrawal);

            let index: u32 = withdrawalCount.get_or_use(0u8, 0u32);
            withdrawalCount.set(0u8, index + 1u32);
            withdrawalList.set(index, key);
            withdrawalByKey.set(key, index);
        }
    }

    async transition cancelWithdrawal(
        public key: u32,
        public withdrawal: Withdrawal,
        public cancelExecutionFee: u128,
    ) -> Future {
        let f1: Future = multi_token_support_program.aleo/transfer_public(
            withdrawal.market, // token_id
            withdrawal.account, // recipient
            withdrawal.marketTokenAmount, // amount
        );
        let f2: Future = multi_token_support_program.aleo/transfer_public(
            CREDITS_RESERVED_TOKEN_ID, // token_id
            withdrawal.account, // recipient
            withdrawal.executionFee - cancelExecutionFee, // amount
        );

        return finalizeCancelWithdrawal(
            f1,
            f2,
            key,
            withdrawal,
            cancelExecutionFee,
        );
    }

    async function finalizeCancelWithdrawal(
        f1: Future,
        f2: Future,
        public key: u32,
        public withdrawal: Withdrawal,
        public cancelExecutionFee: u128,
    ) {
        assert_eq(withdrawals.get(key), withdrawal);

        // TODO: validate cancelExecutionFee

        // Remove withdrawal.
        {
            withdrawals.remove(key);

            let index: u32 = withdrawalByKey.get(key);
            assert_eq(withdrawalList.get(index), key);

            let lastIndex: u32 = withdrawalCount.get(0u8) - 1u32;
            withdrawalCount.set(0u8, lastIndex);

            // If the withdrawal is not the last one, move the last withdrawal to the removed withdrawal's position.
            if (index < lastIndex) {
                let keyOfLastWithdrawal: u32 = withdrawalList.get(lastIndex);
                withdrawalList.set(index, keyOfLastWithdrawal);
                withdrawalByKey.set(keyOfLastWithdrawal, index);
            }
            // Remove the last withdrawal.
            withdrawalList.remove(lastIndex);
            withdrawalByKey.remove(key);
        }

        f1.await();
        f2.await();
    }

    struct ExecuteWithdrawalParams {
        key_: u32, // 'key' is a reserved keyword
        keeper: address,
        swapPricingType: u8,
        marketTokensSupply: u128,
        atBlock: u32,
    }

    async transition executeWithdrawal(
        public params: ExecuteWithdrawalParams,
        public withdrawal: Withdrawal,
        public market: Market,
        public generalConfig: GeneralConfig,
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public prices: Prices,
    ) -> (MarketData, Future) {
        assert(!marketConfig.isMarketDisabled);
        assert(withdrawal.marketTokenAmount > 0u128);

        assert(prices.minBlock >= withdrawal.updatedAtBlock &&
            prices.maxBlock <= withdrawal.updatedAtBlock + generalConfig.requestExpirationBlocks
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

        let (longTokenOutputAmount, shortTokenOutputAmount): (u128, u128) = getOutputAmounts(
            params,
            withdrawal,
            market,
            generalConfig,
            marketConfig,
            marketData,
            prices,
        );

        let longTokenFees: SwapFees = aleox_pricing_v1.aleo/getSwapFees(
            generalConfig,
            marketConfig,
            marketData,
            longTokenOutputAmount,
            false, // forPositiveImpact
            params.swapPricingType
        );

        marketData = aleox_fee_v1.aleo/incrementClaimableFeeAmount(
            marketData,
            true, // isLong
            longTokenFees.feeReceiverAmount,
        );

        let shortTokenFees: SwapFees = aleox_pricing_v1.aleo/getSwapFees(
            generalConfig,
            marketConfig,
            marketData,
            shortTokenOutputAmount,
            false, // forPositiveImpact
            params.swapPricingType
        );

        marketData = aleox_fee_v1.aleo/incrementClaimableFeeAmount(
            marketData,
            false, // isLong
            shortTokenFees.feeReceiverAmount,
        );

        let longTokenPoolAmountDelta: u128 = longTokenOutputAmount - longTokenFees.feeAmountForPool;
        longTokenOutputAmount = longTokenFees.amountAfterFees;

        let shortTokenPoolAmountDelta: u128 = shortTokenOutputAmount - shortTokenFees.feeAmountForPool;
        shortTokenOutputAmount = shortTokenFees.amountAfterFees;

        marketData = aleox_market_v1.aleo/applyDeltaToPoolAmount(
            marketConfig,
            marketData,
            true, // isLong
            -(longTokenPoolAmountDelta as i128)
        );

        marketData = aleox_market_v1.aleo/applyDeltaToPoolAmount(
            marketConfig,
            marketData,
            false, // isLong
            -(shortTokenPoolAmountDelta as i128)
        );

        aleox_market_v1.aleo/validateReserve(
            marketConfig,
            marketData,
            prices,
            true, // isLong
        );

        aleox_market_v1.aleo/validateReserve(
            marketConfig,
            marketData,
            prices,
            false, // isLong
        );

        aleox_market_v1.aleo/validateMaxPnl(
            marketConfig,
            marketData,
            prices,
            PnlFactorForWithdrawals,
            PnlFactorForWithdrawals,
        );

        let f3: Future = aleox_market_v1.aleo/burnMarketTokens(market.marketToken, self.address, withdrawal.marketTokenAmount);

        // TODO: swap

        // If the native token was transferred to the receiver in a swap,
        // it may be possible to invoke external programs before the validations
        // are called.
        let f4: Future = aleox_market_v1.aleo/validateMarketTokenBalance(
            market,
            marketData,
        );

        // TODO: payExecutionFee

        return (marketData, finalizeExecuteWithdrawal(
            f1,
            f2,
            f3,
            f4,
        ));
    }

    async function finalizeExecuteWithdrawal(
        f1: Future,
        f2: Future,
        f3: Future,
        f4: Future,
    ) {
        f1.await();
        f2.await();
        f3.await();
        f4.await();
    }

    const PnlFactorForWithdrawals: u8 = 4u8;

    inline getOutputAmounts(
        params: ExecuteWithdrawalParams,
        withdrawal: Withdrawal,
        market: Market,
        generalConfig: GeneralConfig,
        marketConfig: MarketConfig,
        marketData: MarketData,
        prices: Prices,
    ) -> (u128, u128) {
        // The max pnl factor for withdrawals should be the lower of the max pnl factor values
        // which means that pnl would be capped to a smaller amount and the pool
        // value would be higher even if there is a large pnl.
        // This should be okay since validateMaxPnl is called after the withdrawal
        // which ensures that the max pnl factor for withdrawals was not exceeded.
        let poolValueInfo: MarketPoolValueInfo = aleox_market_v1.aleo/getPoolValueInfo(
            generalConfig,
            marketConfig,
            marketData,
            prices,
            PnlFactorForWithdrawals,
            false, // maximize
            params.atBlock,
        );

        assert(poolValueInfo.poolValue > 0i128);
        let poolValue: u128 = poolValueInfo.poolValue as u128;

        let longTokenPoolUsd: u128 = marketData.poolAmount.long * prices.longToken.max;
        let shortTokenPoolUsd: u128 = marketData.poolAmount.short * prices.shortToken.max;

        let totalPoolUsd: u128 = longTokenPoolUsd + shortTokenPoolUsd;

        let marketTokensUsd: u128 = aleox_market_v1.aleo/marketTokenAmountToUsd(
            withdrawal.marketTokenAmount,
            poolValue,
            params.marketTokensSupply
        );

        let longTokenOutputUsd: u128 = marketTokensUsd * (longTokenPoolUsd / USD_DIVISOR_U) / (totalPoolUsd / USD_DIVISOR_U);
        let shortTokenOutputUsd: u128 = marketTokensUsd * (shortTokenPoolUsd / USD_DIVISOR_U) / (totalPoolUsd / USD_DIVISOR_U);

        return (
            longTokenOutputUsd / prices.longToken.max,
            shortTokenOutputUsd / prices.shortToken.max
        );
    }
}
