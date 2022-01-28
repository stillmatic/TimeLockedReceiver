// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {DSTest} from "ds-test/test.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Hevm} from "./utils/Hevm.sol";

import {TimelockedFundsReceiver} from "./../TimelockedFundsReceiver.sol";
import {TimelockedFundsReceiverFactory} from "./../TimelockedFundsReceiverFactory.sol";

import {MockERC20} from "./utils/MockERC20.sol";
import {Utils} from "../Utils.sol";

contract ContractTest is DSTest {
    Hevm internal immutable hevm = Hevm(HEVM_ADDRESS);

    Utilities internal utils;
    TimelockedFundsReceiverFactory internal factory;
    TimelockedFundsReceiver internal global;
    TimelockedFundsReceiver internal tlfr;
    TimelockedFundsReceiver internal tlfr2;
    MockERC20 internal xyz;
    MockERC20 internal abc;
    address payable[] internal users;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);
        address payable alice = users[0];
        hevm.startPrank(alice);
        hevm.warp(100);
        global = new TimelockedFundsReceiver();
        factory = new TimelockedFundsReceiverFactory(global);
        tlfr = factory.createReceiver(1000, 0, alice);
        tlfr2 = factory.createReceiver(1000, 250, alice);

        xyz = new MockERC20("test coin", "XYZ", alice, 1000);
        abc = new MockERC20("another test", "ABC", alice, 1000);
    }

    function testGasChild() public {
        uint256 startGas = gasleft();
        factory.createReceiver(1000, 500, users[0]);
        uint256 endGas = gasleft();
        uint256 usedGas = startGas - endGas;
        console.log("Deploy gas", usedGas);
        // should be ~129945
        assertLt(usedGas, 150_000);
    }

    function testGasWithdrawWrapped() public {
        hevm.startPrank(users[0]);
        xyz.approve(address(tlfr), 1000);
        xyz.transfer(address(tlfr), 1000);
        hevm.warp(600);
        uint256 startGas = gasleft();
        tlfr.claimWrapped(address(xyz), 500);
        uint256 endGas = gasleft();
        uint256 usedGas = startGas - endGas;
        console.log("Wrapped gas", usedGas);
        // should be ~50752
        assertLt(usedGas, 55_000);
    }

    function testGasWithdrawNative() public {
        address alice = users[0];
        address payable t = payable(address(tlfr));
        hevm.deal(alice, 10000);
        hevm.startPrank(alice);
        (bool sent, ) = t.call{value: 1000}("");
        assertTrue(sent);
        hevm.warp(600);
        uint256 startGas = gasleft();
        tlfr.claimNative(500);
        uint256 endGas = gasleft();
        uint256 usedGas = startGas - endGas;
        console.log("Native gas", usedGas);
        // should be ~32964
        assertLt(usedGas, 35_000);
    }

    function testSetup() public {
        hevm.warp(100);
        assertEq(tlfr.owner(), users[0]);
        assertEq(tlfr.calculateRate(10000, 100), 0);
        assertEq(tlfr.createdAt(), 100);
    }

    function testTransferOwnership() public {
        address payable alice = users[0];
        address payable bob = users[1];
        hevm.prank(bob);
        hevm.expectRevert("Ownable: caller is not the owner");
        tlfr.transferOwnership(bob);
        hevm.prank(alice);
        tlfr.transferOwnership(bob);
        hevm.expectRevert("Ownable: caller is not the owner");
        tlfr.transferOwnership(bob);
        hevm.prank(bob);
        tlfr.transferOwnership(alice);
    }

    function testEth() public {
        address payable alice = users[0];
        address payable t = payable(address(tlfr));
        hevm.deal(alice, 10000);
        hevm.startPrank(alice);
        (bool sent, ) = t.call{value: 100}("");
        assertTrue(sent);
        hevm.warp(600);
        hevm.expectRevert("claimed too much");
        tlfr.claimNative(1000);
        tlfr.claimNative(50);
        hevm.expectRevert("claimed too much");
        tlfr.claimNative(50);
        hevm.warp(1100);
        tlfr.claimNative(50);
    }

    function testCliffFuzz(uint256 x) public {
        address payable alice = users[0];
        hevm.startPrank(alice);
        hevm.warp(100);
        assertEq(tlfr2.calculateRate(x, 100), 0);
        hevm.warp(349);
        assertEq(tlfr2.calculateRate(x, 349), 0);
        hevm.warp(350);
        assertEq(tlfr2.calculateRate(x, 350), x / 4);
    }

    function testEthFuzz(uint256 x) public {
        address payable alice = users[0];
        address payable t = payable(address(tlfr));
        hevm.deal(alice, x);
        hevm.startPrank(alice);
        (bool sent, ) = t.call{value: x}("");
        assertTrue(sent);
        hevm.warp(600);
        hevm.expectRevert("claimed too much");
        tlfr.claimNative(x);
        tlfr.claimNative(x / 2);
        hevm.expectRevert("claimed too much");
        tlfr.claimNative(x / 2);
        hevm.warp(1100);
        tlfr.claimNative(x / 2);
    }

    function testToken() public {
        address payable alice = users[0];
        hevm.startPrank(alice);
        xyz.approve(address(tlfr), 1000);
        xyz.transfer(address(tlfr), 1000);
        assertEq(xyz.balanceOf(address(tlfr)), 1000);
        hevm.warp(600);
        hevm.expectRevert("claimed too much");
        tlfr.claimWrapped(address(xyz), 1000);
        hevm.expectRevert("no token balance");
        tlfr.claimWrapped(address(abc), 1000);
        hevm.warp(600);
        tlfr.claimWrapped(address(xyz), 500);
        hevm.expectRevert("claimed too much");
        tlfr.claimWrapped(address(xyz), 500);
        hevm.warp(1100);
        tlfr.claimWrapped(address(xyz), 500);
    }

    function testTokenFuzz(uint256 x) public {
        address payable alice = users[0];
        hevm.startPrank(alice);
        xyz = new MockERC20("test coin", "XYZ", alice, x);
        xyz.approve(address(tlfr), x);
        xyz.transfer(address(tlfr), x);
        assertEq(xyz.balanceOf(address(tlfr)), x);
        hevm.warp(600);
        hevm.expectRevert("claimed too much");
        tlfr.claimWrapped(address(xyz), x);
        hevm.expectRevert("no token balance");
        tlfr.claimWrapped(address(abc), x);
        hevm.warp(600);
        tlfr.claimWrapped(address(xyz), x / 2);
        hevm.expectRevert("claimed too much");
        tlfr.claimWrapped(address(xyz), x / 2);
        hevm.warp(1100);
        tlfr.claimWrapped(address(xyz), x / 2);
    }

    function testFinalRateWithFuzz(uint256 x) public {
        hevm.warp(1100);
        assertEq(tlfr.calculateRate(x, 1100), x);
    }

    function testIntermediateRateWithFuzz(uint256 x) public {
        hevm.warp(600);
        uint256 val = tlfr.calculateRate(x, 600);
        assertEq(val, x / 2);
    }
}
