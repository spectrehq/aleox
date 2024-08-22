program aleox_oracle_v1.aleo {
    struct Price {
        min: u128,
        max: u128,
    }

    struct TokenPrice {
        token: field,
        min: u128,
        max: u128,
        block_: u32,
    }

    struct Prices {
        indexToken: Price,
        longToken: Price,
        shortToken: Price,
        swapTokens: [Price; 3],
        minBlock: u32,
        maxBlock: u32,
    }

    transition getPrices(public prices: [TokenPrice; 6]) -> Prices {
        let indexToken: Price = Price { min: prices[0u8].min, max: prices[0u8].max };
        let longToken: Price = Price { min: prices[1u8].min, max: prices[1u8].max };
        let shortToken: Price = Price { min: prices[2u8].min, max: prices[2u8].max };
        let swapTokens: [Price; 3] = [
            Price { min: prices[3u8].min, max: prices[3u8].max },
            Price { min: prices[4u8].min, max: prices[4u8].max },
            Price { min: prices[5u8].min, max: prices[5u8].max },
        ];

        let minBlock: u32 = prices[0u8].block_;
        let maxBlock: u32 = minBlock;
        for i: u8 in 0u8..6u8 {
            assert(0u128 < prices[i].min && prices[i].min <= prices[i].max);

            let block_: u32 = prices[i].block_;
            minBlock = minBlock < block_ ? minBlock : block_;
            maxBlock = maxBlock > block_ ? maxBlock : block_;
        }

        let maxOracleTimestampRange: u32 = 0u32; // TODO
        assert(maxBlock - minBlock <= maxOracleTimestampRange);

        return Prices { indexToken, longToken, shortToken, swapTokens, minBlock, maxBlock };
    }

    transition midPrice(price: Price) -> u128 {
        return (price.max + price.min) / 2u128;
    }
}
