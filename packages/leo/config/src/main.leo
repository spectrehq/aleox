program aleox_config_v1.aleo {
    struct MarketConfig {
        market: field,
    }

    struct MarketTokenConfig {
        market: field,
        token: field,
    }

    struct MarketTokenAccountConfig {
        market: field,
        token: field,
        account: address,
    }

    struct TokenConfig {
        token: field,
    }

    struct ModuleConfig {
        module: address,
    }

    struct ModuleOrderTypeConfig {
        module: address,
        orderType: u8,
    }

    struct AccountConfig {
        account: address,
    }

    struct ProviderConfig {
        provider: address,
    }

    struct ProviderTokenConfig {
        provider: address,
        token: field,
    }

    struct TokenConfig {
        token: field,
    }

    struct AccountMarketConfig {
        account: address,
        market: field,
    }

    struct MarketIsLongConfig {
        market: field,
        isLong: field,
    }
}
