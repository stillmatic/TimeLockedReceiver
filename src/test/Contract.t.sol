// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {DSTest} from "ds-test/test.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Hevm} from "./utils/Hevm.sol";

import {TimelockedFundsReceiver} from "./../TimelockedFundsReceiver.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract ContractTest is DSTest {
    Hevm internal immutable hevm = Hevm(HEVM_ADDRESS);
    using SafeMath for uint256;

    Utilities internal utils;
    TimelockedFundsReceiver internal tlfr;
    address payable[] internal users;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);
        address payable alice = users[0];
        hevm.prank(alice);
        hevm.warp(100);
        tlfr = new TimelockedFundsReceiver(1000, 0);
    }

    function testSetup() public {
        assertEq(tlfr.owner(), users[0]);
        assertEq(tlfr.calculateRate(10000), 0);
        assertEq(tlfr.createdAt(), 100);
    }

    function testTransferOwnership() public {
        address payable alice = users[0];
        address payable bob = users[1];
        hevm.prank(bob);
        hevm.expectRevert("must be contract owner");
        tlfr.transferOwnership(bob);
        hevm.prank(alice);
        tlfr.transferOwnership(bob);
        hevm.expectRevert("must be contract owner");
        tlfr.transferOwnership(bob);
        hevm.prank(bob);
        tlfr.transferOwnership(alice);
    }

    function testFundAccount() public {
        address payable alice = users[0];
        address payable t = payable(address(tlfr));
        hevm.deal(alice, 10000);
        hevm.prank(alice);
        (bool sent, ) = t.call{value: 100}("");
        assertTrue(sent);
    }

    function testFinalRateWithFuzz(uint256 x) public {
        hevm.warp(1100);
        assertEq(tlfr.calculateRate(x), x);
    }

    function testIntermediateRateWithFuzz(uint256 x) public {
        hevm.warp(600);
        uint256 val = tlfr.calculateRate(x);
        console.log(val);
        assertEq(val, x.div(2));
    }
}
