program aleox_store_v1.aleo {
    const ZERO_FIELD: field = 0field;

    struct GeneralConfig {
        feeReceiver: address,
        holdingAddress: address,
        maxAutoCancelOrders: u32,
        requestExpirationBlocks: u32,
        minCollateralUsd: u128,
        minPositionSizeUsd: u128,
        maxFundingFactorPerSecondLimit: u128,
        skipBorrowingFeeForSmallerSide: bool,
        positionFeeReceiverFactor: u128,
        swapFeeReceiverFactor: u128,
        borrowingFeeReceiverFactor: u128,
    }

    // 0u8 => GeneralConfig
    mapping generalConfig: u8 => GeneralConfig;

    struct MarketConfig {
        isMarketDisabled: bool,
        minMarketTokensForFirstDeposit: u128,
        minCollateralFactor: u128,
        positionImpactExponentFactor: u32, // integer, no precision
        maxPositionImpactFactorForLiq: u128, // maxPositionImpactFactorForLiquidations
        swapImpactFactor: IsPositiveData,
        swapImpactExponentFactor: u32,
        atomicSwapFeeFactor: u128,
        minPositionImpactPoolAmount: u128,
        positionImpactPoolDistRate: u128, // positionImpactPoolDistributionRate

        fundingFactor: u128,
        fundingExponentFactor: u32, // integer, no precision
        fundingIncreaseFactorPerSecond: u128,
        fundingDecreaseFactorPerSecond: u128,
        minFundingFactorPerSecond: u128,
        maxFundingFactorPerSecond: u128,
        thresholdForStableFunding: u128,
        thresholdForDecreaseFunding: u128,

        optimalUsageFactor: PositionData,
        borrowingFactor: PositionData,
        borrowingExponentFactor: ExponentFactorData,  // integer, no precision

        maxPnlFactorForTraders: PositionData,
        maxPnlFactorForAdl: PositionData,
        minPnlFactorAfterAdl: PositionData,
        maxPnlFactorForDeposits: PositionData,
        maxPnlFactorForWithdrawals: PositionData,

        swapFeeFactor: PositionData,

        virtualMarketId: field, // 0field means empty
        virtualTokenIdForIndexToken: field, // 0field means empty

        maxPoolAmount: CollateralData,
        maxPoolUsdForDeposit: CollateralData,

        reserveFactor: PositionData,
    }

    // market => MarketConfig
    mapping marketConfig: field => MarketConfig;

    struct MarketTokenKey {
        market: field,
        token: field,
    }

    struct MarketTokenConfig {
        isDisabled: bool,
        claimableFeeAmount: u128,
        poolAmount: u128,
        maxPoolAmount: u128,
        maxPoolUsdForDeposit: u128,
        swapImpactPoolAmount: u128,
        claimableFundingAmount: u128,
        claimableCollateralAmount: u128,
        claimableCollateralFactor: u128,
        affiliateReward: u128,
    }

    // hash(MarketTokenKey) => MarketTokenConfig
    mapping marketTokenConfig: field => MarketTokenConfig;

    struct MarketTokenAccountKey {
        market: field,
        token: field,
        account: address,
    }

    struct MarketTokenAccountConfig {
        claimableFundingAmount: u128,
        claimableCollateralAmount: u128,
        claimableCollateralFactor: u128,
        claimedCollateralAmount: u128,
        affiliateReward: u128,
    }

    // hash(MarketTokenAccountKey) => MarketTokenAccountConfig
    mapping marketTokenAccountConfig: field => MarketTokenAccountConfig;

    struct MarketIsLongKey {
        market: field,
        isLong: bool,
    }

    struct MarketIsLongConfig {
        minCollateralFactorForOIM: u128, // minCollateralFactorForOpenInterestMultiplier
        maxOpenInterest: u128,
        reserveFactor: u128,
        openInterestReserveFactor: u128,
        optimalUsageFactor: u128,
        baseBorrowingFactor: u128,
        aboveOUBFactor: u128, // aboveOptimalUsageBorrowingFactor
        borrowingFactor: u128,
        borrowingExponentFactor: u128,
        cumulativeBorrowingFactor: u128,
        cumulativeBFUpdatedAtBlock: u32, // cumulativeBorrowingFactorUpdatedAtBlock
        totalBorrowing: u128,
    }

    // hash(MarketIsLongKey) => MarketIsLongConfig
    mapping marketIsLongConfig: field => MarketIsLongConfig;

    struct MarketIsPositiveKey {
        market: field,
        isPositive: bool,
    }

    struct MarketIsPositiveConfig {
        positionImpactFactor: u128,
        maxPositionImpactFactor: u128,
        positionFeeFactor: u128,
        swapImpactFactor: u128,
        swapFeeFactor: u128,
    }

    // hash(MarketIsPositiveKey) => MarketIsPositiveConfig
    mapping marketIsPositiveConfig: field => MarketIsPositiveConfig;

    struct MarketCollateralTokenIsLongKey {
        market: field,
        collateralToken: field,
        isLong: bool,
    }

    struct MarketCTILConfig { // MarketCollateralTokenIsLongConfig
        openInterest: u128,
        openInterestInTokens: u128,
        collateralSum: u128,
        fundingFeeAmountPerSize: u128,
        claimableFundingAmountPerSize: u128,
    }

    // hash(MarketCollateralTokenIsLongKey) => MarketCTILConfig
    mapping marketCTILConfig: field => MarketCTILConfig;

    struct ModuleConfig {
        createDepositDisabled: bool,
        cancelDepositDisabled: bool,
        executeDepositDisabled: bool,
        createWithdrawalDisabled: bool,
        cancelWithdrawalDisabled: bool,
        executeWithdrawalDisabled: bool,
        executeAtomicWithdrawalDisabled: bool,
        createGlvDepositDisabled: bool,
        cancelGlvDepositDisabled: bool,
        executeGlvDepositDisabled: bool,
        glvShiftDisabled: bool,
        createShiftDisabled: bool,
        cancelShiftDisabled: bool,
        executeShiftDisabled: bool,
        claimFundingFeesDisabled: bool,
        claimCollateralDisabled: bool,
        claimAffiliateRewardsDisabled: bool,
        subAccountDisabled: bool,
    }

    // module => ModuleConfig
    mapping moduleConfig: address => ModuleConfig;

    struct MarketData {
        positionImpactPoolAmount: u128,
        positionImpactPoolDistAtBlock: u32, // positionImpactPoolDistributedAtBlock
        swapImpactPoolAmount: CollateralData,
        savedFundingFactorPerSecond: i128,
        fundingUpdatedAtBlock: u32,
        openInterest: CollateralPositionData,
        openInterestInTokens: CollateralPositionData,
        collateralSum: CollateralPositionData,
        fundingFeeAmountPerSize: CollateralPositionData,
        claimableFundingAmountPerSize: CollateralPositionData,
        cumulativeBorrowingFactor: PositionData,
        cumulativeBFUpdatedAtBlock: PositionAtBlock, // cumulativeBorrowingFactorUpdatedAtBlock
        totalBorrowing: PositionData,
        poolAmount: CollateralData,
        claimableCollateralAmount: CollateralData,
        claimableFeeAmount: CollateralData,
        affiliateRewardAmount: CollateralData,
    }

    struct CollateralPositionData {
        longTokenIsLong: u128,
        shortTokenIsLong: u128,
        longTokenIsShort: u128,
        shortTokenIsShort: u128,
    }

    struct CollateralData {
        long: u128,
        short: u128,
    }

    struct PositionData {
        long: u128,
        short: u128,
    }

    struct PositionAtBlock {
        long: u32,
        short: u32,
    }

    struct IsPositiveData {
        is: u128,
        not: u128,
    }

    struct ExponentFactorData {
        long: u32,
        short: u32,
    }

    // market => MarketData
    mapping marketData: field => MarketData;

    struct VirtualMarketData {
        virtualInventoryForSwaps: CollateralData,
        virtualInventoryForPositions: i128,
    }

    // virtual market => VirtualMarketData
    mapping virtualMarketData: field => VirtualMarketData;

    async transition setGeneralConfig(public cfg: GeneralConfig) -> Future {
        return finalizeSetGeneralConfig(cfg);
    }

    async function finalizeSetGeneralConfig(cfg: GeneralConfig) {
        generalConfig.set(0u8, cfg);
    }

    async transition setMarketData(public market: field, public data: MarketData) -> Future {
        return finalizeSetMarketData(market, data);
    }

    async function finalizeSetMarketData(market: field, data: MarketData) {
        marketData.set(market, data);
    }

    async transition setVirtualMarketData(public virtualMarket: field, public data: VirtualMarketData) -> Future {
        return finalizeSetVirtualMarketData(virtualMarket, data);
    }

    async function finalizeSetVirtualMarketData(virtualMarket: field, data: VirtualMarketData) {
        if (virtualMarket != ZERO_FIELD) {
            virtualMarketData.set(virtualMarket, data);
        }
    }
}
