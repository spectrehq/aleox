import aleox_store_v1.aleo;
import aleox_market_v1.aleo;
import aleox_oracle_v1.aleo;

program aleox_pricing_v1.aleo {
    const PRECISION_U: u128 = 10_000_000_000_000_000_000_000u128; // 10^22
    const PRECISION_I: i128 = 10_000_000_000_000_000_000_000i128; // 10^22
    const FACTOR_PRECISION_U: u128 = 10_000u128; // 10^4
    const FACTOR_PRECISION_I: i128 = 10_000i128; // 10^4

    transition getPriceImpactUsd(
        public market: Market,
        public prices: Prices,
        public usdDeltaForTokenA: i128,
        public usdDeltaForTokenB: i128,
        public includeVirtualInventoryImpact: bool,
    ) -> i128 {
        return 0i128;
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
}
