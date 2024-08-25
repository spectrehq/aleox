import multi_token_support_program.aleo;
import aleox_store_v1.aleo;
import aleox_oracle_v1.aleo;

program aleox_market_v1.aleo {
    const PRECISION_U: u128 = 10_000_000_000_000_000_000_000u128; // 10^22
    const PRECISION_I: i128 = 10_000_000_000_000_000_000_000i128; // 10^22
    const MARKET_TOKEN_PRECISION_U: u128 = 1_000_000u128; // 10^6
    const MARKET_TOKEN_PRECISION_I: i128 = 1_000_000i128; // 10^6
    const USD_DIVISOR_U: u128 = 10_000_000_000_000_000u128; // 10^16; 16 = 22 - 6
    const USD_DIVISOR_I: i128 = 10_000_000_000_000_000i128; // 10^16; 16 = 22 - 6
    const FACTOR_PRECISION_U: u128 = 10_000u128; // 10^4
    const FACTOR_PRECISION_I: i128 = 10_000i128; // 10^4

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

    async transition mintMarketTokens(
        public marketToken: field,
        public receiver: address,
        public amount: u128,
    ) -> Future {
        let f: Future = multi_token_support_program.aleo/mint_public(marketToken, receiver, amount, 4294967295u32);

        return finalizeMintMarketTokens(f);
    }

    async function finalizeMintMarketTokens(f: Future) {
        f.await();
    }

    async transition burnMarketTokens(
        public marketToken: field,
        public owner: address,
        public amount: u128,
    ) -> Future {
        let f: Future = multi_token_support_program.aleo/burn_public(marketToken, owner, amount);

        return finalizeBurnMarketTokens(f);
    }

    async function finalizeBurnMarketTokens(f: Future) {
        f.await();
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
            swapImpactPoolAmount: marketData.swapImpactPoolAmount,
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
            claimableCollateralAmount: marketData.claimableCollateralAmount,
            claimableFeeAmount: marketData.claimableFeeAmount,
            affiliateRewardAmount: marketData.affiliateRewardAmount,
        };

        return (marketData, finalizeDistributePositionImpactPool(atBlock));
    }

    async function finalizeDistributePositionImpactPool(
        atBlock: u32,
    ) {
        assert(block.height - atBlock < 100u32); // TODO
    }

    inline getNextPositionImpactPoolAmount(
        marketConfig: MarketConfig,
        marketData: MarketData,
        atBlock: u32,
    ) -> u128 {
        return getPendingPositionImpactPoolDistributionAmount(
            marketConfig,
            marketData,
            atBlock,
        ).1;
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

        let maxDistributionAmount: u128 = positionImpactPoolAmount.sub_wrapped(minPositionImpactPoolAmount);

        let durationInBlocks: u32 = getBlocksSincePositionImpactPoolDistributed(marketData, atBlock);
        let distributionAmount: u128 = durationInBlocks as u128 * distributionRate;

        if (distributionAmount > maxDistributionAmount) {
            distributionAmount = maxDistributionAmount;
        }

        return (distributionAmount, positionImpactPoolAmount.sub_wrapped(distributionAmount));
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

    async transition updateFundingAndBorrowingState(
        public market: Market,
        public generalConfig: GeneralConfig,
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public prices: Prices,
        public atBlock: u32,
    )-> (MarketData, Future) {
        marketData = updateFundingState(
            market,
            marketConfig,
            marketData,
            prices,
            atBlock,
        );

        marketData = updateCumulativeBorrowingFactor(
            market,
            generalConfig,
            marketConfig,
            marketData,
            prices,
            atBlock,
        );

        return (marketData, finalizeFundingAndBorrowingState(atBlock));
    }

    async function finalizeFundingAndBorrowingState(
        atBlock: u32,
    ) {
        assert(block.height - atBlock < 100u32); // TODO
    }

    inline updateFundingState(
        market: Market,
        marketConfig: MarketConfig,
        marketData: MarketData,
        prices: Prices,
        atBlock: u32,
    ) -> MarketData {
        let result: GetNextFundingAmountPerSize = getNextFundingAmountPerSize(
            market,
            marketConfig,
            marketData,
            prices,
            atBlock,
        );

        let f1: CollateralPositionData = marketData.fundingFeeAmountPerSize;
        let f2: CollateralPositionData = result.fundingFeePerSizeDelta;
        let fundingFeeAmountPerSize: CollateralPositionData = CollateralPositionData {
            longTokenIsLong: f1.longTokenIsLong + f2.longTokenIsLong,
            shortTokenIsLong: f1.shortTokenIsLong + f2.shortTokenIsLong,
            longTokenIsShort: f1.longTokenIsShort + f2.longTokenIsShort,
            shortTokenIsShort: f1.shortTokenIsShort + f2.shortTokenIsShort,
        };

        let c1: CollateralPositionData = marketData.claimableFundingAmountPerSize;
        let c2: CollateralPositionData = result.claimableFundingPerSizeDelta;
        let claimableFundingAmountPerSize: CollateralPositionData = CollateralPositionData {
            longTokenIsLong: c1.longTokenIsLong + c2.longTokenIsLong,
            shortTokenIsLong: c1.shortTokenIsLong + c2.shortTokenIsLong,
            longTokenIsShort: c1.longTokenIsShort + c2.longTokenIsShort,
            shortTokenIsShort: c1.shortTokenIsShort + c2.shortTokenIsShort,
        };

        return MarketData {
            positionImpactPoolAmount: marketData.positionImpactPoolAmount,
            positionImpactPoolDistAtBlock: marketData.positionImpactPoolDistAtBlock,
            swapImpactPoolAmount: marketData.swapImpactPoolAmount,
            savedFundingFactorPerSecond: result.nextSavedFundingFactorPerSecond,
            fundingUpdatedAtBlock: atBlock,
            openInterest: marketData.openInterest,
            openInterestInTokens: marketData.openInterestInTokens,
            collateralSum: marketData.collateralSum,
            fundingFeeAmountPerSize,
            claimableFundingAmountPerSize,
            cumulativeBorrowingFactor: marketData.cumulativeBorrowingFactor,
            cumulativeBFUpdatedAtBlock: marketData.cumulativeBFUpdatedAtBlock,
            totalBorrowing: marketData.totalBorrowing,
            poolAmount: marketData.poolAmount,
            claimableCollateralAmount: marketData.claimableCollateralAmount,
            claimableFeeAmount: marketData.claimableFeeAmount,
            affiliateRewardAmount: marketData.affiliateRewardAmount,
        };
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

        let diffUsdAfterExponent: u128 = diffUsd.pow(marketConfig.fundingExponentFactor);
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
                nextSavedFundingFactorPerSecond = savedFundingFactorPerSecondMagnitude.sub_wrapped(decreaseValue) * sign;
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

    inline updateCumulativeBorrowingFactor(
        market: Market,
        generalConfig: GeneralConfig,
        marketConfig: MarketConfig,
        marketData: MarketData,
        prices: Prices,
        atBlock: u32,
    ) -> MarketData {
        let longDelta: u128 = getNextCumulativeBorrowingFactor(
            generalConfig,
            marketConfig,
            marketData,
            prices,
            true, // isLong
            atBlock,
        ).1;

        let shortDelta: u128 = getNextCumulativeBorrowingFactor(
            generalConfig,
            marketConfig,
            marketData,
            prices,
            false, // isLong
            atBlock,
        ).1;

        return MarketData {
            positionImpactPoolAmount: marketData.positionImpactPoolAmount,
            positionImpactPoolDistAtBlock: marketData.positionImpactPoolDistAtBlock,
            swapImpactPoolAmount: marketData.swapImpactPoolAmount,
            savedFundingFactorPerSecond: marketData.savedFundingFactorPerSecond,
            fundingUpdatedAtBlock: marketData.fundingUpdatedAtBlock,
            openInterest: marketData.openInterest,
            openInterestInTokens: marketData.openInterestInTokens,
            collateralSum: marketData.collateralSum,
            fundingFeeAmountPerSize: marketData.fundingFeeAmountPerSize,
            claimableFundingAmountPerSize: marketData.claimableFundingAmountPerSize,
            cumulativeBorrowingFactor: PositionData {
                long: marketData.cumulativeBorrowingFactor.long + longDelta,
                short: marketData.cumulativeBorrowingFactor.short + shortDelta,
            },
            cumulativeBFUpdatedAtBlock: PositionAtBlock {
                long: atBlock,
                short: atBlock,
            },
            totalBorrowing: marketData.totalBorrowing,
            poolAmount: marketData.poolAmount,
            claimableCollateralAmount: marketData.claimableCollateralAmount,
            claimableFeeAmount: marketData.claimableFeeAmount,
            affiliateRewardAmount: marketData.affiliateRewardAmount,
        };
    }

    inline getNextCumulativeBorrowingFactor(
        generalConfig: GeneralConfig,
        marketConfig: MarketConfig,
        marketData: MarketData,
        prices: Prices,
        isLong: bool,
        atBlock: u32,
    ) -> (u128, u128) {
        let durationInBlocks: u128 = getBlocksSinceCumulativeBorrowingFactorUpdated(marketData, isLong, atBlock) as u128;
        let borrowingFactorPerSecond: u128 = getBorrowingFactorPerSecond(
            generalConfig,
            marketConfig,
            marketData,
            prices,
            isLong,
        );

        let cumulativeBorrowingFactor: u128 = isLong ? marketData.cumulativeBorrowingFactor.long : marketData.cumulativeBorrowingFactor.short;

        let delta: u128 = durationInBlocks * borrowingFactorPerSecond;
        let nextCumulativeBorrowingFactor: u128 = cumulativeBorrowingFactor + delta;
        return (nextCumulativeBorrowingFactor, delta);
    }

    inline getBorrowingFactorPerSecond(
        generalConfig: GeneralConfig,
        marketConfig: MarketConfig,
        marketData: MarketData,
        prices: Prices,
        isLong: bool,
    ) -> u128 {
        let reservedUsd: u128 = getReservedUsd(marketData, prices, isLong);
        if (reservedUsd == 0u128) {
            return 0u128;
        }

        if (generalConfig.skipBorrowingFeeForSmallerSide) {
            let longOpenInterest: u128 = getOpenInterest(marketData, true);
            let shortOpenInterest: u128 = getOpenInterest(marketData, false);

            if (isLong && longOpenInterest < shortOpenInterest) {
                return 0u128;
            }
            if (!isLong && shortOpenInterest < longOpenInterest) {
                return 0u128;
            }
        }

        let poolUsd: u128 = getPoolUsdWithoutPnl(marketData, prices, isLong, false);
        assert(poolUsd > 0u128);

        let optimalUsageFactor: u128 = isLong ? marketConfig.optimalUsageFactor.long : marketConfig.optimalUsageFactor.short;

        if (optimalUsageFactor > 0u128) {
        }

        let borrowingExponentFactor: u32 = isLong ? marketConfig.borrowingExponentFactor.long : marketConfig.borrowingExponentFactor.short;
        let reservedUsdAfterExponent: u128 = reservedUsd.pow(borrowingExponentFactor);

        let reservedUsdToPoolFactor: u128 = reservedUsdAfterExponent / poolUsd;
        let borrowingFactor: u128 = isLong ? marketConfig.borrowingFactor.long : marketConfig.borrowingFactor.short;

        return reservedUsdToPoolFactor * borrowingFactor;
    }

    inline getTotalPendingBorrowingFees(
        generalConfig: GeneralConfig,
        marketConfig: MarketConfig,
        marketData: MarketData,
        prices: Prices,
        isLong: bool,
        atBlock: u32,
    ) -> u128 {
        let openInterest: u128 = getOpenInterest(marketData, isLong);

        let nextCumulativeBorrowingFactor: u128 = getNextCumulativeBorrowingFactor(
            generalConfig,
            marketConfig,
            marketData,
            prices,
            isLong,
            atBlock,
        ).0;

        let totalBorrowing: u128 = isLong ? marketData.totalBorrowing.long : marketData.totalBorrowing.short;

        return openInterest * nextCumulativeBorrowingFactor / FACTOR_PRECISION_U - totalBorrowing;
    }

    inline getPoolUsdWithoutPnl(
        marketData: MarketData,
        prices: Prices,
        isLong: bool,
        maximize: bool,
    ) -> u128 {
        let poolAmount: u128 = isLong ? marketData.poolAmount.long : marketData.poolAmount.short;
        let tokenPrice: u128 = maximize ?
            (isLong ? prices.longToken.max : prices.shortToken.max) :
            (isLong ? prices.longToken.min : prices.shortToken.min);

        return poolAmount * tokenPrice;
    }

    transition validateMaxPnl(
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public prices: Prices,
        public pnlFactorTypeForLongs: u8,
        public pnlFactorTypeForShorts: u8,
    ) {
        let (isPnlFactorExceededForLongs, pnlToPoolFactorForLongs, maxPnlFactorForLongs): (bool, i128, u128) = isPnlFactorExceeded(
            marketConfig,
            marketData,
            prices,
            true, // isLong
            pnlFactorTypeForLongs,
        );

        let (isPnlFactorExceededForShorts, pnlToPoolFactorForShorts, maxPnlFactorForShorts): (bool, i128, u128) = isPnlFactorExceeded(
            marketConfig,
            marketData,
            prices,
            false, // isLong
            pnlFactorTypeForShorts,
        );

        assert(!isPnlFactorExceededForLongs && !isPnlFactorExceededForShorts);
    }

    const PnlFactorForTraders: u8 = 0u8;
    const PnlFactorForAdl: u8 = 1u8;
    const PnlFactorAfterAdl: u8 = 2u8;
    const PnlFactorForDeposits: u8 = 3u8;
    const PnlFactorForWithdrawals: u8 = 4u8;

    inline getMaxPnlFactor(
        marketConfig: MarketConfig,
        isLong: bool,
        pnlFactorType: u8,
    ) -> u128 {
        let maxPnlFactor: PositionData = pnlFactorType == PnlFactorForTraders ? marketConfig.maxPnlFactorForTraders :
            pnlFactorType == PnlFactorForAdl ? marketConfig.maxPnlFactorForAdl :
            pnlFactorType == PnlFactorAfterAdl ? marketConfig.minPnlFactorAfterAdl :
            pnlFactorType == PnlFactorForDeposits ? marketConfig.maxPnlFactorForDeposits :
            marketConfig.maxPnlFactorForWithdrawals;
        return isLong ? maxPnlFactor.long : maxPnlFactor.short;
    }

    inline isPnlFactorExceeded(
        marketConfig: MarketConfig,
        marketData: MarketData,
        prices: Prices,
        isLong: bool,
        pnlFactorType: u8,
    ) -> (bool, i128, u128) {
        let pnlToPoolFactor: i128 = getPnlToPoolFactor(marketData, prices, isLong, true);
        let maxPnlFactor: u128 = getMaxPnlFactor(marketConfig, isLong, pnlFactorType);

        let isExceeded: bool = pnlToPoolFactor > 0i128 && pnlToPoolFactor as u128 > maxPnlFactor;

        return (isExceeded, pnlToPoolFactor, maxPnlFactor);
    }

    inline getPnlToPoolFactor(
        marketData: MarketData,
        prices: Prices,
        isLong: bool,
        maximize: bool,
    ) -> i128 {
        let poolUsd: u128 = getPoolUsdWithoutPnl(marketData, prices, isLong, maximize);
        if (poolUsd == 0u128) {
            return 0i128;
        }

        let pnl: i128 = getPnl(
            marketData,
            prices,
            isLong,
            maximize,
        );

        return pnl * FACTOR_PRECISION_I / poolUsd as i128;
    }

    inline getPnl(
        marketData: MarketData,
        prices: Prices,
        isLong: bool,
        maximize: bool,
    ) -> i128 {
        let openInterest: i128 = getOpenInterest(marketData, isLong) as i128;
        let openInterestInTokens: u128 = getOpenInterestInTokens(marketData, isLong);
        if (openInterest == 0i128 || openInterestInTokens == 0u128) {
            return 0i128;
        }

        let price: u128 = pickPriceForPnl(prices.indexToken, isLong, maximize);

        // `openInterest` is the cost of all positions, `openInterestValue` is the current worth of all positions.
        let openInterestValue: i128 = (openInterestInTokens * price) as i128;
        return isLong ? openInterestValue - openInterest : openInterest - openInterestValue;
    }

    inline getCappedPnl(
        marketConfig: MarketConfig,
        isLong: bool,
        pnl: i128,
        poolUsd: u128,
        pnlFactorType: u8,
    ) -> i128 {
        if (pnl < 0i128) {
            return pnl;
        }

        let maxPnlFactor: u128 = getMaxPnlFactor(marketConfig, isLong, pnlFactorType);
        let maxPnl: i128 = (poolUsd * maxPnlFactor / FACTOR_PRECISION_U) as i128;

        return pnl > maxPnl ? maxPnl : pnl;
    }

    inline getReservedUsd(
        marketData: MarketData,
        prices: Prices,
        isLong: bool,
    ) -> u128 {
        if (isLong) {
            let openInterestInTokens: u128 = getOpenInterestInTokens(marketData, isLong);
            return openInterestInTokens * prices.indexToken.max;
        } else {
            return getOpenInterest(marketData, isLong);
        }
    }

    inline getOpenInterest(
        marketData: MarketData,
        isLong: bool,
    ) -> u128 {
        let interest: CollateralPositionData = marketData.openInterest;
        return isLong ?
            interest.longTokenIsLong + interest.shortTokenIsLong :
            interest.longTokenIsShort + interest.shortTokenIsShort;
    }

    inline getOpenInterestInTokens(
        marketData: MarketData,
        isLong: bool,
    ) -> u128 {
        let tokens: CollateralPositionData = marketData.openInterestInTokens;
        return isLong ?
            tokens.longTokenIsLong + tokens.shortTokenIsLong :
            tokens.longTokenIsShort + tokens.shortTokenIsShort;
    }

    inline getBlocksSinceCumulativeBorrowingFactorUpdated(
        marketData: MarketData,
        isLong: bool,
        atBlock: u32,
    ) -> u32 {
        let updatedAt: PositionAtBlock = marketData.cumulativeBFUpdatedAtBlock;
        return isLong ?
            updatedAt.long == 0u32 ? 0u32 : atBlock - updatedAt.long :
            updatedAt.short == 0u32 ? 0u32 : atBlock - updatedAt.short;
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

    inline pickPrice(price: Price, maximize: bool) -> u128 {
        return maximize ? price.max : price.min;
    }

    inline pickPriceForPnl(price: Price, isLong: bool, maximize: bool) -> u128 {
        // For long positions, pick the larger price to maximize pnl.
        // For short positions, pick the smaller price to maximize pnl.
        return isLong ? (maximize ? price.max : price.min) : (maximize ? price.min : price.max);
    }

    struct MarketPoolValueInfo {
        poolValue: i128,
        longPnl: i128,
        shortPnl: i128,
        netPnl: i128,

        longTokenAmount: u128,
        shortTokenAmount: u128,
        longTokenUsd: u128,
        shortTokenUsd: u128,

        totalBorrowingFees: u128,
        borrowingFeePoolFactor: u128,

        impactPoolAmount: u128,
    }

    transition getPoolValueInfo(
        public generalConfig: GeneralConfig,
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public prices: Prices,
        public pnlFactorType: u8,
        public maximize: bool,
        public atBlock: u32,
    ) -> MarketPoolValueInfo {
        let longTokenAmount: u128 = marketData.poolAmount.long;
        let shortTokenAmount: u128 = marketData.poolAmount.short;

        let longTokenUsd: u128 = longTokenAmount * pickPrice(prices.longToken, maximize);
        let shortTokenUsd: u128 = shortTokenAmount * pickPrice(prices.shortToken, maximize);

        let poolValue: i128 = (longTokenUsd + shortTokenUsd) as i128;

        let totalBorrowingFees: u128 = getTotalPendingBorrowingFees(
            generalConfig,
            marketConfig,
            marketData,
            prices,
            true,
            atBlock,
        );

        totalBorrowingFees += getTotalPendingBorrowingFees(
            generalConfig,
            marketConfig,
            marketData,
            prices,
            false,
            atBlock,
        );

        let borrowingFeePoolFactor: u128 = FACTOR_PRECISION_U - generalConfig.borrowingFeeReceiverFactor;
        poolValue += (totalBorrowingFees * borrowingFeePoolFactor / FACTOR_PRECISION_U) as i128;

        let longPnl: i128 = getPnl(
            marketData,
            prices,
            true,
            !maximize,
        );

        longPnl = getCappedPnl(
            marketConfig,
            true,
            longPnl,
            longTokenUsd,
            pnlFactorType,
        );

        let shortPnl: i128 = getPnl(
            marketData,
            prices,
            false,
            !maximize,
        );

        shortPnl = getCappedPnl(
            marketConfig,
            false,
            shortPnl,
            shortTokenUsd,
            pnlFactorType,
        );

        let netPnl: i128 = longPnl + shortPnl;
        poolValue -= netPnl;

        let impactPoolAmount: u128 = getNextPositionImpactPoolAmount(
            marketConfig,
            marketData,
            atBlock,
        );
        let impactPoolUsd: u128 = impactPoolAmount * pickPrice(prices.indexToken, !maximize);

        poolValue -= impactPoolUsd as i128;

        return MarketPoolValueInfo {
            poolValue,
            longPnl,
            shortPnl,
            netPnl,
            longTokenAmount,
            shortTokenAmount,
            longTokenUsd,
            shortTokenUsd,
            totalBorrowingFees,
            borrowingFeePoolFactor,
            impactPoolAmount,
        };
    }

    transition applySwapImpactWithCap(
        marketData: MarketData,
        prices: Prices,
        isLong: bool,
        priceImpactUsd: i128,
    ) -> (MarketData, i128, u128) {
        let (impactAmount, cappedDiffUsd): (i128, u128) = getSwapImpactAmountWithCap(
            marketData,
            prices,
            isLong,
            priceImpactUsd,
        );

        let swapImpactPoolAmount: u128 = isLong ?
            marketData.swapImpactPoolAmount.long :
            marketData.swapImpactPoolAmount.short;

        // If there is a positive impact, the impact pool amount should be reduced.
        // If there is a negative impact, the impact pool amount should be increased.
        swapImpactPoolAmount = applyBoundedDeltaToUint(swapImpactPoolAmount, -impactAmount);

        marketData = MarketData {
            positionImpactPoolAmount: marketData.positionImpactPoolAmount,
            positionImpactPoolDistAtBlock: marketData.positionImpactPoolDistAtBlock,
            swapImpactPoolAmount: CollateralData {
                long: isLong ? swapImpactPoolAmount: marketData.swapImpactPoolAmount.long,
                short: isLong ? marketData.swapImpactPoolAmount.short : swapImpactPoolAmount,
            },
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
            claimableCollateralAmount: marketData.claimableCollateralAmount,
            claimableFeeAmount: marketData.claimableFeeAmount,
            affiliateRewardAmount: marketData.affiliateRewardAmount,
        };

        return (marketData, impactAmount, cappedDiffUsd);
    }

    inline getSwapImpactAmountWithCap(
        marketData: MarketData,
        prices: Prices,
        isLong: bool,
        priceImpactUsd: i128,
    ) -> (i128, u128) {
        let tokenPrice: Price = isLong ? prices.longToken : prices.shortToken;

        if (priceImpactUsd > 0i128) {
            let impactAmount: i128 = priceImpactUsd / tokenPrice.max as i128;

            let maxImpactAmount: i128 = (isLong ?
                marketData.swapImpactPoolAmount.long :
                marketData.swapImpactPoolAmount.short
            ) as i128;

            let cappedDiffUsd: u128 = 0u128;
            if (impactAmount > maxImpactAmount) {
                cappedDiffUsd = impactAmount.sub_wrapped(maxImpactAmount) as u128 * tokenPrice.max;
                impactAmount = maxImpactAmount;
            }

            return (impactAmount, cappedDiffUsd);
        } else {
            let impactAmount: i128 = roundUpMagnitudeDivision(priceImpactUsd, tokenPrice.min);
            return (impactAmount, 0u128);
        }
    }

    inline roundUpMagnitudeDivision(a: i128, b: u128) -> i128 {
        let b_: i128 = b as i128;
        return a < 0i128 ? (a - b_ + 1i128) / b_ : (a + b_ - 1i128) / b_;
    }

    inline applyDeltaToUint(value: u128, delta: i128) -> u128 {
        let deltaAbs: u128 = delta.abs() as u128;
        if (delta >= 0i128) {
            return value + deltaAbs;
        } else {
            // Revert if underflow.
            return value - deltaAbs;
        }
    }

    inline applyBoundedDeltaToUint(value: u128, delta: i128) -> u128 {
        let deltaAbs: u128 = delta.abs() as u128;
        return delta >= 0i128 ?
            value + deltaAbs :
            (value < deltaAbs ? 0u128 : value.sub_wrapped(deltaAbs));
    }

    transition usdToMarketTokenAmount(
        public usdValue: u128,
        public poolValue: u128,
        public supply: u128,
    ) -> u128 {
        // If the supply and poolValue is zero, use 1 USD as the token price.
        if (supply == 0u128 && poolValue == 0u128) {
            return usdValue / (PRECISION_U / MARKET_TOKEN_PRECISION_U);
        }

        // If the supply is zero and the poolValue is more than zero,
        // then include the poolValue for the amount of tokens minted so that
        // the market token price after mint would be 1 USD.
        if (supply == 0u128 && poolValue > 0u128) {
            return (usdValue + poolValue) / (PRECISION_U / MARKET_TOKEN_PRECISION_U);
        }

        // Use the `USD_DIVISOR_U` divisor to avoid overflow when calculating `supply * usdValue`.
        // So that the usd value below 1e-6 will be rounded to 0.
        // The returned marketTokenAmount is rounded down.
        // Revert if poolValue is zero.
        return supply * (usdValue / USD_DIVISOR_U) / (poolValue / USD_DIVISOR_U);
    }

    transition marketTokenAmountToUsd(
        public marketTokenAmount: u128,
        public poolValue: u128,
        public supply: u128,
    ) -> u128 {
        assert(supply > 0u128);

        // Use the `USD_DIVISOR_U` divisor to avoid overflow when calculating `poolValue * marketTokenAmount`.
        // So that the usd value below 1e-6 will be rounded to 0.
        // The returned usdValue is rounded down.
        return (poolValue / USD_DIVISOR_U) * marketTokenAmount / supply * USD_DIVISOR_U;
    }

    transition applyDeltaToPoolAmount(
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public virtualMarketData: VirtualMarketData,
        public isLong: bool,
        public delta: i128,
    ) -> (MarketData, VirtualMarketData) {
        let poolAmount: u128 = isLong ? marketData.poolAmount.long : marketData.poolAmount.short;
        poolAmount = applyDeltaToUint(poolAmount, delta);

        marketData = MarketData {
            positionImpactPoolAmount: marketData.positionImpactPoolAmount,
            positionImpactPoolDistAtBlock: marketData.positionImpactPoolDistAtBlock,
            swapImpactPoolAmount: marketData.swapImpactPoolAmount,
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
            poolAmount: CollateralData {
                long: isLong ? poolAmount : marketData.poolAmount.long,
                short: isLong ? marketData.poolAmount.short : poolAmount,
            },
            claimableCollateralAmount: marketData.claimableCollateralAmount,
            claimableFeeAmount: marketData.claimableFeeAmount,
            affiliateRewardAmount: marketData.affiliateRewardAmount,
        };

        let (a, virtualMarketData_, b): (bool, VirtualMarketData, u128) = applyDeltaToVirtualInventoryForSwaps(
            marketConfig,
            virtualMarketData,
            isLong,
            delta,
        );
        virtualMarketData = virtualMarketData_;

        return (marketData, virtualMarketData);
    }

    inline applyDeltaToVirtualInventoryForSwaps(
        marketConfig: MarketConfig,
        virtualMarketData: VirtualMarketData,
        isLong: bool,
        delta: i128,
    ) -> (bool, VirtualMarketData, u128) {
        if (marketConfig.virtualMarketId == 0field) {
            return (false, virtualMarketData, 0u128);
        }

        let virtualInventoryForSwaps: u128 = isLong ?
            virtualMarketData.virtualInventoryForSwaps.long :
            virtualMarketData.virtualInventoryForSwaps.short;

        virtualInventoryForSwaps = applyBoundedDeltaToUint(virtualInventoryForSwaps, delta);

        virtualMarketData = VirtualMarketData {
            virtualInventoryForSwaps: CollateralData {
                long: isLong ? virtualInventoryForSwaps : virtualMarketData.virtualInventoryForSwaps.long,
                short: isLong ? virtualMarketData.virtualInventoryForSwaps.short : virtualInventoryForSwaps,
            },
            virtualInventoryForPositions: virtualMarketData.virtualInventoryForPositions,
        };

        return (true, virtualMarketData, virtualInventoryForSwaps);
    }

    transition validatePoolAmount(
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public isLong: bool,
    ) {
        let poolAmount: u128 = isLong ? marketData.poolAmount.long : marketData.poolAmount.short;
        let maxPoolAmount: u128 = isLong ? marketConfig.maxPoolAmount.long : marketConfig.maxPoolAmount.short;
        assert(poolAmount <= maxPoolAmount);
    }

    async transition validateMarketTokenBalance(
        public market: Market,
        public marketData: MarketData,
    ) -> Future {
        let (expectedMinBalanceForLongToken, expectedMinBalanceForShortToken): (u128, u128) = getExpectedMinTokenBalance(marketData);

        let collateralAmountForLongToken: u128 = marketData.collateralSum.longTokenIsLong + marketData.collateralSum.longTokenIsShort;
        let collateralAmountForShortToken: u128 = marketData.collateralSum.shortTokenIsLong + marketData.collateralSum.shortTokenIsShort;

        let claimableFundingFeeAmountForLongToken: u128 = marketData.claimableFeeAmount.long;
        let claimableFundingFeeAmountForShortToken: u128 = marketData.claimableFeeAmount.short;

        let balanceKeyForLongToken: field = BHP256::hash_to_field(TokenOwner {
            account: self.address,
            token_id: market.longToken,
        });
        let balanceKeyForShortToken: field = BHP256::hash_to_field(TokenOwner {
            account: self.address,
            token_id: market.shortToken,
        });

        return finalizeValidateMarketTokenBalance(
            market,
            expectedMinBalanceForLongToken,
            expectedMinBalanceForShortToken,
            collateralAmountForLongToken,
            collateralAmountForShortToken,
            claimableFundingFeeAmountForLongToken,
            claimableFundingFeeAmountForShortToken,
            balanceKeyForLongToken,
            balanceKeyForShortToken,
        );
    }

    async function finalizeValidateMarketTokenBalance(
        market: Market,
        expectedMinBalanceForLongToken: u128,
        expectedMinBalanceForShortToken: u128,
        collateralAmountForLongToken: u128,
        collateralAmountForShortToken: u128,
        claimableFundingFeeAmountForLongToken: u128,
        claimableFundingFeeAmountForShortToken: u128,
        balanceKeyForLongToken: field,
        balanceKeyForShortToken: field,
    ) {
        let balanceForLongToken: u128 = multi_token_support_program.aleo/authorized_balances.get(balanceKeyForLongToken).balance;

        if (balanceKeyForLongToken == balanceKeyForShortToken) {
            assert(balanceForLongToken >= expectedMinBalanceForLongToken + expectedMinBalanceForShortToken);
            // Funding fees can be claimed even if the collateral for positions that should pay funding fees
            // hasn't been reduced yet.
            // Due to that, funding fees and collateral is excluded from the expectedMinBalance calculation
            // and validated separately.
            assert(balanceForLongToken >= collateralAmountForLongToken + collateralAmountForShortToken);
            // In case of late liquidations, it may be possible for the claimableFundingFeeAmount to exceed the market token balance.
            // But this should be very rare.
            assert(balanceForLongToken >= claimableFundingFeeAmountForLongToken + claimableFundingFeeAmountForShortToken);
        } else {
            let balanceForShortToken: u128 = multi_token_support_program.aleo/authorized_balances.get(balanceKeyForShortToken).balance;

            assert(balanceForLongToken >= expectedMinBalanceForLongToken);
            assert(balanceForLongToken >= collateralAmountForLongToken);
            assert(balanceForLongToken >= claimableFundingFeeAmountForLongToken);

            assert(balanceForShortToken >= expectedMinBalanceForShortToken);
            assert(balanceForShortToken >= collateralAmountForShortToken);
            assert(balanceForShortToken >= claimableFundingFeeAmountForShortToken);
        }
    }

    inline getExpectedMinTokenBalance(
        marketData: MarketData,
    ) -> (u128, u128) {
        // Funding fees are excluded from this summation as claimable funding fees
        // are incremented without a corresponding decrease of the collateral of
        // other positions, the collateral of other positions is decreased when
        // those positions are updated.
        return (
            marketData.poolAmount.long +
            marketData.swapImpactPoolAmount.long +
            marketData.claimableCollateralAmount.long +
            marketData.claimableFeeAmount.long +
            marketData.affiliateRewardAmount.long,

            marketData.poolAmount.short +
            marketData.swapImpactPoolAmount.short +
            marketData.claimableCollateralAmount.short +
            marketData.claimableFeeAmount.short +
            marketData.affiliateRewardAmount.short,
        );
    }

    async transition validateSwapPath(
        public swapPath: [field; 2],
    ) -> Future {
        return finalizeValidateSwapPath(swapPath);
    }

    async function finalizeValidateSwapPath(
        swapPath: [field; 2],
    ) {
        for i: u8 in 0u8..2u8 {
            let marketId: field = swapPath[i];
            let cfg: MarketConfig = aleox_store_v1.aleo/marketConfig.get(marketId);
            assert(!cfg.isMarketDisabled);
            let market: Market = markets.get(marketId);
            assert(market.longToken != market.shortToken);
        }
    }

    transition validateReserve(
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public prices: Prices,
        public isLong: bool,
    ) {
        // `poolUsd` is used instead of pool amount as the `indexToken` may not match the `longToken`.
        // Additionally, the `shortToken` may not be a stablecoin.
        let poolUsd: u128 = getPoolUsdWithoutPnl(marketData, prices, isLong, false);
        let reserveFactor: u128 = isLong ? marketConfig.reserveFactor.long : marketConfig.reserveFactor.short;
        let maxReservedUsd: u128 = poolUsd * reserveFactor / FACTOR_PRECISION_U;

        let reservedUsd: u128 = getReservedUsd(marketData, prices, isLong);

        assert(reservedUsd <= maxReservedUsd);
    }
}
