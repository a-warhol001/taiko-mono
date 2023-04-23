// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.18;

import {AddressResolver} from "../../common/AddressResolver.sol";
import {LibMath} from "../../libs/LibMath.sol";
import {
    SafeCastUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {TaikoData} from "../TaikoData.sol";
import {TaikoToken} from "../TaikoToken.sol";
import {
    LibFixedPointMath as Math
} from "../../thirdparty/LibFixedPointMath.sol";

library LibTokenomics {
    using LibMath for uint256;

    error L1_INSUFFICIENT_TOKEN();
    error L1_INVALID_PARAM();

    function withdrawTaikoToken(
        TaikoData.State storage state,
        AddressResolver resolver,
        uint256 amount
    ) internal {
        uint256 balance = state.taikoTokenBalances[msg.sender];
        if (balance < amount) revert L1_INSUFFICIENT_TOKEN();

        unchecked {
            state.taikoTokenBalances[msg.sender] -= amount;
        }

        TaikoToken(resolver.resolve("taiko_token", false)).mint(
            msg.sender,
            amount
        );
    }

    function depositTaikoToken(
        TaikoData.State storage state,
        AddressResolver resolver,
        uint256 amount
    ) internal {
        if (amount > 0) {
            TaikoToken(resolver.resolve("taiko_token", false)).burn(
                msg.sender,
                amount
            );
            state.taikoTokenBalances[msg.sender] += amount;
        }
    }

    /**
     * Update the baseFee for proofs
     *
     * @param state The actual state data
     * @param proofTime The actual proof time
     * @return reward Amount of reward given - if blocked is proved and verified
     */
    function getProofReward(
        TaikoData.State storage state,
        uint64 proofTime
    ) internal view returns (uint64) {
        uint64 numBlocksUnverified = state.numBlocks -
            state.lastVerifiedBlockId -
            1;

        if (numBlocksUnverified == 0) {
            return 0;
        } else {
            uint64 totalNumProvingSeconds = uint64(
                uint256(numBlocksUnverified) *
                    block.timestamp -
                    state.accProposedAt
            );
            // If block timestamp is equal to state.accProposedAt (not really, but theoretically possible)
            // there will be division by 0 error
            if (totalNumProvingSeconds == 0) {
                totalNumProvingSeconds = 1;
            }

            return
                uint64(
                    (uint256(state.accBlockFees) * proofTime) /
                        totalNumProvingSeconds
                );
        }
    }

    /**
     * Calculate the newProofTimeIssued and newBasefee
     *
     * @param state The actual state data
     * @param config Config data
     * @param proofTime The actual proof time
     * @return newProofTimeIssued Accumulated proof time
     * @return newBasefee New basefee
     */
    function getNewBaseFeeandProofTimeIssued(
        TaikoData.State storage state,
        TaikoData.Config memory config,
        uint64 proofTime
    ) internal view returns (uint64 newProofTimeIssued, uint64 newBasefee) {
        newProofTimeIssued = (state.proofTimeIssued > config.proofTimeTarget)
            ? state.proofTimeIssued - config.proofTimeTarget
            : uint64(0);
        newProofTimeIssued += proofTime;

        uint256 x = (newProofTimeIssued * Math.SCALING_FACTOR_1E18) /
            (config.proofTimeTarget * config.adjustmentQuotient);

        if (Math.MAX_EXP_INPUT <= x) {
            x = Math.MAX_EXP_INPUT;
        }

        uint256 result = (uint256(Math.exp(int256(x))) /
            Math.SCALING_FACTOR_1E18) /
            (config.proofTimeTarget * config.adjustmentQuotient);

        newBasefee = uint64(result.min(type(uint64).max));
    }

    /**
     * Calculating the exponential smoothened with (target/quotient)
     *
     * @param value Result of cumulativeProofTime
     * @param target Target proof time
     * @param quotient Quotient
     * @return uint64 Calculated new basefee
     */
    function _calcBasefee(
        uint256 value,
        uint256 target,
        uint256 quotient
    ) private pure returns (uint64) {
        uint256 x = (value * Math.SCALING_FACTOR_1E18) / (target * quotient);

        if (Math.MAX_EXP_INPUT <= x) {
            x = Math.MAX_EXP_INPUT;
        }

        uint256 result = (uint256(Math.exp(int256(x))) /
            Math.SCALING_FACTOR_1E18) / (target * quotient);

        if (result > type(uint64).max) return type(uint64).max;

        return uint64(result);
    }
}
