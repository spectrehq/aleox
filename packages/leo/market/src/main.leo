import multi_token_support_program.aleo;

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
}
