import aleox_oracle_v1.aleo;

program aleox_oracle_signers_v1.aleo {
    mapping signerCount: u8 => u32; // 0u8 => signer count
    mapping signerList: u32 => address; // index => signer address
    mapping signerByAddress: address => u32; // signer address => index

    async transition addSigner(public signer: address) -> Future {
        return finalizeAddSigner(signer);
    }

    async function finalizeAddSigner(signer: address) {
        assert(!signerByAddress.contains(signer));

        let index: u32 = signerCount.get_or_use(0u8, 0u32);
        signerCount.set(0u8, index + 1u32);

        signerList.set(index, signer);
        signerByAddress.set(signer, index);
    }

    async transition removeSigner(public signer: address) -> Future {
        return finalizeRemoveSigner(signer);
    }

    async function finalizeRemoveSigner(signer: address) {
        assert(signerByAddress.contains(signer));

        let index: u32 = signerByAddress.get(signer);
        assert_eq(signerList.get(index), signer);

        let lastIndex: u32 = signerCount.get(0u8) - 1u32;
        signerCount.set(0u8, lastIndex);

        // If the signer is not the last one, move the last signer to the removed signer's position.
        if (index < lastIndex) {
            let lastSigner: address = signerList.get(lastIndex);
            signerList.set(index, lastSigner);
            signerByAddress.set(lastSigner, index);
        }
        // Remove the last signer.
        signerList.remove(lastIndex);
        signerByAddress.remove(signer);
    }

    struct Report {
        token: field,
        oracleBlock: u32,
        oracleTimestamp: u64,
        minPrices: [u128; 3],
        maxPrices: [u128; 3],
        signatures: [signature; 3],
    }

    struct Reports {
        signers: [address; 3],
        reports: [Report; 6],
    }

    struct SignerReport {
        token: field,
        oracleBlock: u32,
        oracleTimestamp: u64,
        minPrice: u128,
        maxPrice: u128,
    }

    async transition validatePrices(public params: Reports) -> (Prices, Future) {
        let reports: [Report; 6] = params.reports;
        let signers: [address; 3] = params.signers;

        // Validate that the signers are unique.
        assert(signers[0u8] != signers[1u8] && signers[0u8] != signers[2u8] && signers[1u8] != signers[2u8]);

        let maxOracleBlock: u32 = 0u32;
        for i: u8 in 0u8..6u8 {
            let report: Report = reports[i];

            let oracleBlock: u32 = report.oracleBlock;
            maxOracleBlock = maxOracleBlock > oracleBlock ? maxOracleBlock : oracleBlock;

            for j: u8 in 0u8..3u8 {
                let signer: address = signers[j];
                let hash: field = BHP256::hash_to_field(SignerReport {
                    token: report.token,
                    oracleBlock: oracleBlock,
                    oracleTimestamp: report.oracleTimestamp,
                    minPrice: report.minPrices[j],
                    maxPrice: report.maxPrices[j],
                });
                assert(report.signatures[j].verify(signer, hash));
            }

            // Validate that minPrices/maxPrices are sorted in ascending order.
            assert(report.minPrices[0u8] <= report.minPrices[1u8]);
            assert(report.minPrices[1u8] <= report.minPrices[2u8]);
            assert(report.maxPrices[0u8] <= report.maxPrices[1u8]);
            assert(report.maxPrices[1u8] <= report.maxPrices[2u8]);
        }

        let tokenPrices: [TokenPrice; 6] = [
            TokenPrice { token: reports[0u8].token, min: getMedian(reports[0u8].minPrices), max: getMedian(reports[0u8].maxPrices), block_: reports[0u8].oracleBlock },
            TokenPrice { token: reports[1u8].token, min: getMedian(reports[1u8].minPrices), max: getMedian(reports[1u8].maxPrices), block_: reports[1u8].oracleBlock },
            TokenPrice { token: reports[2u8].token, min: getMedian(reports[2u8].minPrices), max: getMedian(reports[2u8].maxPrices), block_: reports[2u8].oracleBlock },
            TokenPrice { token: reports[3u8].token, min: getMedian(reports[3u8].minPrices), max: getMedian(reports[3u8].maxPrices), block_: reports[3u8].oracleBlock },
            TokenPrice { token: reports[4u8].token, min: getMedian(reports[4u8].minPrices), max: getMedian(reports[4u8].maxPrices), block_: reports[4u8].oracleBlock },
            TokenPrice { token: reports[5u8].token, min: getMedian(reports[5u8].minPrices), max: getMedian(reports[5u8].maxPrices), block_: reports[5u8].oracleBlock },
        ];

        let prices: Prices = aleox_oracle_v1.aleo/getPrices(tokenPrices);

        return (prices, finalizeValidatePrices(signers, maxOracleBlock));
    }

    async function finalizeValidatePrices(signers: [address; 3], oracleBlock: u32) {
        for i: u8 in 0u8..3u8 {
            assert(signerByAddress.contains(signers[i]));
        }
        assert(oracleBlock < block.height);
    }

    inline getMedian(prices: [u128; 3]) -> u128 {
        return prices[1u8];
    }
}
