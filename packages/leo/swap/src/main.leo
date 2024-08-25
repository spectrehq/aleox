import aleox_swap_inner_v1.aleo;

program aleox_swap_v1.aleo {
    const ZERO_FIELD: field = 0field;
    const ZERO_ADDRESS: address = aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;

    struct SwapParams {
        tokenIn: field,
        amountIn: u128,
        swapPath: [field; 2],
        minOutputAmount: u128,
        receiver: address,
        shouldUnwrapNativeToken: bool,
    }

    struct SwapMarkets {
        market: Market,
        marketConfig: MarketConfig,
        marketData: MarketData,
        virtualMarketData: VirtualMarketData,
        prices: Prices,
    }

    async transition swap(
        public params: SwapParams,
        public generalConfig: GeneralConfig,
        public marketData: MarketData,
        public swapMarkets: [SwapMarkets; 2],
    ) -> (field, u128, Future) {
        assert(params.amountIn > 0u128);

        let markets: SwapMarkets = swapMarkets[0u8];
        assert(markets.market.marketToken == params.swapPath[0u8]);

        let tokenIn1: field = params.tokenIn;
        let amountIn1: u128 = params.amountIn;
        assert(tokenIn1 == markets.market.shortToken || tokenIn1 == markets.market.longToken);
        let isLongTokenIn1: bool = tokenIn1 == markets.market.longToken;

        let (tokenOut1, amountOut1, f1): (field, u128, Future) = aleox_swap_inner_v1.aleo/swap(
            SwapParams_ {
                isLongTokenIn: isLongTokenIn1,
                amountIn: amountIn1,
                receiver: ZERO_ADDRESS, // only transfer tokens on the last swap if needed
                shouldUnwrapNativeToken: false, // only convert native tokens on the last swap if needed
            },
            generalConfig,
            markets.market,
            markets.marketConfig,
            markets.marketData,
            markets.virtualMarketData,
            markets.prices,
        );
        assert(tokenOut1 == (isLongTokenIn1 ? markets.market.shortToken : markets.market.longToken));

        markets = swapMarkets[1u8];
        assert(markets.market.marketToken == params.swapPath[1u8]);

        let tokenIn2: field = tokenOut1;
        let amountIn2: u128 = amountOut1;
        assert(tokenIn2 == markets.market.shortToken || tokenIn2 == markets.market.longToken);
        let isLongTokenIn2: bool = tokenIn2 == markets.market.longToken;

        let (tokenOut2, amountOut2, f2): (field, u128, Future) = aleox_swap_inner_v1.aleo/swap(
            SwapParams_ {
                isLongTokenIn: isLongTokenIn2,
                amountIn: amountIn2,
                receiver: params.receiver,
                shouldUnwrapNativeToken: params.shouldUnwrapNativeToken, // only convert native token on the last swap if needed
            },
            generalConfig,
            markets.market,
            markets.marketConfig,
            markets.marketData,
            markets.virtualMarketData,
            markets.prices,
        );

        return (0field, 0u128, finalizeSwap(f1, f2));
    }

    async function finalizeSwap(
        f1: Future,
        f2: Future,
    ) {
        f1.await();
        f2.await();
    }
}
