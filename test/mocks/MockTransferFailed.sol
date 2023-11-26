// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockTransferFailed is ERC20 {
    constructor() ERC20("MockTransferFailed", "MTFF") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        return false;
    }
}
