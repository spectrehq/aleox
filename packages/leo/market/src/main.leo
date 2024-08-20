import multi_token_support_program.aleo;
import aleox_store_v1.aleo;
import aleox_oracle_v1.aleo;

program aleox_market_v1.aleo {
    struct Market {
        marketToken: field,
        indexToken: field,
        longToken: field,
        shortToken: field,
    }

    mapping markets: field => Market; // market token => market

    mapping marketList: u32 => field; // index => market token

    mapping marketCount: u8 => u32; // 0u8 => market count

    async transition createMarket(
        public indexToken: field,
        public longToken: field,
        public shortToken: field,
        public salt: field,
    ) -> Future {
        // Here we use `salt` as the market token just for hash computation.
        // It ensures markets with the same indexToken, longToken and shortToken can be created if needed.
        // Generally `salt` should be set to `0field`.
        let marketToken: field = BHP256::hash_to_field(Market {
            marketToken: salt,
            indexToken,
            longToken,
            shortToken,
        });

        let market: Market = Market {
            marketToken,
            indexToken,
            longToken,
            shortToken,
        };

        // Register market token in mtsp program.
        // Admin is this program.
        let f: Future = multi_token_support_program.aleo/register_token(
            marketToken, // token_id
            0u128, // name, TODO
            0u128, // symbol, TODO
            6u8, // decimals
            340282366920938463463374607431768211455u128, // max_supply, never reach
            false, // external_authorization_required
            self.address, // external_authorization_party
        );

        return finalizeCreateMarket(f, market);
    }

    async function finalizeCreateMarket(f: Future, market: Market) {
        f.await();

        assert(multi_token_support_program.aleo/registered_tokens.contains(market.indexToken));
        assert(multi_token_support_program.aleo/registered_tokens.contains(market.longToken));
        assert(multi_token_support_program.aleo/registered_tokens.contains(market.shortToken));

        assert(!markets.contains(market.marketToken));

        markets.set(market.marketToken, market);

        let count: u32 = marketCount.get_or_use(0u8, 0u32);
        marketCount.set(0u8, count + 1u32);
        marketList.set(count, market.marketToken);
    }

    async transition distributePositionImpactPool(
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public atBlock: u32,
    ) -> (MarketData, Future) {
        let (distributionAmount, nextPositionImpactPoolAmount): (u128, u128) = getPendingPositionImpactPoolDistributionAmount(
            marketConfig,
            marketData,
            atBlock,
        );

        marketData = MarketData {
            positionImpactPoolAmount: marketData.positionImpactPoolAmount - distributionAmount,
            positionImpactPoolDistAtBlock: atBlock,
            savedFundingFactorPerSecond: marketData.savedFundingFactorPerSecond,
            fundingUpdatedAtBlock: marketData.fundingUpdatedAtBlock,
            openInterest: marketData.openInterest,
            openInterestInTokens: marketData.openInterestInTokens,
            collateralSum: marketData.collateralSum,
            fundingFeeAmountPerSize: marketData.fundingFeeAmountPerSize,
            claimableFundingAmountPerSize: marketData.claimableFundingAmountPerSize,
        };

        return (marketData, finalizeDistributePositionImpactPool(atBlock));
    }

    async function finalizeDistributePositionImpactPool(
        atBlock: u32,
    ) {
        assert(block.height - atBlock < 100u32); // TODO
    }

    inline getPendingPositionImpactPoolDistributionAmount(
        marketConfig: MarketConfig,
        marketData: MarketData,
        atBlock: u32,
    ) -> (u128, u128) {
        let positionImpactPoolAmount: u128 = marketData.positionImpactPoolAmount;
        if (positionImpactPoolAmount == 0u128) {
            return (0u128, 0u128);
        }

        let distributionRate: u128 = marketConfig.positionImpactPoolDistRate;
        if (distributionRate == 0u128) {
            return (0u128, positionImpactPoolAmount);
        }

        let minPositionImpactPoolAmount: u128 = marketConfig.minPositionImpactPoolAmount;
        if (positionImpactPoolAmount <= minPositionImpactPoolAmount) {
            return (0u128, positionImpactPoolAmount);
        }

        let maxDistributionAmount: u128 = positionImpactPoolAmount - minPositionImpactPoolAmount;

        let durationInBlocks: u32 = getBlocksSincePositionImpactPoolDistributed(marketData, atBlock);
        let distributionAmount: u128 = durationInBlocks as u128 * distributionRate;

        if (distributionAmount > maxDistributionAmount) {
            distributionAmount = maxDistributionAmount;
        }

        return (distributionAmount, positionImpactPoolAmount - distributionAmount);
    }

    inline getBlocksSincePositionImpactPoolDistributed(
        marketData: MarketData,
        atBlock: u32,
    ) -> u32 {
        let distributedAt: u32 = marketData.positionImpactPoolDistAtBlock;
        if (distributedAt == 0u32) {
            return 0u32;
        }
        return atBlock - distributedAt;
    }

    async transition updateFundingState(
        public marketData: MarketData,
        public prices: Prices,
    ) -> Future {
        return finalizeUpdateFundingState();
    }

    async function finalizeUpdateFundingState() {
        let i: u8 = 0u8;
        assert(i == 0u8);
    }

    struct GetNextFundingAmountPerSize {
        longsPayShorts: bool,
        fundingFactorPerSecond: u128,
        nextSavedFundingFactorPerSecond: i128,
        fundingFeePerSizeDelta: CollateralPositionData,
        claimableFundingPerSizeDelta: CollateralPositionData,
    }

    inline getNextFundingAmountPerSize(
        market: Market,
        marketData: MarketData,
        atBlock: u32,
    ) -> GetNextFundingAmountPerSize {
        let divisor: u128 = getPoolDivisor(market.longToken, market.shortToken);

        let longOpenInterest: u128 = marketData.openInterest.longTokenIsLong + marketData.openInterest.shortTokenIsLong;
        let shortOpenInterest: u128 = marketData.openInterest.longTokenIsShort + marketData.openInterest.shortTokenIsShort;

        // If either long or short open interest is zero, then funding should not be updated
        // as there would not be any user to pay the funding to.
        if (longOpenInterest == 0u128 || shortOpenInterest == 0u128) {
            let zeroCollateralPositionData: CollateralPositionData = CollateralPositionData {
                longTokenIsLong: 0u128,
                longTokenIsShort: 0u128,
                shortTokenIsLong: 0u128,
                shortTokenIsShort: 0u128,
            };
            return GetNextFundingAmountPerSize {
                longsPayShorts: false,
                fundingFactorPerSecond: 0u128,
                nextSavedFundingFactorPerSecond: 0i128,
                fundingFeePerSizeDelta: zeroCollateralPositionData,
                claimableFundingPerSizeDelta: zeroCollateralPositionData,
            };
        }

        // If the blockchain is not progressing / a market is disabled, funding fees
        // will continue to accumulate.
        // This should be a rare occurrence so funding fees are not adjusted for this case.
        let durationInBlocks: u32 = getBlocksSinceFundingUpdated(marketData, atBlock);

        let sizeOfLargerSide: u128 = longOpenInterest > shortOpenInterest ? longOpenInterest : shortOpenInterest;

        let zeroCollateralPositionData: CollateralPositionData = CollateralPositionData {
            longTokenIsLong: 0u128,
            longTokenIsShort: 0u128,
            shortTokenIsLong: 0u128,
            shortTokenIsShort: 0u128,
        };
        return GetNextFundingAmountPerSize {
            longsPayShorts: false,
            fundingFactorPerSecond: 0u128,
            nextSavedFundingFactorPerSecond: 0i128,
            fundingFeePerSizeDelta: zeroCollateralPositionData,
            claimableFundingPerSizeDelta: zeroCollateralPositionData,
        };
    }

    inline getNextFundingFactorPerSecond(
        marketConfig: MarketConfig,
        longOpenInterest: u128,
        shortOpenInterest: u128,
        durationInBlocks: u32,
    ) -> (u128, bool, i128) {
        let diffUsd: u128 = longOpenInterest > shortOpenInterest ? longOpenInterest.sub_wrapped(shortOpenInterest) : shortOpenInterest.sub_wrapped(longOpenInterest);
        let totalOpenInterest: u128 = longOpenInterest + shortOpenInterest;

        if (diffUsd == 0u128) {
            return (0u128, true, 0i128);
        }

        assert(totalOpenInterest > 0u128);

        let fundingExponentFactor: u128 = marketConfig.fundingExponentFactor;

        let diffUsdAfterExponent: u128 = diffUsd.pow(fundingExponentFactor as u32);

        return (0u128, true, 0i128);
    }

    inline getBlocksSinceFundingUpdated(
        marketData: MarketData,
        atBlock: u32,
    ) -> u32 {
        let updatedAt: u32 = marketData.fundingUpdatedAtBlock;
        if (updatedAt == 0u32) {
            return 0u32;
        }
        return atBlock - updatedAt;
    }

    inline getPoolDivisor(longToken: field, shortToken: field) -> u128 {
        return longToken == shortToken ? 2u128 : 1u128;
    }

    inline getOpenInterest(
        marketData: MarketData,
        divisor: u128,
    ) {
    }
}
