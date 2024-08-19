program aleox_timelock_v1.aleo {
    mapping timelockDelayBlocks: u8 => u32; // 0u8 => timelock delay in blocks

    mapping pendingActions: field => u32; // action hash => block number

    mapping pendingActionCount: u8 => u32; // 0u8 => pending action count

    mapping pendingActionList: u32 => field; // index => action hash

    mapping pendingActionByHash: field => u32; // action hash => index

    async transition setTimelockDelayBlocks(public blocks: u32) -> Future {
        return finalizeSetTimelockDelayBlocks(blocks);
    }

    async function finalizeSetTimelockDelayBlocks(blocks: u32) {
        timelockDelayBlocks.set(0u8, blocks);
    }

    async transition signalPendingAction(public actionHash: field) -> Future {
        return finalizeSignalPendingAction(actionHash);
    }

    async function finalizeSignalPendingAction(actionHash: field) {
        assert(!pendingActions.contains(actionHash));
        pendingActions.set(actionHash, block.height + timelockDelayBlocks.get(0u8));

        let index: u32 = pendingActionCount.get_or_use(0u8, 0u32);
        pendingActionCount.set(0u8, index + 1u32);

        pendingActionList.set(index, actionHash);
        pendingActionByHash.set(actionHash, index);
    }

    async transition validateAndClearAction(public actionHash: field) -> Future {
        return finalizeClearAction(actionHash, true);
    }

    async transition cancelAction(public actionHash: field) -> Future {
        return finalizeClearAction(actionHash, false);
    }

    async function finalizeClearAction(actionHash: field, validate: bool) {
        if (validate) {
            assert(pendingActions.get(actionHash) <= block.height);
        } else {
            assert(pendingActions.contains(actionHash));
        }
        pendingActions.remove(actionHash);

        let index: u32 = pendingActionByHash.get(actionHash);
        assert_eq(pendingActionList.get(index), actionHash);

        let lastIndex: u32 = pendingActionCount.get(0u8) - 1u32;
        pendingActionCount.set(0u8, lastIndex);

        // If the action to cancel is not the last one, move the last action to the index of the action to cancel.
        if (index < lastIndex) {
            let lastActionHash: field = pendingActionList.get(lastIndex);
            pendingActionList.set(index, lastActionHash);
            pendingActionByHash.set(lastActionHash, index);
        }
        // Remove the last action.
        pendingActionList.remove(lastIndex);
        pendingActionByHash.remove(actionHash);
    }
}
