program aleox_order_v1.aleo {
    // MarketSwap: swap token A to token B at the current market price
    // the order will be cancelled if the minOutputAmount cannot be fulfilled
    const OrderType_MarketSwap: u8 = 0u8;
    // LimitSwap: swap token A to token B if the minOutputAmount can be fulfilled
    const OrderType_LimitSwap: u8 = 1u8;
    // MarketIncrease: increase position at the current market price
    // the order will be cancelled if the position cannot be increased at the acceptablePrice
    const OrderType_MarketIncrease: u8 = 2u8;
    // LimitIncrease: increase position if the triggerPrice is reached and the acceptablePrice can be fulfilled
    const OrderType_LimitIncrease: u8 = 3u8;
    // MarketDecrease: decrease position at the current market price
    // the order will be cancelled if the position cannot be decreased at the acceptablePrice
    const OrderType_MarketDecrease: u8 = 4u8;
    // LimitDecrease: decrease position if the triggerPrice is reached and the acceptablePrice can be fulfilled
    const OrderType_LimitDecrease: u8 = 5u8;
    // StopLossDecrease: decrease position if the triggerPrice is reached and the acceptablePrice can be fulfilled
    const OrderType_StopLossDecrease: u8 = 6u8;
    // Liquidation: allows liquidation of positions if the criteria for liquidation are met
    const OrderType_Liquidation: u8 = 7u8;

    const DecreasePositionSwapType_NoSwap: u8 = 0u8;
    const DecreasePositionSwapType_SwapPnlTokenToCollateralToken: u8 = 1u8;
    const DecreasePositionSwapType_SwapCollateralTokenToPnlToken: u8 = 2u8;

    struct Order {
        account: address,
        receiver: address,
        cancellationReceiver: address,
        market: field,
        initialCollateralToken: field,
        swapPath: [field; 2],

        orderType: u8, // OrderType_*
        decreasePositionSwapType: u8, // DecreasePositionSwapType_*
        sizeDeltaUsd: u128,
        initialCollateralDeltaAmount: u128,
        triggerPrice: u128,
        acceptablePrice: u128,
        executionFee: u128,
        minOutputAmount: u128,
        updatedAtBlock: u32,

        isLong: bool,
        shouldUnwrapNativeToken: bool,
        isFrozen: bool,
        autoCancel: bool,
    }

    mapping orders: u32 => Order; // order key => order

    mapping orderCount: u8 => u32; // 0u8 => order count

    mapping orderList: u32 => u32; // index => order key

    mapping orderByKeyList: u32 => u32; // order key => index

    mapping orderNonce: u8 => u32; // 0u8 => order key generator

    async transition createOrder(public order: Order) -> Future {
        return finalizeCreateOrder(order);
    }

    async function finalizeCreateOrder(order: Order) {
        let key: u32 = orderNonce.get_or_use(0u8, 0u32);
        orderNonce.set(0u8, key + 1u32);

        orders.set(key, order);

        let index: u32 = orderCount.get_or_use(0u8, 0u32);
        orderCount.set(0u8, index + 1u32);
        orderList.set(index, key);
        orderByKeyList.set(key, index);
    }

    async transition removeOrder(public key: u32) -> Future {
        return finalizeRemoveOrder(key);
    }

    async function finalizeRemoveOrder(key: u32) {
        assert(orders.contains(key));
        orders.remove(key);

        let index: u32 = orderByKeyList.get(key);
        assert_eq(orderList.get(index), key);

        let lastIndex: u32 = orderCount.get(0u8) - 1u32;
        orderCount.set(0u8, lastIndex);

        // If the order is not the last one, move the last order to the removed order's position.
        if (index < lastIndex) {
            let keyOfLastOrder: u32 = orderList.get(lastIndex);
            orderList.set(index, keyOfLastOrder);
            orderByKeyList.set(keyOfLastOrder, index);
        }
        // Remove the last order.
        orderList.remove(lastIndex);
        orderByKeyList.remove(key);
    }
}
