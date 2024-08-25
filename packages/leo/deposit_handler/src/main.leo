import aleox_deposit_v1.aleo;

program aleox_deposit_handler_v1.aleo {
    const SwapPricingTwoStep: u8 = 0u8;

    async transition executeDeposit(
        public key: u32,
        public deposit: Deposit,
        public market: Market,
        public generalConfig: GeneralConfig,
        public marketConfig: MarketConfig,
        public marketData: MarketData,
        public virtualMarketData: VirtualMarketData,
        public oracle: Oracle,
        public marketTokensSupply: u128,
        public atBlock: u32,
    ) -> Future {
        let marketDataHash: field = Keccak256::hash_to_field(marketData);
        let virtualMarketDataHash: field = Keccak256::hash_to_field(virtualMarketData);

        let (receivedMarketTokens, marketData1, virtualMarketData1, f1): (u128, MarketData, VirtualMarketData, Future) = aleox_deposit_v1.aleo/executeDeposit(
            ExecuteDepositParams {
                key_: key,
                keeper: self.caller,
                swapPricingType: SwapPricingTwoStep,
                includeVirtualInventoryImpact: true,
                marketTokensSupply,
                atBlock,
            },
            deposit,
            market,
            generalConfig,
            marketConfig,
            marketData,
            virtualMarketData,
            oracle,
        );
        marketData = marketData1;
        virtualMarketData = virtualMarketData1;

        // Save marketData.
        let f2: Future = aleox_store_v1.aleo/setMarketData(deposit.market, marketData);
        let f3: Future = aleox_store_v1.aleo/setVirtualMarketData(marketConfig.virtualMarketId, virtualMarketData);

        return finalizeExecuteDeposit(
            f1,
            f2,
            f3,
            key,
            deposit.market,
            marketConfig,
            Keccak256::hash_to_field(deposit),
            Keccak256::hash_to_field(market),
            Keccak256::hash_to_field(generalConfig),
            Keccak256::hash_to_field(marketConfig),
            marketDataHash,
            virtualMarketDataHash,
            atBlock,
        );
    }

    async function finalizeExecuteDeposit(
        f1: Future,
        f2: Future,
        f3: Future,
        key: u32,
        market: field,
        marketConfig: MarketConfig,
        depositHash: field,
        marketHash: field,
        generalConfigHash: field,
        marketConfigHash: field,
        marketDataHash: field,
        virtualMarketDataHash: field,
        atBlock: u32,
    ) {
        // Validate that those parameters are in consistency with the on-chain data.
        // TODO: use get_or_use
        assert_eq(depositHash, Keccak256::hash_to_field(aleox_deposit_v1.aleo/deposits.get(key)));
        assert_eq(marketHash, Keccak256::hash_to_field(aleox_market_v1.aleo/markets.get(market)));
        assert_eq(generalConfigHash, Keccak256::hash_to_field(aleox_store_v1.aleo/generalConfig.get(0u8)));
        assert_eq(marketConfigHash, Keccak256::hash_to_field(aleox_store_v1.aleo/marketConfig.get(market)));
        assert_eq(marketDataHash, Keccak256::hash_to_field(aleox_store_v1.aleo/marketData.get(market)));
        assert_eq(virtualMarketDataHash, Keccak256::hash_to_field(aleox_store_v1.aleo/virtualMarketData.get(marketConfig.virtualMarketId)));

        assert(block.height - atBlock < 100u32); // TODO

        f1.await();
        f2.await();
        f3.await();
    }
}
