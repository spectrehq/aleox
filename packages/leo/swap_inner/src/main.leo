import multi_token_support_programv1.aleo;
import aleox_store_v1.aleo;
import aleox_market_v1.aleo;
import aleox_pricing_v1.aleo;
import aleox_fee_v1.aleo;

program aleox_swap_inner_v1.aleo {
    const ZERO_FIELD: field = 0field;
    const ZERO_ADDRESS: address = aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;

    struct SwapParams_ {
        isLongTokenIn: bool,
        amountIn: u128,
        receiver: address,
        shouldUnwrapNativeToken: bool,
    }

    const SwapPricingTwoStep: u8 = 0u8;

    const PnlFactorForDeposits: u8 = 3u8;
    const PnlFactorForWithdrawals: u8 = 4u8;

    async transition swap(
        public params_: SwapParams_,
        public generalConfig: GeneralConfig,
        public market: Market,
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public virtualMarketData: VirtualMarketData,
        public prices: Prices,
    ) -> (field, u128, MarketData, VirtualMarketData, Future) {
        assert(!marketConfig.isMarketDisabled);
        assert(market.longToken != market.shortToken);

        let tokenOut: field = params_.isLongTokenIn ? market.longToken : market.shortToken;

        let tokenInPrice: Price = params_.isLongTokenIn ? prices.longToken : prices.shortToken;
        let tokenOutPrice: Price = params_.isLongTokenIn ? prices.shortToken : prices.longToken;
        let tokenInMidPrice: u128 = aleox_oracle_v1.aleo/midPrice(tokenInPrice);
        let tokenOutMidPrice: u128 = aleox_oracle_v1.aleo/midPrice(tokenOutPrice);

        let usdDeltaForTokenIn: i128 = (params_.amountIn * tokenInMidPrice) as i128;
        let usdDeltaForTokenOut: i128 = -usdDeltaForTokenIn;

        let priceImpactUsd: i128 = aleox_pricing_v1.aleo/getPriceImpactUsd(
            market,
            marketConfig,
            marketData,
            virtualMarketData,
            prices,
            usdDeltaForTokenIn,
            usdDeltaForTokenOut,
            true,
        );

        let fees: SwapFees = aleox_pricing_v1.aleo/getSwapFees(
            generalConfig,
            marketConfig,
            marketData,
            params_.amountIn,
            priceImpactUsd > 0i128, // forPositiveImpact
            SwapPricingTwoStep,
        );

        marketData = aleox_fee_v1.aleo/incrementClaimableFeeAmount(
            marketData,
            params_.isLongTokenIn,
            fees.feeReceiverAmount,
        );

        let amountIn: u128 = 0u128;
        let amountOut: u128 = 0u128;
        let poolAmountOut: u128 = 0u128;

        if (priceImpactUsd > 0i128) {
            amountIn = fees.amountAfterFees;

            let (marketData1, priceImpactAmount, cappedDiffUsd): (MarketData, i128, u128) = aleox_market_v1.aleo/applySwapImpactWithCap(
                marketData,
                prices,
                !params_.isLongTokenIn,
                priceImpactUsd,
            );
            marketData = marketData1;

            if (cappedDiffUsd != 0u128) {
                let (marketData2, tokenInPriceImpactAmount, c): (MarketData, i128, u128) = aleox_market_v1.aleo/applySwapImpactWithCap(
                    marketData,
                    prices,
                    params_.isLongTokenIn,
                    cappedDiffUsd as i128,
                );
                marketData = marketData2;

                amountIn += tokenInPriceImpactAmount as u128;
            }

            amountOut = amountIn * tokenInPrice.min / tokenOutPrice.max;
            poolAmountOut = amountOut;

            amountOut += priceImpactAmount as u128;
        } else {
            let (marketData3, priceImpactAmount, c): (MarketData, i128, u128) = aleox_market_v1.aleo/applySwapImpactWithCap(
                marketData,
                prices,
                params_.isLongTokenIn,
                priceImpactUsd,
            );
            marketData = marketData3;

            amountIn = fees.amountAfterFees - (-priceImpactAmount) as u128;
            amountOut = amountIn * tokenInPrice.min / tokenOutPrice.max;
            poolAmountOut = amountOut;
        }

        let f: Future = aleox_market_v1.aleo/transferOut(
            params_.isLongTokenIn ? market.shortToken : market.longToken, // token_id
            params_.receiver, // recipient
            params_.receiver != ZERO_ADDRESS ? amountOut : 0u128, // amount
            params_.shouldUnwrapNativeToken,
        );

        let (marketData4, virtualMarketData1): (MarketData, VirtualMarketData) = aleox_market_v1.aleo/applyDeltaToPoolAmount(
            marketConfig,
            marketData,
            virtualMarketData,
            params_.isLongTokenIn,
            (amountIn + fees.feeAmountForPool) as i128,
        );
        marketData = marketData4;
        virtualMarketData = virtualMarketData1;

        let (marketData5, virtualMarketData2): (MarketData, VirtualMarketData) = aleox_market_v1.aleo/applyDeltaToPoolAmount(
            marketConfig,
            marketData,
            virtualMarketData,
            !params_.isLongTokenIn,
            poolAmountOut as i128,
        );
        marketData = marketData5;
        virtualMarketData = virtualMarketData2;

        aleox_market_v1.aleo/validatePoolAmount(
            marketConfig,
            marketData,
            params_.isLongTokenIn,
        );

        aleox_market_v1.aleo/validateReserve(
            marketConfig,
            marketData,
            prices,
            !params_.isLongTokenIn,
        );

        aleox_market_v1.aleo/validateMaxPnl(
            marketConfig,
            marketData,
            prices,
            params_.isLongTokenIn ? PnlFactorForDeposits : PnlFactorForWithdrawals,
            params_.isLongTokenIn ? PnlFactorForWithdrawals : PnlFactorForDeposits,
        );

        return (tokenOut, amountOut, marketData, virtualMarketData, finalizeSwap(f));
    }

    async function finalizeSwap(
        f: Future
    ) {
        f.await();
    }
}
