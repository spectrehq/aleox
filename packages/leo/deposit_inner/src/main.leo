import multi_token_support_programv1.aleo;
import aleox_store_v1.aleo;
import aleox_market_v1.aleo;
import aleox_oracle_v1.aleo;
import aleox_pricing_v1.aleo;
import aleox_fee_v1.aleo;

program aleox_deposit_inner_v1.aleo {
    const CREDITS_RESERVED_TOKEN_ID: field = 3443843282313283355522573239085696902919850365217539366784739393210722344986field;

    const RECEIVER_FOR_FIRST_DEPOSIT: address = aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc; // 1field as address

    struct ExecuteDepositParams {
        key_: u32, // 'key' is a reserved keyword
        keeper: address,
        swapPricingType: u8,
        includeVirtualInventoryImpact: bool,
        marketTokensSupply: u128,
        atBlock: u32,
    }

    struct ExecuteDepositParams_ {
        account: address,
        receiver: address,
        isLong: bool,
        amount: u128,
        priceImpactUsd: i128,
    }

    const PnlFactorForDeposits: u8 = 3u8;

    async transition executeDeposit(
        public params: ExecuteDepositParams,
        public params_: ExecuteDepositParams_,
        public market: Market,
        public generalConfig: GeneralConfig,
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public virtualMarketData: VirtualMarketData,
        public prices: Prices,
    ) -> (u128, MarketData, VirtualMarketData, Future) {
        let tokenInPrice: Price = params_.isLong ? prices.longToken : prices.shortToken;
        let tokenOutPrice: Price = params_.isLong ? prices.shortToken : prices.longToken;
        let marketTokensSupply: u128 = params.marketTokensSupply;

        let fees: SwapFees = aleox_pricing_v1.aleo/getSwapFees(
            generalConfig,
            marketConfig,
            marketData,
            params_.amount,
            params_.priceImpactUsd > 0i128, // forPositiveImpact
            params.swapPricingType
        );

        marketData = aleox_fee_v1.aleo/incrementClaimableFeeAmount(
            marketData,
            params_.isLong,
            fees.feeReceiverAmount,
        );

        let poolValueInfo: MarketPoolValueInfo = aleox_market_v1.aleo/getPoolValueInfo(
            generalConfig,
            marketConfig,
            marketData,
            prices,
            PnlFactorForDeposits,
            true, // maximize
            params.atBlock,
        );

        assert(poolValueInfo.poolValue >= 0i128);
        let poolValue: u128 = poolValueInfo.poolValue as u128;


        assert(poolValue > 0u128 || marketTokensSupply == 0u128);

        let mintAmount: u128 = 0u128;

        let priceImpactUsd: i128 = marketTokensSupply == 0u128 ? 0i128 : params_.priceImpactUsd;

        if (priceImpactUsd > 0i128) {
            let (marketData1, positiveImpactAmount, cappedDiffUsd): (MarketData, i128, u128) = aleox_market_v1.aleo/applySwapImpactWithCap(
                marketData,
                prices,
                !params_.isLong,
                priceImpactUsd,
            );
            marketData = marketData1;

            mintAmount += aleox_market_v1.aleo/usdToMarketTokenAmount(
                positiveImpactAmount as u128 * tokenOutPrice.max,
                poolValue,
                marketTokensSupply
            );

            let (marketData2, virtualMarketData1): (MarketData, VirtualMarketData) = aleox_market_v1.aleo/applyDeltaToPoolAmount(
                marketConfig,
                marketData,
                virtualMarketData,
                !params_.isLong,
                positiveImpactAmount,
            );
            marketData = marketData2;
            virtualMarketData = virtualMarketData1;

            aleox_market_v1.aleo/validatePoolAmount(
                marketConfig,
                marketData,
                !params_.isLong,
            );
        }

        if (priceImpactUsd < 0i128) {
            let (marketData3, negativeImpactAmount, cappedDiffUsd): (MarketData, i128, u128) = aleox_market_v1.aleo/applySwapImpactWithCap(
                marketData,
                prices,
                params_.isLong,
                priceImpactUsd,
            );
            marketData = marketData3;

            fees = SwapFees {
                feeReceiverAmount: fees.feeReceiverAmount,
                feeAmountForPool: fees.feeAmountForPool,
                amountAfterFees: fees.amountAfterFees - (-negativeImpactAmount) as u128,
            };
        }

        mintAmount += aleox_market_v1.aleo/usdToMarketTokenAmount(
            fees.amountAfterFees * tokenInPrice.min,
            poolValue,
            marketTokensSupply,
        );

        let (marketData4, virtualMarketData2): (MarketData, VirtualMarketData) = aleox_market_v1.aleo/applyDeltaToPoolAmount(
            marketConfig,
            marketData,
            virtualMarketData,
            params_.isLong,
            (fees.amountAfterFees + fees.feeAmountForPool) as i128,
        );
        marketData = marketData4;
        virtualMarketData = virtualMarketData2;

        validatePoolUsdForDeposit(
            marketConfig,
            marketData,
            params_.isLong,
            tokenInPrice.max,
        );

        aleox_market_v1.aleo/validatePoolAmount(
            marketConfig,
            marketData,
            params_.isLong,
        );

        let f: Future = aleox_market_v1.aleo/mintMarketTokens(market.marketToken, params_.receiver, mintAmount);

        return (mintAmount, marketData, virtualMarketData, finalizeExecuteDeposit(f, market.marketToken, marketTokensSupply));
    }

    async function finalizeExecuteDeposit(f: Future, marketToken: field, marketTokensSupply: u128) {
        let metadata: TokenMetadata = multi_token_support_programv1.aleo/registered_tokens.get(marketToken);
        assert_eq(marketTokensSupply, metadata.supply);

        f.await();
    }

    inline validatePoolUsdForDeposit(
        marketConfig: MarketConfig,
        marketData: MarketData,
        isLong: bool,
        tokenPrice: u128,
    ) {
        let poolAmount: u128 = isLong ? marketData.poolAmount.long : marketData.poolAmount.short;
        let poolUsd: u128 = poolAmount * tokenPrice;
        let maxPoolUsd: u128 = isLong ? marketConfig.maxPoolUsdForDeposit.long : marketConfig.maxPoolUsdForDeposit.short;
        assert(poolUsd <= maxPoolUsd);
    }
}
