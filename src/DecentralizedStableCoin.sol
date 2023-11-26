// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Luke4G1
 * @notice This is the contract meant to be governed by DSCEngine.
 * It represents an ERC20 token that can be minted and burned by the 'DSCEngine' contract.
 *
 * - Collateral: Exogenous
 * - Minting (Stability Mechanism): Algorithmic
 * - Value (Relative Stability): Anchored -> Pegged to USD
 * - Collateral Type: Crypto
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("Decentralized Stablecoin", "DSC") {}

    /**
     * @notice This function burns DSC tokens.
     * Only the owner of the contract can burn DSC tokens
     * @param _amount The amount of DSC to burn
     */

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    /**
     * @notice This function mints DSC tokens.
     * Only the owner of the contract can mint DSC tokens.
     * @param _to The address to mint DSC tokens to
     * @param _amount The amount of DSC to mint
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }

        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
