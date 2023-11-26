// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {MockV3Aggregator} from "../mocks/Mockv3Aggregator.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract OracleLib__Test is Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator public priceFeed;
    uint8 public DECIMALS = 8;
    int256 public INITIAL_PRICE = 2000e8;

    function setUp() public {
        priceFeed = new MockV3Aggregator(DECIMALS,INITIAL_PRICE);
    }

    // 0. Can get `TIMEOUT`
    function test__CanGetTimeout() public {
        uint256 timeout = AggregatorV3Interface(address(priceFeed)).getTimeout();
        assertEq(timeout, 3 hours);
    }

    // 1. Revert if exceeded `TIMEOUT`
    function test__RevertIfTimeoutExceeded() public {
        uint256 actualTimestamp = block.timestamp;
        vm.warp(actualTimestamp + 10801);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(priceFeed)).staleChecksLatestRoundData();
    }

    // 2. Returns Price
    function test__CanGetPrice() public {
        (, int256 price,,,) = AggregatorV3Interface(address(priceFeed)).staleChecksLatestRoundData();
        assertEq(price, INITIAL_PRICE);
    }
}
