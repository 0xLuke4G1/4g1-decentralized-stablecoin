// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

abstract contract BaseSetup__DSC is Test {
    DecentralizedStableCoin dscToken;
    DSCEngine dscEngine;

    address public weth;
    address public wbtc;

    address public wethPriceFeed;
    address public wbtcPriceFeed;

    address[] public collateralTokens;
    address[] public priceFeedAddresses;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant DSC_MINT_AMOUNT = 50000;
    uint256 public constant DSC_BURN_AMOUNT = 30000;

    uint256 public constant COLLATERAL_MINT_AMOUNT = 100;
    uint256 public constant COLLATERAL_DEPOSIT_AMOUNT = 50;
    uint256 public constant COLLATERAL_DEPOSIT_AMOUNT_LIQUIDATOR = 100;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    function setUp() public virtual {
        HelperConfig config;
        DeployDSC deployer = new DeployDSC();

        (dscToken, dscEngine, config) = deployer.run();

        (wethPriceFeed, wbtcPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        collateralTokens.push(weth);
        collateralTokens.push(wbtc);
        priceFeedAddresses.push(wethPriceFeed);
        priceFeedAddresses.push(wbtcPriceFeed);

        ERC20Mock(weth).mint(USER, COLLATERAL_MINT_AMOUNT);
        ERC20Mock(wbtc).mint(USER, COLLATERAL_MINT_AMOUNT);

        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_MINT_AMOUNT);
        ERC20Mock(wbtc).mint(LIQUIDATOR, COLLATERAL_MINT_AMOUNT);
    }
}
