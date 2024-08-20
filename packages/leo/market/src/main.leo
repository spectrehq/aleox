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
        marketConfig: MarketConfig,
        marketData: MarketData,
        prices: Prices,
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
        let durationInBlocks: u128 = getBlocksSinceFundingUpdated(marketData, atBlock) as u128;

        let sizeOfLargerSide: u128 = longOpenInterest > shortOpenInterest ? longOpenInterest : shortOpenInterest;

        let (fundingFactorPerSecond, longsPayShorts, nextSavedFundingFactorPerSecond): (u128, bool, i128) = getNextFundingFactorPerSecond(
            marketConfig,
            marketData,
            longOpenInterest,
            shortOpenInterest,
            durationInBlocks,
        );

        let fundingUsd: u128 = sizeOfLargerSide * durationInBlocks * fundingFactorPerSecond / divisor;

        let fundingUsdForLongCollateral: u128 = longsPayShorts ?
            fundingUsd * marketData.openInterest.longTokenIsLong / longOpenInterest :
            fundingUsd * marketData.openInterest.longTokenIsShort / shortOpenInterest;
        let fundingUsdForShortCollateral: u128 = longsPayShorts ?
            fundingUsd * marketData.openInterest.shortTokenIsLong / longOpenInterest :
            fundingUsd * marketData.openInterest.shortTokenIsShort / shortOpenInterest;

        return GetNextFundingAmountPerSize {
            longsPayShorts,
            fundingFactorPerSecond,
            nextSavedFundingFactorPerSecond,
            fundingFeePerSizeDelta: CollateralPositionData {
                longTokenIsLong: longsPayShorts ? getFundingAmountPerSizeDelta(
                    fundingUsdForLongCollateral,
                    marketData.openInterest.longTokenIsLong,
                    prices.longToken.max,
                    true, // roundUpMagnitude
                ) : 0u128,
                longTokenIsShort: longsPayShorts ? 0u128 : getFundingAmountPerSizeDelta(
                    fundingUsdForLongCollateral,
                    marketData.openInterest.longTokenIsShort,
                    prices.longToken.max,
                    true, // roundUpMagnitude
                ),
                shortTokenIsLong: longsPayShorts ? getFundingAmountPerSizeDelta(
                    fundingUsdForShortCollateral,
                    marketData.openInterest.shortTokenIsLong,
                    prices.shortToken.max,
                    true, // roundUpMagnitude
                ) : 0u128,
                shortTokenIsShort: longsPayShorts ? 0u128 : getFundingAmountPerSizeDelta(
                    fundingUsdForShortCollateral,
                    marketData.openInterest.shortTokenIsShort,
                    prices.shortToken.max,
                    true, // roundUpMagnitude
                ),
            },
            claimableFundingPerSizeDelta: CollateralPositionData {
                longTokenIsLong: longsPayShorts ? 0u128 : getFundingAmountPerSizeDelta(
                    fundingUsdForLongCollateral,
                    longOpenInterest,
                    prices.longToken.max,
                    false, // roundUpMagnitude
                ),
                longTokenIsShort: longsPayShorts ?  getFundingAmountPerSizeDelta(
                    fundingUsdForLongCollateral,
                    shortOpenInterest,
                    prices.longToken.max,
                    false, // roundUpMagnitude
                ): 0u128,
                shortTokenIsLong: longsPayShorts ? 0u128 : getFundingAmountPerSizeDelta(
                    fundingUsdForShortCollateral,
                    longOpenInterest,
                    prices.shortToken.max,
                    false, // roundUpMagnitude
                ),
                shortTokenIsShort: longsPayShorts ? getFundingAmountPerSizeDelta(
                    fundingUsdForShortCollateral,
                    shortOpenInterest,
                    prices.shortToken.max,
                    false, // roundUpMagnitude
                ) : 0u128,
            },
        };
    }

    const FundingRateNoChange: u8 = 0u8;
    const FundingRateIncrease: u8 = 1u8;
    const FundingRateDecrease: u8 = 2u8;

    inline getNextFundingFactorPerSecond(
        marketConfig: MarketConfig,
        marketData: MarketData,
        longOpenInterest: u128,
        shortOpenInterest: u128,
        durationInBlocks: u128,
    ) -> (u128, bool, i128) {
        let diffUsd: u128 = longOpenInterest > shortOpenInterest ? longOpenInterest.sub_wrapped(shortOpenInterest) : shortOpenInterest.sub_wrapped(longOpenInterest);
        let totalOpenInterest: u128 = longOpenInterest + shortOpenInterest;

        if (diffUsd == 0u128) {
            return (0u128, true, 0i128);
        }

        assert(totalOpenInterest > 0u128);

        let fundingExponentFactor: u128 = marketConfig.fundingExponentFactor;

        let diffUsdAfterExponent: u128 = diffUsd.pow(fundingExponentFactor as u32);
        let diffUsdToOpenInterestFactor: u128 = diffUsdAfterExponent / totalOpenInterest;

        if (marketConfig.fundingIncreaseFactorPerSecond == 0u128) {
            // If there is no fundingIncreaseFactorPerSecond then return the static fundingFactor based on open interest difference.
            let fundingFactorPerSecond: u128 = diffUsdToOpenInterestFactor * marketConfig.fundingFactor;

            if (fundingFactorPerSecond > marketConfig.maxFundingFactorPerSecond) {
                fundingFactorPerSecond = marketConfig.maxFundingFactorPerSecond;
            }

            return (
                fundingFactorPerSecond,
                longOpenInterest > shortOpenInterest,
                0i128,
            );
        }

        // If the savedFundingFactorPerSecond is positive then longs pay shorts.
        // If the savedFundingFactorPerSecond is negative then shorts pay longs.
        let savedFundingFactorPerSecondMagnitude: i128 = marketData.savedFundingFactorPerSecond.abs();

        // Set the default of nextSavedFundingFactorPerSecond as the savedFundingFactorPerSecond.
        let nextSavedFundingFactorPerSecond: i128 = marketData.savedFundingFactorPerSecond;

        let fundingRateChangeType: u8 = FundingRateNoChange;

        let isSkewTheSameDirectionAsFunding: bool = (marketData.savedFundingFactorPerSecond > 0i128 &&
            longOpenInterest > shortOpenInterest) || (marketData.savedFundingFactorPerSecond < 0i128 &&
            shortOpenInterest > longOpenInterest);

        if (isSkewTheSameDirectionAsFunding) {
            if (diffUsdToOpenInterestFactor > marketConfig.thresholdForStableFunding) {
                fundingRateChangeType = FundingRateIncrease;
            } else if (diffUsdToOpenInterestFactor < marketConfig.thresholdForDecreaseFunding) {
                fundingRateChangeType = FundingRateDecrease;
            }
        } else {
            // If the skew has changed, then the funding should increase in the opposite direction.
            fundingRateChangeType = FundingRateIncrease;
        }

        if (fundingRateChangeType == FundingRateIncrease) {
            let increaseValue: i128 = (diffUsdToOpenInterestFactor * marketConfig.fundingIncreaseFactorPerSecond * durationInBlocks) as i128;

            // If there are more longs than shorts, then the savedFundingFactorPerSecond should increase.
            if (longOpenInterest < shortOpenInterest) {
                increaseValue = -increaseValue;
            }

            nextSavedFundingFactorPerSecond = marketData.savedFundingFactorPerSecond + increaseValue;
        }

        if (fundingRateChangeType == FundingRateDecrease && savedFundingFactorPerSecondMagnitude != 0i128) {
            let decreaseValue: i128 = (marketConfig.fundingDecreaseFactorPerSecond * durationInBlocks) as i128;

            let sign: i128 = marketData.savedFundingFactorPerSecond >= 0i128 ? 1i128 : -1i128;
            if (savedFundingFactorPerSecondMagnitude <= decreaseValue) {
                // Set the funding factor to 1 or -1 depending on the original savedFundingFactorPerSecond.
                nextSavedFundingFactorPerSecond = sign;
            } else {
                // Reduce the original savedFundingFactorPerSecond while keeping the original sign of the savedFundingFactorPerSecond.
                nextSavedFundingFactorPerSecond = (savedFundingFactorPerSecondMagnitude - decreaseValue) * sign;
            }
        }

        nextSavedFundingFactorPerSecond = boundMagnitude(nextSavedFundingFactorPerSecond, 0u128, marketConfig.maxFundingFactorPerSecond);

        let nextSavedFundingFactorPerSecondWithMinBound: i128 = boundMagnitude(
            nextSavedFundingFactorPerSecond,
            marketConfig.minFundingFactorPerSecond,
            marketConfig.maxFundingFactorPerSecond,
        );

        return (
            nextSavedFundingFactorPerSecondWithMinBound.abs() as u128,
            nextSavedFundingFactorPerSecondWithMinBound > 0i128,
            nextSavedFundingFactorPerSecond
        );
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

    inline getFundingAmountPerSizeDelta(
        fundingUsd: u128,
        openInterest: u128,
        tokenPrice: u128,
        roundUpMagnitude: bool,
    ) -> u128 {
        if (fundingUsd == 0u128 || openInterest == 0u128) {
            return 0u128;
        }
        let fundingUsdPerSize: u128 = fundingUsd / openInterest;
        if (roundUpMagnitude) {
            return (fundingUsdPerSize + tokenPrice - 1u128) / tokenPrice;
        } else {
            return fundingUsdPerSize / tokenPrice;
        }
    }

    inline boundMagnitude(value: i128, min: u128, max: u128) -> i128 {
        let magnitude: u128 = value.abs() as u128;
        if (magnitude < min) {
            magnitude = min;
        }
        if (magnitude > max) {
            magnitude = max;
        }
        return value >= 0i128 ? magnitude as i128 : -(magnitude as i128);
    }

    inline getOpenInterest(
        marketData: MarketData,
        divisor: u128,
    ) {
    }
}
