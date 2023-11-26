// SPDX-LICENSE-IDENTIFIER: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Luke4G1
 * @notice  This library is used to check the Chainlink Oracle for stale data.
 * If a price is stale, the function will revert, and render the DSCEngine unusable - this is by design.
 * We want the DSCEngine to freeze if price become stale.
 *
 */

library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    /**
     *
     * @param priceFeed The Chainlink Price Feed to get data from
     * @notice This function checks the price of an asset from its Chainlink Price Feed contract, and returns its value.
     * @notice Reverts if the last time price was updated was more than `TIMEOUT`.
     * @dev Using Chainlink Data Feeds to get assets' price.
     */

    function staleChecksLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        // @dev get the price from the Price Feed Contract
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answerInRound) =
            priceFeed.latestRoundData();

        // calculate seconds passed since the price has been updated for the last time
        uint256 secondsSince = block.timestamp - updatedAt;

        // revert if price updated more than 3 hours ago
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();

        return (roundId, answer, startedAt, updatedAt, answerInRound);
    }

    function getTimeout(AggregatorV3Interface priceFeed) public pure returns (uint256) {
        return TIMEOUT;
    }
}
