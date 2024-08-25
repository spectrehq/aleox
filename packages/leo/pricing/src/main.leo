import aleox_store_v1.aleo;
import aleox_market_v1.aleo;
import aleox_oracle_v1.aleo;

program aleox_pricing_v1.aleo {
    const PRECISION_U: u128 = 10_000_000_000_000_000_000_000u128; // 10^22
    const PRECISION_I: i128 = 10_000_000_000_000_000_000_000i128; // 10^22
    const USD_DIVISOR_U: u128 = 10_000_000_000_000_000u128; // 10^16; 16 = 22 - 6
    const USD_DIVISOR_I: i128 = 10_000_000_000_000_000i128; // 10^16; 16 = 22 - 6
    const FACTOR_PRECISION_U: u128 = 10_000u128; // 10^4
    const FACTOR_PRECISION_I: i128 = 10_000i128; // 10^4

    const ZERO_FIELD: field = 0field;

    transition getPriceImpactUsd(
        public market: Market,
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public virtualMarketData: VirtualMarketData,
        public prices: Prices,
        public usdDeltaForTokenA: i128,
        public usdDeltaForTokenB: i128,
        public includeVirtualInventoryImpact: bool,
    ) -> i128 {
        let priceForTokenA: u128 = aleox_oracle_v1.aleo/midPrice(prices.longToken);
        let priceForTokenB: u128 = aleox_oracle_v1.aleo/midPrice(prices.shortToken);

        let poolParams: PoolParams = getNextPoolAmountsParams(
            priceForTokenA,
            priceForTokenB,
            usdDeltaForTokenA,
            usdDeltaForTokenB,
            marketData.poolAmount.long,
            marketData.poolAmount.short,
        );

        let priceImpactUsd: i128 = getPriceImpactUsd_(
            marketConfig,
            poolParams.poolUsdForTokenA,
            poolParams.poolUsdForTokenB,
            poolParams.nextPoolUsdForTokenA,
            poolParams.nextPoolUsdForTokenB,
        );

        if (priceImpactUsd >= 0i128) {
            return priceImpactUsd;
        }

        if (!includeVirtualInventoryImpact) {
            return priceImpactUsd;
        }

        if (marketConfig.virtualMarketId == ZERO_FIELD) {
            // has no virtual inventory
            return priceImpactUsd;
        }

        let poolParamsForVirtualInventory: PoolParams = getNextPoolAmountsParams(
            priceForTokenA,
            priceForTokenB,
            usdDeltaForTokenA,
            usdDeltaForTokenB,
            virtualMarketData.virtualInventoryForSwaps.long,
            virtualMarketData.virtualInventoryForSwaps.short,
        );

        let priceImpactUsdForVirtualInventory: i128 = getPriceImpactUsd_(
            marketConfig,
            poolParamsForVirtualInventory.poolUsdForTokenA,
            poolParamsForVirtualInventory.poolUsdForTokenB,
            poolParamsForVirtualInventory.nextPoolUsdForTokenA,
            poolParamsForVirtualInventory.nextPoolUsdForTokenB,
        );

        return priceImpactUsdForVirtualInventory < priceImpactUsd ?
            priceImpactUsdForVirtualInventory :
            priceImpactUsd;
    }

    inline getPriceImpactUsd_(
        marketConfig: MarketConfig,
        poolUsdForTokenA: u128,
        poolUsdForTokenB: u128,
        nextPoolUsdForTokenA: u128,
        nextPoolUsdForTokenB: u128,
    ) -> i128 {
        let initialDiffUsd: u128 = diff(poolUsdForTokenA, poolUsdForTokenB);
        let nextDiffUsd: u128 = diff(nextPoolUsdForTokenA, nextPoolUsdForTokenB);

        let isSameSideRebalance: bool = (poolUsdForTokenA <= poolUsdForTokenB) == (nextPoolUsdForTokenA <= nextPoolUsdForTokenB);

        let (positiveImpactFactor, negativeImpactFactor): (u128, u128) = getAdjustedSwapImpactFactors(marketConfig);
        if (isSameSideRebalance) {
            let hasPositiveImpact: bool = nextDiffUsd < initialDiffUsd;
            let impactFactor: u128 = hasPositiveImpact ? positiveImpactFactor : negativeImpactFactor;

            return getPriceImpactUsdForSameSideRebalance(
                initialDiffUsd,
                nextDiffUsd,
                impactFactor,
                marketConfig.swapImpactExponentFactor,
            );
        } else {
            return getPriceImpactUsdForCrossoverRebalance(
                initialDiffUsd,
                nextDiffUsd,
                positiveImpactFactor,
                negativeImpactFactor,
                marketConfig.swapImpactExponentFactor,
            );
        }
    }

    inline getAdjustedSwapImpactFactors(
        marketConfig: MarketConfig,
    ) -> (u128, u128) {
        let positiveImpactFactor: u128 = marketConfig.swapImpactFactor.is;
        let negativeImpactFactor: u128 = marketConfig.swapImpactFactor.not;

        // If the positive impact factor is more than the negative impact factor, positions could be opened
        // and closed immediately for a profit if the difference is sufficient to cover the position fees.
        if (positiveImpactFactor > negativeImpactFactor) {
            positiveImpactFactor = negativeImpactFactor;
        }

        return (positiveImpactFactor, negativeImpactFactor);
    }

    struct PoolParams {
        poolUsdForTokenA: u128,
        poolUsdForTokenB: u128,
        nextPoolUsdForTokenA: u128,
        nextPoolUsdForTokenB: u128,
    }

    inline getNextPoolAmountsParams(
        priceForTokenA: u128,
        priceForTokenB: u128,
        usdDeltaForTokenA: i128,
        usdDeltaForTokenB: i128,
        poolAmountForTokenA: u128,
        poolAmountForTokenB: u128,
    ) -> PoolParams {
        let poolUsdForTokenA: u128 = poolAmountForTokenA * priceForTokenA;
        let poolUsdForTokenB: u128 = poolAmountForTokenB * priceForTokenB;

        let nextPoolUsdForTokenA: u128 = sumReturnU128(poolUsdForTokenA, usdDeltaForTokenA);
        let nextPoolUsdForTokenB: u128 = sumReturnU128(poolUsdForTokenB, usdDeltaForTokenB);

        return PoolParams {
            poolUsdForTokenA,
            poolUsdForTokenB,
            nextPoolUsdForTokenA,
            nextPoolUsdForTokenB,
        };
    }

    const SwapPricingTwoStep: u8 = 0u8;
    const SwapPricingShift: u8 = 1u8;
    const SwapPricingAtomic: u8 = 2u8;

    struct SwapFees {
        feeReceiverAmount: u128,
        feeAmountForPool: u128,
        amountAfterFees: u128,
    }

    transition getSwapFees(
        public generalConfig: GeneralConfig,
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public amount: u128,
        public forPositiveImpact: bool,
        public swapPricingType: u8,
    ) -> SwapFees {
        let feeFactor: u128 = 0u128;

        if (swapPricingType == SwapPricingTwoStep) {
            feeFactor = forPositiveImpact ? marketConfig.swapFeeFactor.long : marketConfig.swapFeeFactor.short;
        } else if (swapPricingType == SwapPricingShift) {
            // 0
        } else if (swapPricingType == SwapPricingAtomic) {
            feeFactor = marketConfig.atomicSwapFeeFactor;
        }

        let feeAmount: u128 = amount * feeFactor / FACTOR_PRECISION_U;

        let feeReceiverAmount: u128 = feeAmount * generalConfig.swapFeeReceiverFactor / FACTOR_PRECISION_U;
        let feeAmountForPool: u128 = feeAmount - feeReceiverAmount;

        let amountAfterFees: u128 = amount - feeAmount;

        return SwapFees {
            feeReceiverAmount,
            feeAmountForPool,
            amountAfterFees,
        };
    }

    inline getPriceImpactUsdForSameSideRebalance(
        initialDiffUsd: u128,
        nextDiffUsd: u128,
        impactFactor: u128,
        impactExponentFactor: u32,
    ) -> i128 {
        let hasPositiveImpact: bool = nextDiffUsd < initialDiffUsd;

        let deltaDiffUsd: i128 = diff(
            applyImpactFactor(initialDiffUsd, impactFactor, impactExponentFactor),
            applyImpactFactor(nextDiffUsd, impactFactor, impactExponentFactor)
        ) as i128;

        return hasPositiveImpact ? deltaDiffUsd : -deltaDiffUsd;
    }

    inline getPriceImpactUsdForCrossoverRebalance(
        initialDiffUsd: u128,
        nextDiffUsd: u128,
        positiveImpactFactor: u128,
        negativeImpactFactor: u128,
        impactExponentFactor: u32,
    ) -> i128 {
        let positiveImpactUsd: u128 = applyImpactFactor(initialDiffUsd, positiveImpactFactor, impactExponentFactor);
        let negativeImpactUsd: u128 = applyImpactFactor(nextDiffUsd, negativeImpactFactor, impactExponentFactor);
        let deltaDiffUsd: i128 = diff(positiveImpactUsd, negativeImpactUsd) as i128;

        return positiveImpactUsd > negativeImpactUsd ? deltaDiffUsd : -deltaDiffUsd;
    }

    inline applyImpactFactor(
        diffUsd: u128,
        impactFactor: u128,
        impactExponentFactor: u32,
    ) -> u128 {
        let exponentValue: u128 = (diffUsd / USD_DIVISOR_U).pow(impactExponentFactor) * USD_DIVISOR_U;
        return exponentValue * impactFactor / FACTOR_PRECISION_U;
    }

    inline sumReturnU128(a: u128, b: i128) -> u128 {
        let babs: u128 = b.abs() as u128;
        return b > 0i128 ? a.add_wrapped(babs) : a.sub_wrapped(babs);
    }

    inline diff(a: u128, b: u128) -> u128 {
        return a > b ? a.sub_wrapped(b) : b.sub_wrapped(a);
    }
}
