// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Luke4G1
 *
 * The system is designed to be as minimal as possible, and have the tokens mantain a 1 token == $1 peg.
 *
 * This is a stablecoin with the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algoritmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees and was only backed by WETH and WBTC.
 *
 * @notice The system should always be 200% over-collateralized.
 *
 * @notice This contract is the core of the DSC System.
 * It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 *
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system.
 *
 */

contract DSCEngine is ReentrancyGuard {
    ////////////////
    //  ERRORS   //
    //////////////
    error DSCEngine__NeedToBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ///////////////
    //  TYPES   //
    //////////////

    using OracleLib for AggregatorV3Interface;

    ///////////////////////////
    //    STATE VARIABLES   //
    /////////////////////////

    DecentralizedStableCoin private immutable i_dsc; // DSC token address

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means users should always be 2x over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // BONUS percentage for liquidation
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // minimum Health Factor value
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    // @dev mapping of token address to price feed address
    mapping(address token => address priceFeed) private s_priceFeeds;
    // @dev mapping of user to amount of collateral tokens deposited
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    // @dev mapping of user to amount of DSC minted
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens; // @dev tokens accepted as collateral

    ////////////////
    //  EVENTS   //
    //////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ///////////////////
    //  MODIFIERS   //
    /////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert DSCEngine__NeedToBeMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ////////////////////
    //  FUNCTIONS    //
    //////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        // @dev set collateral tokens and oracle price feeds
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        // @dev set DSC address
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////
    //   External FUNCTIONS  //
    //////////////////////////

    /**
     *
     * @param tokenCollateralAddress The address of ERC20 collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of DSC to mint
     * @notice This function allows users to deposit collateral and mint DSC in one transaction.
     * @notice Sender must approve DSCEngine before calling this function.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @param tokenCollateralAddress The address of ERC20 collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     * @notice This function allow users to deposit collateral into the protocol.
     * @notice Sender must approve DSCEngine before calling this function.
     * @dev Follows CEI: Cecks, Effects, Interactions.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // @dev update state an emit event
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // @dev transfer collateral to the DSCEngine
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The address of ERC20 collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * @notice This function allows users to burn DSC and redeem underlying collateral in one transaction.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     * @param tokenCollateralAddress The address of ERC20 collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @notice This function allows users to redeem deposited collateral.
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender); // @dev revert if HF breaks
    }

    /**
     * @param amountDscToMint The amount of DSC to mint
     * @notice This function allows user to mint DSC.
     * @dev Follows CEI: Cecks, Effects, Interactions.
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        // @dev update state
        s_DSCMinted[msg.sender] += amountDscToMint;

        // @dev revert if HF breaks
        _revertIfHealthFactorIsBroken(msg.sender);

        // @dev mint DSC
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     *
     * @param amountDscToBurn The amount of DSC to burn
     * @notice This function allows users to burn their DSC.
     */
    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // @dev revert if HF breaks
    }

    /**
     * @param collateral The address of ERC20 collateral token to liquidate
     * @param user The user who has broken the Health Factor (it should be below `MIN_HEALTH_FACTOR`)
     * @param debtToCover The amount of DSC to burn in order to improve `user` Health Factor
     *
     * @notice Users can be partially liquidated.
     * @notice If you liquidate a user, you will get a 10% liquidation Bonus on the debt covered.
     * @notice This function working assumes that the protocol will be roughly 150% overcollateralized.
     * @notice A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * @dev Follows CEI: Cecks, Effects, Interactions.
     */

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // @dev chek the starting `user` HF and revert if it's healthy
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // Since 1 DSC = 1$
        // If covering 100 DSC, liquidator will get 100$ of `collateral`, plus a 10% bonus

        // So we are giving the liquidator $110 of collateral for 100 DSC

        // We should implmement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amoutnts into a treasury

        // @dev get the collateral amount and calculate bonus and total collateral to redeem
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        // @dev redeem collateral and burn DSC
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);

        // @dev this should never happen, but just in case
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        // @dev revert if liquidator's HF breaks
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////////////////jj////
    //  Private and Internal FUNCTIONS  //
    /////////////////////////////////////

    /**
     * @dev Low-level internal function for burning DSC.
     */

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        // @dev update state and transfer DSC to the engine
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);

        // This conditional is hypothetical unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        // @dev burn DSC
        i_dsc.burn(amountDscToBurn);

        // @dev revert if HF breaks
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param from The address of the user from which the collareral is taken
     * @param to The address of the user that will take the collateral
     * @param tokenCollateralAddress The address of ERC20 collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @dev Low-level internal function for redeeming DSC.
     */
    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        internal
    {
        // @dev update state and emit event
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        // @dev transfer collateral
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
    }

    /**
     * @param user Address to get information about
     * @notice Returns the total DSC minted by `user` and the $USD value of its deposited collateral.
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     *
     * @notice Calculates the Health Factor given `totalDscMinted` and `collateralValueInUsd`.
     *
     * The Health Factor represents how close is a user to liquidation.
     * If it's below `MIN_HEALTH_FACTOR` user can be liquidated.
     */

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max; // @dev if a user has no DSC minted, he is considered healthy regardless

        // Since the protocol is 200% Overcollateralized:
        //
        //            (Collateral in USD * 0.5) * 1e18
        //        ----------------------------------------
        //                Total DSC tokens minted
        //
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @notice Returns the Health Factor of the given `user`.
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /**
     * @dev Checks the Health Factor of `user` and reverts if it's below `MIN_HEALTH_FACTOR`.
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /////////////////////////////////////////
    //  Public & External View FUNCTIONS  //
    ///////////////////////////////////////

    /**
     * @notice Calculates Health Factor given `totalDscMinted` and `collateralValueInUsd`.
     */
    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /**
     * @notice Returns the amount of `token` given its $USD value.
     * @param token The address of the collateral token
     * @param usdAmountInWei The USD value of the token
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     * @notice Returns the total value of the deposited collateral from the given `user`.
     */

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // @dev loops trough the list of collateral addresses,
        // checks the amount of collateral deposited for each token address
        // and get its value in USD
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice Returns the $USD value of the given `amount` of `token`.
     * @dev Uses Chainlinlk Data Feeds to retrieve the current $USD price of the collateral tokens.
     */

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleChecksLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // example (1600e8 * 1e10 * 2)/ 1e18 = 3200 $
    }

    /**
     * @notice Returns `totalDscMinted` and `collateralValueInUsd` of `user`.
     * @param user The address of the user to get information about
     */
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    /**
     * @notice Returns the Health Factor of the given `user`.
     */
    function getHealthFactor(address user) external view returns (uint256 helthFactor) {
        helthFactor = _healthFactor(user);
    }

    /**
     * @notice Returns the DSC Token address.
     */
    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    /**
     * @notice Returns the `LIQUIDATION_PRECISION`.
     */
    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    /**
     * @notice Returns the `LIQUIDATION_THRESHOLD`.
     */
    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice Returns the `LIQUIDATION_BONUS`.
     */
    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    /**
     * @notice Returns the `MIN_HEALTH_FACTOR` value.
     */
    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    /**
     * @notice Returns the amount of `token` deposited by `user`.
     */
    function getCollateralDepositedAmount(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    /**
     * @notice Returns the list of collateral tokens approved by the system.
     */
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    /**
     * @notice Returns the Price Feed contract address for the given `token`.
     */
    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
