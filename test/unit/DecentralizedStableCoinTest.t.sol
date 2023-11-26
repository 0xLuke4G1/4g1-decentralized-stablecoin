// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {BaseSetup__DSC} from "../DSCBaseSetup.t.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoin__Test is BaseSetup__DSC {
    function setUp() public override {
        super.setUp();
    }

    function test__ContractInitialized() public view {
        assert(keccak256(abi.encodePacked(dscToken.name())) == keccak256(abi.encodePacked("Decentralized Stablecoin")));
        assert(keccak256(abi.encodePacked(dscToken.symbol())) == keccak256(abi.encodePacked("DSC")));
    }

    ////////////////////
    //    Mint Dsc   //
    //////////////////

    // 1. Revert if minting to Zero address
    function test__RevertIfMintingToZeroAddress() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        vm.startPrank(address(dscEngine));
        dscToken.mint(address(0), DSC_MINT_AMOUNT);
    }

    // 2. Revert if amount is 0
    function test__RevertIfMintingZeroAmount() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        vm.startPrank(address(dscEngine));
        dscToken.mint(address(dscEngine), 0);
    }

    // 3. Can Mint Dsc
    function test__CanMintDSC() public {
        vm.startPrank(address(dscEngine));
        dscToken.mint(address(dscEngine), DSC_MINT_AMOUNT);

        assert(dscToken.balanceOf(address(dscEngine)) == DSC_MINT_AMOUNT);
    }

    ////////////////////
    //    Burn Dsc   //
    //////////////////

    modifier mintedDSC() {
        vm.prank(address(dscEngine));
        dscToken.mint(address(dscEngine), DSC_MINT_AMOUNT);
        _;
    }

    // 1. Revert if amount is 0
    function test__RevertIfBurningZeroAmount() public mintedDSC {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        vm.startPrank(address(dscEngine));
        dscToken.burn(0);
    }

    // 2. Revert if balance is less than amount
    function test__RevertIfBurningAmountIsGreaterThanBalance() public mintedDSC {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        vm.startPrank(address(dscEngine));
        dscToken.burn(DSC_MINT_AMOUNT + 10);
    }

    // 3. Can Burn Dsc
    function test__CanBurnDSC() public mintedDSC {
        vm.startPrank(address(dscEngine));
        dscToken.burn(DSC_MINT_AMOUNT);

        assert(dscToken.balanceOf(address(dscEngine)) == 0);
    }
}
