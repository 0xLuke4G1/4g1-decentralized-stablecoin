// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {BaseSetup__DSC} from "../DSCBaseSetup.t.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockTransferFailed} from "../mocks/MockTransferFailed.sol";
import {MockTransferFromFailed} from "../mocks/MockTransferFromFailed.sol";
import {MockDscTransferFromFail} from "../mocks/MockDscTransferFromFail.sol";
import {MockDscMintFail} from "../mocks/MockDscMintFail.sol";
import {MockDscCrackPrice} from "../mocks/MockDscCrackPrice.sol";
import {console} from "forge-std/Test.sol";

contract DSCEngine__Test is BaseSetup__DSC {
    function setUp() public override {
        super.setUp();
    }

    ///////////////////////
    //    Constructor   //
    /////////////////////

    // 1. Revert if tokens array's length doesn't match price feeds array's length
    function test__RevertIfArrayLengthDoesntMatch() public {
        // @dev for this test we deployed a new dscEngine
        address[] memory collTokens = new address[](1);
        address[] memory priceFeeds = new address[](3);
        DSCEngine newEngine;
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        vm.startBroadcast();
        newEngine = new DSCEngine(collTokens,priceFeeds,address(dscToken));
    }

    //////////////////////////////
    //    Deposit Collateral   //
    ////////////////////////////

    modifier approvedEngine(address from, address collateral, uint256 amount) {
        vm.prank(from);
        ERC20Mock(collateral).approve(address(dscEngine), amount);
        _;
    }

    // 1. Revert if collateral amount is 0
    function test__RevertIfCollateralAmountIsZero() public approvedEngine(USER, weth, COLLATERAL_DEPOSIT_AMOUNT) {
        vm.expectRevert(DSCEngine.DSCEngine__NeedToBeMoreThanZero.selector);
        vm.prank(USER);
        dscEngine.depositCollateral(weth, 0);
    }

    // 2. Revert if collateral is not allowed
    function test__RevertWithUnapprovedCollateral() public {
        address newToken = makeAddr("newToken");

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        vm.prank(USER);
        dscEngine.depositCollateral(newToken, COLLATERAL_DEPOSIT_AMOUNT);
    }

    // 3. Revert if collateral transfer fails
    function test__RevertIfCollateralTransferFromFails() public {
        // @dev for this we created a new engine that accepts as collateral a ERC20token that returns false on 'transfer'
        address[] memory collTokens = new address[](1);
        address[] memory priceFeeds = new address[](1);

        // @dev deploy mockTransferFailed token
        MockTransferFromFailed mockTransferFromFailed = new MockTransferFromFailed();
        mockTransferFromFailed.mint(USER, COLLATERAL_DEPOSIT_AMOUNT);

        // @dev fill the contructor arrays
        collTokens[0] = address(mockTransferFromFailed);
        priceFeeds[0] = wbtcPriceFeed; // casual addresss, we need to fit the array

        // @dev deploy new engine using mockTransferFailed token
        DSCEngine newEngine = new DSCEngine(collTokens,priceFeeds,address(dscToken));

        vm.startPrank(USER);
        mockTransferFromFailed.approve(address(newEngine), COLLATERAL_DEPOSIT_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        newEngine.depositCollateral(address(mockTransferFromFailed), COLLATERAL_DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    // 4. Should Emit Event
    function test__EmitsCollateralDepositedEvent() public approvedEngine(USER, weth, COLLATERAL_DEPOSIT_AMOUNT) {
        vm.expectEmit();
        emit CollateralDeposited(USER, weth, COLLATERAL_DEPOSIT_AMOUNT);
        vm.prank(USER);
        dscEngine.depositCollateral(weth, COLLATERAL_DEPOSIT_AMOUNT);
    }

    // 5. Users Can Deposit Collateral
    function test__CanDepositCollateral() public approvedEngine(USER, weth, COLLATERAL_DEPOSIT_AMOUNT) {
        vm.prank(USER);
        dscEngine.depositCollateral(weth, COLLATERAL_DEPOSIT_AMOUNT);

        assert(ERC20Mock(weth).balanceOf(address(dscEngine)) == COLLATERAL_DEPOSIT_AMOUNT);
        assert(dscEngine.getCollateralDepositedAmount(USER, weth) == COLLATERAL_DEPOSIT_AMOUNT);
    }

    ////////////////////
    //    Mint Dsc   //
    //////////////////

    modifier collateralDeposited(address from, address collateral, uint256 amount) {
        vm.startPrank(from);
        ERC20Mock(collateral).approve(address(dscEngine), amount);
        dscEngine.depositCollateral(collateral, amount);
        vm.stopPrank();
        _;
    }

    // 1. Revert if mint amount is 0
    function test__RevertIfMintAmountIsZero() public collateralDeposited(USER, weth, COLLATERAL_DEPOSIT_AMOUNT) {
        vm.expectRevert(DSCEngine.DSCEngine__NeedToBeMoreThanZero.selector);
        vm.prank(USER);
        dscEngine.mintDsc(0);
    }

    // 2. Revert if breaks HF
    function test__CantMintIfBreaksHealthFactor() public collateralDeposited(USER, weth, COLLATERAL_DEPOSIT_AMOUNT) {
        uint256 collateralValueInUsd = dscEngine.getAccountCollateralValue(USER);
        // we want to mint a value which is higher than the allowed one
        // since the protocol is 200% overcollateralized,
        // the max value mintable is equal to 'collateralValueInUsd / 2'

        // we have set a value that is much higher than the allowed one (2x)
        uint256 amountToMint = collateralValueInUsd;

        // @dev calculation of the broken HF that our event will display
        uint256 brokenHealthFactor = dscEngine.calculateHealthFactor(amountToMint, collateralValueInUsd);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, brokenHealthFactor));
        vm.prank(USER);
        dscEngine.mintDsc(amountToMint);
    }

    // 3. Revert if mint failed
    function test__RevertIfMintFailed() public {
        // @dev for this test a new engine and a new dsc token have been created
        // The dsc token is designed to return 'false' when minting, in order to simulate a failure.

        // @dev deploy mockDscMintFailed
        MockDscMintFail mockDscMintFail = new MockDscMintFail();

        // @dev deploy new engine that governs mockTransferFailed token
        DSCEngine newEngine = new DSCEngine(collateralTokens,priceFeedAddresses,address(mockDscMintFail));

        vm.prank(mockDscMintFail.owner());
        mockDscMintFail.transferOwnership(address(newEngine));

        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(newEngine), COLLATERAL_DEPOSIT_AMOUNT);
        newEngine.depositCollateral(weth, COLLATERAL_DEPOSIT_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        newEngine.mintDsc(DSC_MINT_AMOUNT);

        vm.stopPrank();
    }

    // 4. Users Can Mint Dsc
    function test__CanMintDsc() public collateralDeposited(USER, weth, COLLATERAL_DEPOSIT_AMOUNT) {
        vm.prank(USER);
        dscEngine.mintDsc(DSC_MINT_AMOUNT);

        (uint256 dscMinted,) = dscEngine.getAccountInformation(USER);

        assert(dscMinted == DSC_MINT_AMOUNT);
        assert(dscToken.balanceOf(USER) == DSC_MINT_AMOUNT);
    }

    ///////////////////////////////////////////
    //    Deposit Collateral and Mint DSC   //
    /////////////////////////////////////////

    // 1. Users Can Deposit Collateral And Mint Dsc in One Tx
    function test__CanDepositCollateralAndMintsDsc() public approvedEngine(USER, weth, COLLATERAL_DEPOSIT_AMOUNT) {
        vm.prank(USER);
        dscEngine.depositCollateralAndMintDsc(weth, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT);

        (uint256 dscMinted,) = dscEngine.getAccountInformation(USER);

        assert(ERC20Mock(weth).balanceOf(address(dscEngine)) == COLLATERAL_DEPOSIT_AMOUNT);
        assert(dscEngine.getCollateralDepositedAmount(USER, weth) == COLLATERAL_DEPOSIT_AMOUNT);
        assert(dscMinted == DSC_MINT_AMOUNT);
    }

    //////////////////////////////
    //    Redeem Collateral    //
    ////////////////////////////

    // 0. Revert if amount to redeem is 0.

    function test__RevertIfTryingToRedeemZro() public collateralDeposited(USER, weth, COLLATERAL_DEPOSIT_AMOUNT) {
        vm.expectRevert(DSCEngine.DSCEngine__NeedToBeMoreThanZero.selector);
        vm.prank(USER);
        dscEngine.redeemCollateral(weth, 0);
    }
    // 1. Revert if Transfer fails

    function test__RevertIfCollateralTransferFails() public {
        // @dev for this we created a new engine that accepts as collateral an ERC20token that returns false on 'transfer'
        address[] memory collTokens = new address[](1);
        address[] memory priceFeeds = new address[](1);

        // @dev deploy mockTransferFailed token
        MockTransferFailed mockTransferFailed = new MockTransferFailed();
        mockTransferFailed.mint(USER, COLLATERAL_DEPOSIT_AMOUNT * 2);

        // @dev fill the contructor arrays
        collTokens[0] = address(mockTransferFailed);
        priceFeeds[0] = wbtcPriceFeed; // casual addresss, we need to fit the array

        // @dev deploy new engine using mockTransferFailed token
        DSCEngine newEngine = new DSCEngine(collTokens,priceFeeds,address(dscToken));

        vm.startPrank(USER);
        mockTransferFailed.approve(address(newEngine), COLLATERAL_DEPOSIT_AMOUNT);
        newEngine.depositCollateral(address(mockTransferFailed), COLLATERAL_DEPOSIT_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        newEngine.redeemCollateral(address(mockTransferFailed), COLLATERAL_DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    // 2. Revert if breaks HF
    function test__CantRedeemIfBreaksHealthFactor() public collateralDeposited(USER, weth, COLLATERAL_DEPOSIT_AMOUNT) {
        uint256 collateralValueInUsd = dscEngine.getAccountCollateralValue(USER);
        uint256 amountToMint = collateralValueInUsd / 2;

        uint256 brokenHealthFactor = dscEngine.calculateHealthFactor(amountToMint, 0);
        console.log(brokenHealthFactor);

        vm.startPrank(USER);
        dscEngine.mintDsc(amountToMint);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, brokenHealthFactor));
        dscEngine.redeemCollateral(weth, COLLATERAL_DEPOSIT_AMOUNT);
    }

    // 3. Should Emit Event
    function test__EmitsCollateralRedeemedEvent() public collateralDeposited(USER, weth, COLLATERAL_DEPOSIT_AMOUNT) {
        vm.expectEmit(address(dscEngine));
        emit CollateralRedeemed(USER, USER, weth, COLLATERAL_DEPOSIT_AMOUNT);
        vm.prank(USER);
        dscEngine.redeemCollateral(weth, COLLATERAL_DEPOSIT_AMOUNT);
    }

    // 4. Users Can Redeem Collateral
    function test__CanRedeemCollateral() public collateralDeposited(USER, weth, COLLATERAL_DEPOSIT_AMOUNT) {
        uint256 startingUserBalance = ERC20Mock(weth).balanceOf(USER);

        vm.prank(USER);
        dscEngine.redeemCollateral(weth, COLLATERAL_DEPOSIT_AMOUNT);

        assert(ERC20Mock(weth).balanceOf(address(dscEngine)) == 0);
        assert(dscEngine.getCollateralDepositedAmount(USER, weth) == 0);
        assert(ERC20Mock(weth).balanceOf(USER) == startingUserBalance + COLLATERAL_DEPOSIT_AMOUNT);
    }

    ////////////////////
    //    Burn DSC   //
    //////////////////

    modifier depositedCollateralAndMintedDsc(address from, uint256 amountCollateral, uint256 amountDsc) {
        vm.startPrank(from);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(weth, amountCollateral, amountDsc);
        vm.stopPrank();
        _;
    }

    // 1. Revert if burning amount is 0
    function test__RevertIfBurnAmountIsZero()
        public
        depositedCollateralAndMintedDsc(USER, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT)
    {
        vm.expectRevert(DSCEngine.DSCEngine__NeedToBeMoreThanZero.selector);
        vm.prank(USER);
        dscEngine.burnDsc(0);
    }

    // 2. Revert if DSC transfer Fails
    function test__RevertIfDscTransferFails() public {
        // @dev for this test a new engine and a new dsc token have been created
        // The dsc token is designed to return 'false' when burning, in order to simulate a failure.

        // @dev deploy mockDscMintFailed
        MockDscTransferFromFail mockDscTransferFromFail = new MockDscTransferFromFail();

        // @dev fill the contructor arrays
        // @dev deploy new engine that governs mockTransferFailed token
        DSCEngine newEngine = new DSCEngine(collateralTokens,priceFeedAddresses,address(mockDscTransferFromFail));

        vm.prank(mockDscTransferFromFail.owner());
        mockDscTransferFromFail.transferOwnership(address(newEngine));

        // @dev deposit collateral and mint dsc
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(newEngine), COLLATERAL_DEPOSIT_AMOUNT);
        newEngine.depositCollateralAndMintDsc(weth, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        newEngine.burnDsc(DSC_BURN_AMOUNT);

        vm.stopPrank();
    }

    // 3. Revert if trying to burn more than user has
    function test__CantBurnMoreThanUserHas()
        public
        depositedCollateralAndMintedDsc(USER, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT)
    {
        vm.expectRevert();
        vm.prank(USER);
        dscEngine.burnDsc(DSC_MINT_AMOUNT + 1);
    }

    // 4. Users Can Burn Dsc
    function test__CanBurnDsc()
        public
        depositedCollateralAndMintedDsc(USER, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT)
    {
        vm.startPrank(USER);
        dscToken.approve(address(dscEngine), DSC_BURN_AMOUNT);
        dscEngine.burnDsc(DSC_BURN_AMOUNT);
        vm.stopPrank();

        (uint256 totalDscMintedByUser,) = dscEngine.getAccountInformation(USER);

        uint256 totalDscSupply = dscToken.totalSupply();

        uint256 expectedRemaniningDsc = DSC_MINT_AMOUNT - DSC_BURN_AMOUNT;
        assert(totalDscSupply == expectedRemaniningDsc);
        assert(totalDscMintedByUser == expectedRemaniningDsc);
    }

    /////////////////////////////////////
    //    Redeem Collateral for DSC   //
    ///////////////////////////////////

    function test__CanRedeemCollateralForDsc()
        public
        depositedCollateralAndMintedDsc(USER, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT)
    {
        vm.startPrank(USER);
        dscToken.approve(address(dscEngine), DSC_MINT_AMOUNT);
        dscEngine.redeemCollateralForDsc(weth, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT);
        vm.stopPrank();

        (uint256 totalDscMintedByUserAfter, uint256 collateralValueOfUserAfter) = dscEngine.getAccountInformation(USER);

        assert(ERC20Mock(weth).balanceOf(address(dscEngine)) == 0);
        assert(dscToken.balanceOf(USER) == 0);
        assert(totalDscMintedByUserAfter == 0);
        assert(collateralValueOfUserAfter == 0);
    }

    ////////////////////
    //    Liquidate  //
    //////////////////

    modifier wethPriceDropped() {
        // @dev in order to liquidate USER, his health factor must be under the minimum value
        // to make it happen, we change the answer of our MockV3Aggregator

        // collateral deposited = 5 = 10000$
        // dsc minted = 5000
        // we set a new price of 1800 to crack user's HF

        int256 newPrice = 1800e8;
        MockV3Aggregator(wethPriceFeed).updateAnswer(newPrice);
        console.log(dscEngine.getHealthFactor(USER));
        _;
    }

    // 1. Revert if debt is 0
    function test__RevertLiquidationIfDebtiIsZero()
        public
        depositedCollateralAndMintedDsc(USER, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT)
        depositedCollateralAndMintedDsc(LIQUIDATOR, COLLATERAL_DEPOSIT_AMOUNT_LIQUIDATOR, DSC_MINT_AMOUNT)
    {
        vm.expectRevert(DSCEngine.DSCEngine__NeedToBeMoreThanZero.selector);
        vm.prank(LIQUIDATOR);
        dscEngine.liquidate(weth, USER, 0);
    }

    // 2. Revert if user's HF is ok
    function test__CantLiquidateIfUserHealthFactorIsOk()
        public
        depositedCollateralAndMintedDsc(USER, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT)
        depositedCollateralAndMintedDsc(LIQUIDATOR, COLLATERAL_DEPOSIT_AMOUNT_LIQUIDATOR, DSC_MINT_AMOUNT)
    {
        vm.startPrank(LIQUIDATOR);
        dscToken.approve(address(dscEngine), DSC_BURN_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, USER, DSC_BURN_AMOUNT);
        vm.stopPrank();
    }

    // 3. Revert if users' HF not improves
    function test__RevertLiquidationIfUserHealthFactorNotImproves() public {
        // @dev to test this we have to crash the price of weth during the liquidation

        // To simulate this scenario, we deploy a new engine using a mocked dsc that updates the price of weth when burning.

        // This will emulate a scenario when during the exeution of the liquidation the price of the collateral drops,
        // in order to make USER's HF more broken.

        // @dev deploy mockDsc and newEngine
        MockDscCrackPrice mockDsc = new MockDscCrackPrice(wethPriceFeed);
        DSCEngine newEngine = new DSCEngine(collateralTokens,priceFeedAddresses,address(mockDsc));

        vm.prank(mockDsc.owner());
        mockDsc.transferOwnership(address(newEngine));

        // @dev arrange USER
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(newEngine), COLLATERAL_DEPOSIT_AMOUNT);
        newEngine.depositCollateralAndMintDsc(weth, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT);
        vm.stopPrank();

        // @dev arrange LIQUIDATOR
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wbtc).approve(address(newEngine), COLLATERAL_DEPOSIT_AMOUNT_LIQUIDATOR);
        newEngine.depositCollateralAndMintDsc(wbtc, COLLATERAL_DEPOSIT_AMOUNT_LIQUIDATOR, DSC_MINT_AMOUNT);
        vm.stopPrank();

        // @dev update weth price make liquidation possible
        int256 newPrice = 1800e8;
        MockV3Aggregator(wethPriceFeed).updateAnswer(newPrice);

        vm.startPrank(LIQUIDATOR);

        mockDsc.approve(address(newEngine), DSC_BURN_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        newEngine.liquidate(weth, USER, DSC_BURN_AMOUNT);

        vm.stopPrank();
    }

    // 4. Revert if liquidator's HF breaks
    function test__CantLiquidateIfLiquidatorHealthFactorBreaks() public {
        // @dev to test this we have to crash the price of LIQUIDATOR colleteral during the liquidation

        // To simulate this scenario, we deploy a new engine using a mocked dsc that updates the price of wbtc when burning.

        // This will emulate a scenario when during the exeution of the liquidation the price of the collateral drops,
        // in order to make the LIQUIDATOR's HF more broken.

        // @dev deploy mockDsc and newEngine
        MockDscCrackPrice mockDsc = new MockDscCrackPrice(wbtcPriceFeed);
        DSCEngine newEngine = new DSCEngine(collateralTokens,priceFeedAddresses,address(mockDsc));

        vm.prank(mockDsc.owner());
        mockDsc.transferOwnership(address(newEngine));

        // @dev arrange USER
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(newEngine), COLLATERAL_DEPOSIT_AMOUNT);
        newEngine.depositCollateralAndMintDsc(weth, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT);
        vm.stopPrank();

        // @dev arrange LIQUIDATOR
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wbtc).approve(address(newEngine), COLLATERAL_DEPOSIT_AMOUNT_LIQUIDATOR);
        newEngine.depositCollateralAndMintDsc(wbtc, COLLATERAL_DEPOSIT_AMOUNT_LIQUIDATOR, DSC_MINT_AMOUNT);
        vm.stopPrank();

        // @dev update weth price to make liquidation possible
        int256 newPrice = 1800e8;
        MockV3Aggregator(wethPriceFeed).updateAnswer(newPrice);

        // @dev calculation of the broken HF that our event will display
        uint256 brokenHealthFactor = dscEngine.calculateHealthFactor(DSC_MINT_AMOUNT, 0);

        vm.startPrank(LIQUIDATOR);

        mockDsc.approve(address(newEngine), DSC_BURN_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, brokenHealthFactor));
        newEngine.liquidate(weth, USER, DSC_BURN_AMOUNT);

        vm.stopPrank();
    }

    // 5. Can Liquidate Users
    function test__CanLiquidateUsers()
        public
        depositedCollateralAndMintedDsc(USER, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT)
        depositedCollateralAndMintedDsc(LIQUIDATOR, COLLATERAL_DEPOSIT_AMOUNT_LIQUIDATOR, DSC_MINT_AMOUNT)
        wethPriceDropped
    {
        (, uint256 collateralValueOfUserBefore) = dscEngine.getAccountInformation(USER);
        uint256 wethLiquidatorBalanceBefore = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        uint256 totalSupplyBefore = dscToken.totalSupply();

        vm.startPrank(LIQUIDATOR);
        dscToken.approve(address(dscEngine), DSC_MINT_AMOUNT);
        dscEngine.liquidate(weth, USER, DSC_MINT_AMOUNT);
        vm.stopPrank();

        (uint256 totalDscMintedByUserAfter, uint256 collateralValueOfUserAfter) = dscEngine.getAccountInformation(USER);
        uint256 wethLiquidatorBalanceAfter = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 totalSupplyAfter = dscToken.totalSupply();

        assert(totalDscMintedByUserAfter == 0 && collateralValueOfUserAfter < collateralValueOfUserBefore);
        assert(totalSupplyAfter < totalSupplyBefore);
        assert(wethLiquidatorBalanceBefore < wethLiquidatorBalanceAfter);
    }

    // 6. Can Partially Liquidate Users
    function test__CanPartiallyLiquidateUsers()
        public
        depositedCollateralAndMintedDsc(USER, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT)
        depositedCollateralAndMintedDsc(LIQUIDATOR, COLLATERAL_DEPOSIT_AMOUNT_LIQUIDATOR, DSC_MINT_AMOUNT)
        wethPriceDropped
    {
        (, uint256 collateralValueOfUserBefore) = dscEngine.getAccountInformation(USER);
        uint256 wethLiquidatorBalanceBefore = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        uint256 totalSupplyBefore = dscToken.totalSupply();

        vm.startPrank(LIQUIDATOR);

        dscToken.approve(address(dscEngine), DSC_BURN_AMOUNT);
        dscEngine.liquidate(weth, USER, DSC_BURN_AMOUNT);

        vm.stopPrank();

        (uint256 totalDscMintedByUserAfter, uint256 collateralValueOfUserAfter) = dscEngine.getAccountInformation(USER);
        uint256 wethLiquidatorBalanceAfter = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 totalSupplyAfter = dscToken.totalSupply();

        assert(totalDscMintedByUserAfter == DSC_MINT_AMOUNT - DSC_BURN_AMOUNT);
        assert(collateralValueOfUserAfter < collateralValueOfUserBefore);
        assert(totalSupplyAfter == totalSupplyBefore - DSC_BURN_AMOUNT);
        assert(wethLiquidatorBalanceBefore < wethLiquidatorBalanceAfter);
    }

    // 7. Liquidator gets collateral + 10% bonus
    function test__LiquidatorGetsRewardAndBonus()
        public
        depositedCollateralAndMintedDsc(USER, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT)
        depositedCollateralAndMintedDsc(LIQUIDATOR, COLLATERAL_DEPOSIT_AMOUNT_LIQUIDATOR, DSC_MINT_AMOUNT)
        wethPriceDropped
    {
        // want to ensure that liquidator gets collateral + 10%  bonus
        uint256 collateralToRedeemInUsd = dscEngine.getTokenAmountFromUsd(weth, DSC_MINT_AMOUNT);
        uint256 bonus = collateralToRedeemInUsd * dscEngine.getLiquidationBonus() / dscEngine.getLiquidationPrecision();

        uint256 liquidatorBalanceBefore = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        vm.startPrank(LIQUIDATOR);

        dscToken.approve(address(dscEngine), DSC_MINT_AMOUNT);
        dscEngine.liquidate(weth, USER, DSC_MINT_AMOUNT);

        vm.stopPrank();

        uint256 liquidatorBalanceAfter = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        assertEq(liquidatorBalanceAfter, liquidatorBalanceBefore + collateralToRedeemInUsd + bonus);
    }

    ////////////////////////////
    //    Getter Functions   //
    //////////////////////////

    // 0. Getters should work
    function test__GettersWorkFine() public view {
        assert(dscEngine.getCollateralTokens().length == 2);
        assert(dscEngine.getCollateralDepositedAmount(USER, weth) == 0);
        assert(dscEngine.getAccountCollateralValue(USER) == 0);
        assert(dscEngine.getLiquidationPrecision() == 100);
        assert(dscEngine.getLiquidationThreshold() == 50);
        assert(dscEngine.getLiquidationBonus() == 10);
        assert(dscEngine.getPrecision() == 1e18);
        assert(dscEngine.getCollateralTokenPriceFeed(weth) == wethPriceFeed);
        assert(dscEngine.getCollateralTokenPriceFeed(wbtc) == wbtcPriceFeed);
        assert(dscEngine.getMinHealthFactor() == 1e18);
        assert(dscEngine.getDsc() == address(dscToken));
    }

    // 1. Health Factor is Reported Properly
    function test__ReportsCorrectHealthFactor()
        public
        depositedCollateralAndMintedDsc(USER, COLLATERAL_DEPOSIT_AMOUNT, DSC_MINT_AMOUNT)
    {
        (uint256 dscMinted, uint256 collateralValueOfUser) = dscEngine.getAccountInformation(USER);
        uint256 expectedHealthFactor = ((collateralValueOfUser / 2) * 1e18) / dscMinted;

        assert(dscEngine.getHealthFactor(USER) == expectedHealthFactor);
    }
}
