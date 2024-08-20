import aleox_store_v1.aleo;

program aleox_configurator_v1.aleo {
    async transition setGeneralConfig(public cfg: GeneralConfig) -> Future {
        let f: Future = aleox_store_v1.aleo/setGeneralConfig(cfg);

        return finalizeSetGeneralConfig(f);
    }

    async function finalizeSetGeneralConfig(f: Future) {
        f.await();
    }

    async transition setFeeReceiver(public cfg: GeneralConfig) -> Future {
        let f: Future = aleox_store_v1.aleo/setGeneralConfig(cfg);

        return finalizeSetFeeReceiver(f, cfg);
    }

    async function finalizeSetFeeReceiver(f: Future, cfg: GeneralConfig) {
        // Ensure that other configuration fields are not changed.
        let c: GeneralConfig = aleox_store_v1.aleo/generalConfig.get(0u8);
        assert(
            c.holdingAddress == cfg.holdingAddress &&
            c.maxAutoCancelOrders == cfg.maxAutoCancelOrders &&
            c.requestExpirationBlocks == cfg.requestExpirationBlocks &&
            c.minCollateralUsd == cfg.minCollateralUsd &&
            c.minPositionSizeUsd == cfg.minPositionSizeUsd &&
            c.maxFundingFactorPerSecondLimit == cfg.maxFundingFactorPerSecondLimit &&
            c.skipBorrowingFeeForSmallerSide == cfg.skipBorrowingFeeForSmallerSide
        );

        f.await();
    }

    async transition setHoldingAddress(public cfg: GeneralConfig) -> Future {
        let f: Future = aleox_store_v1.aleo/setGeneralConfig(cfg);

        return finalizeSetHoldingAddress(f, cfg);
    }

    async function finalizeSetHoldingAddress(f: Future, cfg: GeneralConfig) {
        // Ensure that other configuration fields are not changed.
        let c: GeneralConfig = aleox_store_v1.aleo/generalConfig.get(0u8);
        assert(
            c.feeReceiver == cfg.feeReceiver &&
            c.maxAutoCancelOrders == cfg.maxAutoCancelOrders &&
            c.requestExpirationBlocks == cfg.requestExpirationBlocks &&
            c.minCollateralUsd == cfg.minCollateralUsd &&
            c.minPositionSizeUsd == cfg.minPositionSizeUsd &&
            c.maxFundingFactorPerSecondLimit == cfg.maxFundingFactorPerSecondLimit &&
            c.skipBorrowingFeeForSmallerSide == cfg.skipBorrowingFeeForSmallerSide
        );

        f.await();
    }

    async transition setMaxAutoCancelOrders(public cfg: GeneralConfig) -> Future {
        let f: Future = aleox_store_v1.aleo/setGeneralConfig(cfg);

        return finalizeSetMaxAutoCancelOrders(f, cfg);
    }

    async function finalizeSetMaxAutoCancelOrders(f: Future, cfg: GeneralConfig) {
        // Ensure that other configuration fields are not changed.
        let c: GeneralConfig = aleox_store_v1.aleo/generalConfig.get(0u8);
        assert(
            c.feeReceiver == cfg.feeReceiver &&
            c.holdingAddress == cfg.holdingAddress &&
            c.requestExpirationBlocks == cfg.requestExpirationBlocks &&
            c.minCollateralUsd == cfg.minCollateralUsd &&
            c.minPositionSizeUsd == cfg.minPositionSizeUsd &&
            c.maxFundingFactorPerSecondLimit == cfg.maxFundingFactorPerSecondLimit &&
            c.skipBorrowingFeeForSmallerSide == cfg.skipBorrowingFeeForSmallerSide
        );

        f.await();
    }

    async transition setRequestExpirationBlocks(public cfg: GeneralConfig) -> Future {
        let f: Future = aleox_store_v1.aleo/setGeneralConfig(cfg);

        return finalizeSetRequestExpirationBlocks(f, cfg);
    }

    async function finalizeSetRequestExpirationBlocks(f: Future, cfg: GeneralConfig) {
        // Ensure that other configuration fields are not changed.
        let c: GeneralConfig = aleox_store_v1.aleo/generalConfig.get(0u8);
        assert(
            c.feeReceiver == cfg.feeReceiver &&
            c.holdingAddress == cfg.holdingAddress &&
            c.maxAutoCancelOrders == cfg.maxAutoCancelOrders &&
            c.minCollateralUsd == cfg.minCollateralUsd &&
            c.minPositionSizeUsd == cfg.minPositionSizeUsd &&
            c.maxFundingFactorPerSecondLimit == cfg.maxFundingFactorPerSecondLimit &&
            c.skipBorrowingFeeForSmallerSide == cfg.skipBorrowingFeeForSmallerSide
        );

        f.await();
    }

    async transition setMinCollateralUsd(public cfg: GeneralConfig) -> Future {
        let f: Future = aleox_store_v1.aleo/setGeneralConfig(cfg);

        return finalizeSetMinCollateralUsd(f, cfg);
    }

    async function finalizeSetMinCollateralUsd(f: Future, cfg: GeneralConfig) {
        // Ensure that other configuration fields are not changed.
        let c: GeneralConfig = aleox_store_v1.aleo/generalConfig.get(0u8);
        assert(
            c.feeReceiver == cfg.feeReceiver &&
            c.holdingAddress == cfg.holdingAddress &&
            c.maxAutoCancelOrders == cfg.maxAutoCancelOrders &&
            c.requestExpirationBlocks == cfg.requestExpirationBlocks &&
            c.minPositionSizeUsd == cfg.minPositionSizeUsd &&
            c.maxFundingFactorPerSecondLimit == cfg.maxFundingFactorPerSecondLimit &&
            c.skipBorrowingFeeForSmallerSide == cfg.skipBorrowingFeeForSmallerSide
        );

        f.await();
    }

    async transition setMinPositionSizeUsd(public cfg: GeneralConfig) -> Future {
        let f: Future = aleox_store_v1.aleo/setGeneralConfig(cfg);

        return finalizeSetMinPositionSizeUsd(f, cfg);
    }

    async function finalizeSetMinPositionSizeUsd(f: Future, cfg: GeneralConfig) {
        // Ensure that other configuration fields are not changed.
        let c: GeneralConfig = aleox_store_v1.aleo/generalConfig.get(0u8);
        assert(
            c.feeReceiver == cfg.feeReceiver &&
            c.holdingAddress == cfg.holdingAddress &&
            c.maxAutoCancelOrders == cfg.maxAutoCancelOrders &&
            c.requestExpirationBlocks == cfg.requestExpirationBlocks &&
            c.minCollateralUsd == cfg.minCollateralUsd &&
            c.maxFundingFactorPerSecondLimit == cfg.maxFundingFactorPerSecondLimit &&
            c.skipBorrowingFeeForSmallerSide == cfg.skipBorrowingFeeForSmallerSide
        );

        f.await();
    }

    // setMaxFundingFactorPerSecondLimit
    async transition setMaxFundingFactorPerSecLimit(public cfg: GeneralConfig) -> Future {
        let f: Future = aleox_store_v1.aleo/setGeneralConfig(cfg);

        return finalizeSetMaxFundingFactorPerSecLimit(f, cfg);
    }

    async function finalizeSetMaxFundingFactorPerSecLimit(f: Future, cfg: GeneralConfig) {
        // Ensure that other configuration fields are not changed.
        let c: GeneralConfig = aleox_store_v1.aleo/generalConfig.get(0u8);
        assert(
            c.feeReceiver == cfg.feeReceiver &&
            c.holdingAddress == cfg.holdingAddress &&
            c.maxAutoCancelOrders == cfg.maxAutoCancelOrders &&
            c.requestExpirationBlocks == cfg.requestExpirationBlocks &&
            c.minCollateralUsd == cfg.minCollateralUsd &&
            c.minPositionSizeUsd == cfg.minPositionSizeUsd &&
            c.skipBorrowingFeeForSmallerSide == cfg.skipBorrowingFeeForSmallerSide
        );

        f.await();
    }

    // setSkipBorrowingFeeForSmallerSide
    async transition setSkipBorrowingFeeForSmaller(public cfg: GeneralConfig) -> Future {
        let f: Future = aleox_store_v1.aleo/setGeneralConfig(cfg);

        return finalizeSetSkipBorrowingFeeForSmaller(f, cfg);
    }

    async function finalizeSetSkipBorrowingFeeForSmaller(f: Future, cfg: GeneralConfig) {
        // Ensure that other configuration fields are not changed.
        let c: GeneralConfig = aleox_store_v1.aleo/generalConfig.get(0u8);
        assert(
            c.feeReceiver == cfg.feeReceiver &&
            c.holdingAddress == cfg.holdingAddress &&
            c.maxAutoCancelOrders == cfg.maxAutoCancelOrders &&
            c.requestExpirationBlocks == cfg.requestExpirationBlocks &&
            c.minCollateralUsd == cfg.minCollateralUsd &&
            c.minPositionSizeUsd == cfg.minPositionSizeUsd &&
            c.maxFundingFactorPerSecondLimit == cfg.maxFundingFactorPerSecondLimit
        );

        f.await();
    }
}
