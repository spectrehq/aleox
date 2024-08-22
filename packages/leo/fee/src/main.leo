import aleox_store_v1.aleo;

program aleox_fee_v1.aleo {
    transition incrementClaimableFeeAmount(
        public marketData: MarketData,
        public isLong: bool,
        public delta: u128,
    ) -> MarketData {
        return MarketData {
            positionImpactPoolAmount: marketData.positionImpactPoolAmount,
            positionImpactPoolDistAtBlock: marketData.positionImpactPoolDistAtBlock,
            savedFundingFactorPerSecond: marketData.savedFundingFactorPerSecond,
            fundingUpdatedAtBlock: marketData.fundingUpdatedAtBlock,
            openInterest: marketData.openInterest,
            openInterestInTokens: marketData.openInterestInTokens,
            collateralSum: marketData.collateralSum,
            fundingFeeAmountPerSize: marketData.fundingFeeAmountPerSize,
            claimableFundingAmountPerSize: marketData.claimableFundingAmountPerSize,
            cumulativeBorrowingFactor: marketData.cumulativeBorrowingFactor,
            cumulativeBFUpdatedAtBlock: marketData.cumulativeBFUpdatedAtBlock,
            totalBorrowing: marketData.totalBorrowing,
            poolAmount: marketData.poolAmount,
            claimableFeeAmount: CollateralData {
                long: isLong ? marketData.claimableFeeAmount.long + delta : marketData.claimableFeeAmount.long,
                short: isLong ? marketData.claimableFeeAmount.short : marketData.claimableFeeAmount.short + delta,
            },
        };
    }
}
