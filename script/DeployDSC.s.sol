// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses; // @dev collateral tokens
    address[] public priceFeedAddresses; // @dev price feed addresses

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        // @dev get data from helper config
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        // @dev collateral set up
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        // deploy DSC Token contract
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        // deploy DSCEngine contract
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        // @dev transfer DSC ownership to the DSCEngine contract
        dsc.transferOwnership(address(engine));

        vm.stopBroadcast();

        return (dsc, engine, config);
    }
}
