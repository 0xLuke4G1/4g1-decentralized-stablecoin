// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "..//../src/DscEngine.sol";
import {DecentralizedStableCoin} from "..//../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/Mockv3Aggregator.sol";

contract Handler is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dscToken;

    address[] public collateralTokens;

    uint256 public MAX_DEPOSIT = type(uint96).max;
    uint256 public MINIMUM_HEALTH_FACTOR;

    constructor(address _dscEngine, address _dsc) {
        dscEngine = DSCEngine(_dscEngine);
        dscToken = DecentralizedStableCoin(_dsc);

        collateralTokens = dscEngine.getCollateralTokens();
        MINIMUM_HEALTH_FACTOR = dscEngine.getMinHealthFactor();
    }

    ///////////////////////////////////////////
    //    Deposit Collateral and Mint DSC   //
    /////////////////////////////////////////

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT);

        ERC20Mock(collateral).mint(msg.sender, amountCollateral);

        vm.startPrank(msg.sender);
        ERC20Mock(collateral).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(collateral, amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 amountDsc) public {
        (uint256 dscMinted, uint256 collateralValue) = dscEngine.getAccountInformation(msg.sender);

        uint256 maxAmountMintable = (collateralValue / 2) - dscMinted;
        amountDsc = bound(amountDsc, 0, maxAmountMintable);

        if (amountDsc == 0) return;

        vm.prank(msg.sender);
        dscEngine.mintDsc(amountDsc);
    }

    /////////////////////////////
    //    Redeem Collateral   //
    ///////////////////////////

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        // select collateral token to redeem and bound the amount
        address collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxAmountRedeemable = dscEngine.getCollateralDepositedAmount(msg.sender, collateral);

        amount = bound(amount, 0, maxAmountRedeemable);
        if (amount == 0) return;

        vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(collateral, amount);
        vm.stopPrank();
    }

    ////////////////////
    //    Burn Dsc   //
    //////////////////

    function burnDsc(uint256 amountDsc) public {
        // @dev bound the max amount to the total dsc mitned from the sender
        (uint256 maxAmountBurnable,) = dscEngine.getAccountInformation(msg.sender);

        amountDsc = bound(amountDsc, 0, maxAmountBurnable);
        if (maxAmountBurnable == 0) return;

        vm.startPrank(msg.sender);
        dscToken.approve(address(dscEngine), amountDsc);
        dscEngine.burnDsc(amountDsc);
        vm.stopPrank();
    }

    /////////////////////
    //    Liquidate   //
    ///////////////////

    function liquidate(uint256 collateralSeed, address accounToLiquidate, uint256 amountDsc) public {
        if (
            dscEngine.getHealthFactor(accounToLiquidate) < MINIMUM_HEALTH_FACTOR
                || dscEngine.getHealthFactor(msg.sender) > MINIMUM_HEALTH_FACTOR
        ) return;

        address collateral = _getCollateralFromSeed(collateralSeed);

        (uint256 maxDscToLiquidate,) = dscEngine.getAccountInformation(accounToLiquidate);
        (uint256 dscMintedByLiquidator,) = dscEngine.getAccountInformation(msg.sender);

        amountDsc = bound(amountDsc, 0, maxDscToLiquidate);
        // return if amount to liquidate is 0 or if liquidator can't pay debt
        if (amountDsc == 0 || dscMintedByLiquidator < amountDsc) return;

        vm.startPrank(msg.sender);
        dscToken.approve(address(dscEngine), amountDsc);
        dscEngine.liquidate(accounToLiquidate, collateral, amountDsc);
        vm.stopPrank();
    }

    ////////////////////////
    //    Update Price   //
    //////////////////////

    function updateCollateralPrice(uint256 collateralSeed, uint96 value) public {
        address collateral = _getCollateralFromSeed(collateralSeed);
        address priceFeed = dscEngine.getCollateralTokenPriceFeed(collateral);

        MockV3Aggregator(priceFeed).updateAnswer(int256(uint256(value)));
    }

    ///////////////////
    //    Helpers   //
    /////////////////

    function _getCollateralFromSeed(uint256 seed) internal view returns (address) {
        return collateralTokens[seed % collateralTokens.length];
    }
}
