// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/FIBORToken.sol";

contract FIBORTokenTest is Test {
    FIBORToken token;
    address treasury = address(0xBEEF);

    function setUp() public {
        token = new FIBORToken(treasury);
    }

    function test_totalSupply() public view {
        assertEq(token.totalSupply(), 1_000_000_000 ether);
    }

    function test_treasuryReceivesAll() public view {
        assertEq(token.balanceOf(treasury), 1_000_000_000 ether);
    }

    function test_transfer() public {
        vm.prank(treasury);
        token.transfer(address(1), 100 ether);
        assertEq(token.balanceOf(address(1)), 100 ether);
        assertEq(token.balanceOf(treasury), 1_000_000_000 ether - 100 ether);
    }

    function test_nameAndSymbol() public view {
        assertEq(token.name(), "FIBOR");
        assertEq(token.symbol(), "FIBOR");
    }
}
