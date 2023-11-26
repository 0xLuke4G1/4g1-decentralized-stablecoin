// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {BaseSetup__DSC} from "../DSCBaseSetup.t.sol";
import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "..//../src/DscEngine.sol";
import {DecentralizedStableCoin} from "..//../src/DecentralizedStableCoin.sol";
import {Handler} from "./Handler.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariants is StdInvariant, BaseSetup__DSC {
    Handler handler;

    function setUp() public override {
        super.setUp();
        handler = new Handler(address(dscEngine), address(dscToken));
        targetContract(address(handler));
    }

    // What are the Invariants of the system?

    // Invariants : properties that the system should always hold

    // 1. The total value of deposited collateral has to be greater than total DSC minted.
    // 2. Getters should always work (this is an evergreen invariant)

    function invariant__TotalCollateralMustAlwaysBeGreaterThanTotalDebt() public view {
        uint256 dscTotalSyupply = dscToken.totalSupply();

        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("WETH deposited: $", wethValue);
        console.log("WBTC deposited: $", wbtcValue);
        console.log("total DSC supply: $", dscTotalSyupply);

        assert(wethValue + wbtcValue >= dscTotalSyupply);
    }

    function invariant__GettersAlwaysWorking() public view {
        dscEngine.getCollateralTokens();
        dscEngine.getPrecision();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationPrecision();
        dscEngine.getLiquidationThreshold();
        dscEngine.getMinHealthFactor();
        dscEngine.getDsc();
    }
}
