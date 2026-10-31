// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Plain 6-decimal mock token with open mint.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Mock that reverts any transfer whose recipient is blocked (USDC-blocklist style).
contract BlockableERC20 is ERC20 {
    mapping(address => bool) public blocked;

    constructor() ERC20("Blockable USDC", "bUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setBlocked(address who, bool b) external {
        blocked[who] = b;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(!blocked[to], "blocked");
        require(!blocked[from], "blocked");
        super._update(from, to, value);
    }
}

/// @dev Mock that burns 1% of every transfer (fee-on-transfer).
contract FeeOnTransferERC20 is ERC20 {
    constructor() ERC20("Fee USDC", "fUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value / 100;
            if (fee != 0) {
                super._update(from, address(0), fee); // burn the fee
            }
            value -= fee;
        }
        super._update(from, to, value);
    }
}
