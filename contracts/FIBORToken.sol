// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FIBORToken
 * @notice The native token of the FIBOR protocol.
 *
 *   - Fixed supply of 1 billion FIBOR minted at deploy.
 *   - Governance token: vote on protocol parameters, fee rates, treasury.
 *   - No inflation, no additional minting.
 */
contract FIBORToken is ERC20, Ownable {

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether; // 1B tokens

    constructor(address _treasury) ERC20("FIBOR", "FIBOR") Ownable(msg.sender) {
        _mint(_treasury, MAX_SUPPLY);
    }
}
