// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

/**
 * @notice Helper Smart Contract for configuring constructor data depending on the network.
 */

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    // @dev private key used for anvil deployments
    uint256 public DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /////// MOCK CONFIG VARIABLES
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 10000e8;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // Chainlink Price Feed for WETH/USD
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, // Chainlink Price Feed for WBTC/USD
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, // WETH address
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063, // WBTC address
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        // @dev for foundry local blockchain (anvil) we need to deploy mocks of Collateral Tokens and Price Feeds
        vm.startBroadcast();

        // WETH setup
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH ", "WETH", msg.sender,1000e8);

        // WBTC setup
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock btcMock = new ERC20Mock("WBTC ", "WBTC", msg.sender,1000e8);

        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed), // Mock Chainlink Price Feed for WETH/USD
            wbtcUsdPriceFeed: address(btcUsdPriceFeed), // Mock Chainlink Price Feed for WBTC/USD
            weth: address(wethMock), // Mock WETH address
            wbtc: address(btcMock), // Mock WBTC address
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}
