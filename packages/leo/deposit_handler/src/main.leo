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
        public prices: Prices,
        public marketTokensSupply: u128,
        public atBlock: u32,
    ) -> Future {
        let (receivedMarketTokens, marketData1, f1): (u128, MarketData, Future) = aleox_deposit_v1.aleo/executeDeposit(
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
            prices,
        );

        // Save marketData.
        let f2: Future = aleox_store_v1.aleo/setMarketData(deposit.market, marketData1);

        return finalizeExecuteDeposit(
            f1,
            f2,
            key,
            deposit.market,
            Keccak256::hash_to_field(deposit),
            Keccak256::hash_to_field(market),
            Keccak256::hash_to_field(generalConfig),
            Keccak256::hash_to_field(marketConfig),
            Keccak256::hash_to_field(marketData),
            atBlock,
        );
    }

    async function finalizeExecuteDeposit(
        f1: Future,
        f2: Future,
        key: u32,
        market: field,
        depositHash: field,
        marketHash: field,
        generalConfigHash: field,
        marketConfigHash: field,
        marketDataHash: field,
        atBlock: u32,
    ) {
        // Validate that those parameters are in consistency with the on-chain data.
        assert_eq(depositHash, Keccak256::hash_to_field(aleox_deposit_v1.aleo/deposits.get(key)));
        assert_eq(marketHash, Keccak256::hash_to_field(aleox_market_v1.aleo/markets.get(market)));
        assert_eq(generalConfigHash, Keccak256::hash_to_field(aleox_store_v1.aleo/generalConfig.get(0u8)));
        assert_eq(marketConfigHash, Keccak256::hash_to_field(aleox_store_v1.aleo/marketConfig.get(market)));
        assert_eq(marketDataHash, Keccak256::hash_to_field(aleox_store_v1.aleo/marketData.get(market)));

        assert(block.height - atBlock < 100u32); // TODO

        f1.await();
        f2.await();
    }
}
