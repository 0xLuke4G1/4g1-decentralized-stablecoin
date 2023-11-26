// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockTransferFromFailed is ERC20 {
    constructor() ERC20("MockTransferFailed", "MTFF") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        return false;
    }
}
