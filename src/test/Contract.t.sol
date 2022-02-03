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
    address payable alice;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);
        alice = users[0];
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
        tlfr.claimWrapped(address(xyz));
        uint256 endGas = gasleft();
        uint256 usedGas = startGas - endGas;
        console.log("Wrapped gas", usedGas);
        // should be ~73435
        assertLt(usedGas, 75_000);
    }

    function testGasWithdrawNative() public {
        address payable t = payable(address(tlfr));
        hevm.deal(alice, 10000);
        hevm.startPrank(alice);
        (bool sent, ) = t.call{value: 1000}("");
        assertTrue(sent);
        hevm.warp(600);
        uint256 startGas = gasleft();
        tlfr.claimNative();
        uint256 endGas = gasleft();
        uint256 usedGas = startGas - endGas;
        console.log("Native gas", usedGas);
        // should be ~55534
        assertLt(usedGas, 60_000);
    }

    function testSetup() public {
        hevm.warp(100);
        assertEq(tlfr.owner(), users[0]);
        assertEq(tlfr.calculateRate(10000, 100, 0), 0);
        assertEq(tlfr.createdAt(), 100);
        assertEq(address(tlfr).balance, 0);
    }

    function testTransferOwnership() public {
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

    function testCliffFuzz(uint256 x) public {
        hevm.startPrank(alice);
        hevm.warp(100);
        assertEq(tlfr2.calculateRate(x, 100, 0), 0);
        hevm.warp(349);
        assertEq(tlfr2.calculateRate(x, 349, 0), 0);
        hevm.warp(350);
        assertEq(tlfr2.calculateRate(x, 350, 0), x / 4);
    }

    // function testEthFuzz(uint256 x) public {
    //     address payable t = payable(address(tlfr));
    //     hevm.deal(alice, x);
    //     hevm.startPrank(alice);
    //     (bool sent, ) = t.call{value: x}("");
    //     assertTrue(sent);
    //     hevm.warp(600);
    //     hevm.expectRevert("claimed too much");
    //     tlfr.claimNative(x);
    //     tlfr.claimNative(x / 2);
    //     hevm.expectRevert("claimed too much");
    //     tlfr.claimNative(x / 2);
    //     hevm.warp(1100);
    //     tlfr.claimNative(x / 2);
    // }

    function testNativeFuzz() public {
        uint256 x = 1;
        if (x == 0) {
            return;
        }
        assertEq(address(tlfr).balance, 0);
        address payable t = payable(address(tlfr));
        address payable bob = users[1];
        hevm.deal(alice, x + 100);
        hevm.deal(bob, 100);
        hevm.startPrank(alice);
        (bool sent, ) = t.call{value: x}("");
        assertEq(address(tlfr).balance, x);
        assertEq(alice.balance, 100);
        assertTrue(sent);
        // hevm.expectRevert("no token balance");
        // tlfr.claimNative();
        hevm.warp(600);
        // this should be 1/2 of the balance
        tlfr.claimNative();
        uint256 tlfrBal = address(tlfr).balance;
        uint256 aliceBal = alice.balance;
        console.log("tlfr", tlfrBal, "alice", aliceBal);
        if (x % 2 == 0) {
            console.log("expect", tlfrBal, ((x / 2) + 1));
            assertEq(tlfrBal, x / 2);
            console.log("expect", aliceBal, ((x / 2)));
            assertEq(aliceBal, (x / 2) + 100);
        } else {
            console.log("expect", tlfrBal, ((x / 2) + 1));
            assertEq(tlfrBal, ((x / 2) + 1));
            console.log("expect", aliceBal, ((x / 2) + 100));
            assertEq(aliceBal, ((x / 2)) + 100);
        }
        // this is the same as above since they should not be allowed to claim more.
        tlfr.claimNative();
        uint256 tlfrBal2 = address(tlfr).balance;
        uint256 aliceBal2 = alice.balance;
        if (x % 2 == 0) {
            assertEq(tlfrBal2, x / 2);
            assertEq(aliceBal2, (x / 2) + 100);
        } else {
            console.log("expect2", tlfrBal2, ((x / 2) + 1));
            assertEq(tlfrBal2, ((x / 2) + 1));
            console.log("expect2", aliceBal2, ((x / 2) + 100));
            assertEq(aliceBal2, (x / 2) + 100);
        }
        // send some money to this wallet
        hevm.stopPrank();
        hevm.prank(bob);
        (bool sent2, ) = t.call{value: 100}("");
        assertTrue(sent2);
        assertEq(tlfrBal2 + 100, address(tlfr).balance);
        assertEq(aliceBal2, alice.balance);
        console.log("tlfr", address(tlfr).balance, "alice", alice.balance);
        hevm.startPrank(alice);
        // claim again
        // should be allowed to claim half of the extra balance
        tlfr.claimNative();
        console.log("tlfr", address(tlfr).balance, "alice", alice.balance);
        uint256 tlfrBal3 = address(tlfr).balance;
        uint256 aliceBal3 = alice.balance;
        if (x % 2 == 0) {
            assertEq(tlfrBal3, (x / 2) + 50);
            assertEq(aliceBal3, (x / 2) + 150);
        } else {
            console.log("expect3", tlfrBal3, ((x / 2) + 1) + 50);
            assertEq(tlfrBal3, ((x / 2) + 1) + 50);
            console.log("expect3", aliceBal3, ((x / 2) + 50));
            assertEq(aliceBal3, (x / 2) + 150);
        }

        hevm.warp(1100);
        tlfr.claimNative();
        console.log("expect4", address(tlfr).balance);
        console.log("expect4", alice.balance);

        assertEq(address(tlfr).balance, 0);
        assertEq(alice.balance, x + 200);
    }

    function testTokenFuzz(uint256 x) public {
        if (x == 0) {
            return;
        }
        hevm.startPrank(alice);
        xyz = new MockERC20("test coin", "XYZ", alice, x + 100);
        xyz.approve(address(tlfr), x + 100);
        xyz.transfer(address(tlfr), x);
        assertEq(xyz.balanceOf(address(tlfr)), x);
        hevm.expectRevert("no token balance");
        tlfr.claimWrapped(address(abc));
        hevm.warp(600);
        // this should be 1/2 of the balance
        tlfr.claimWrapped(address(xyz));
        uint256 tlfrBal = xyz.balanceOf(address(tlfr));
        uint256 aliceBal = xyz.balanceOf(alice);
        console.log(tlfrBal, aliceBal);
        if (x % 2 == 0) {
            console.log("expect", tlfrBal, ((x / 2) + 1));
            assertEq(tlfrBal, x / 2);
            console.log("expect", aliceBal, ((x / 2)));
            assertEq(aliceBal, (x / 2) + 100);
        } else {
            // console.log("expect", tlfrBal, ((x / 2) + 1));
            assertEq(tlfrBal, ((x / 2) + 1));
            // console.log("expect", aliceBal, ((x / 2)));
            assertEq(aliceBal, ((x / 2)) + 100);
        }
        // this is the same as above since they should not be allowed to claim more.
        tlfr.claimWrapped(address(xyz));
        uint256 tlfrBal2 = xyz.balanceOf(address(tlfr));
        uint256 aliceBal2 = xyz.balanceOf(alice);
        if (x % 2 == 0) {
            assertEq(tlfrBal2, x / 2);
            assertEq(aliceBal2, (x / 2) + 100);
        } else {
            // console.log("expect2", tlfrBal2, ((x / 2) + 1));
            assertEq(tlfrBal2, ((x / 2) + 1));
            // console.log("expect2", aliceBal2, ((x / 2) + 100));
            assertEq(aliceBal2, (x / 2) + 100);
        }
        // send some money to this wallet
        xyz.transfer(address(tlfr), 100);
        tlfr.claimWrapped(address(xyz));
        uint256 tlfrBal3 = xyz.balanceOf(address(tlfr));
        uint256 aliceBal3 = xyz.balanceOf(alice);
        if (x % 2 == 0) {
            assertEq(tlfrBal3, (x / 2) + 50);
            assertEq(aliceBal3, (x / 2) + 50);
        } else {
            console.log("expect3", tlfrBal3, ((x / 2) + 1) + 50);
            assertEq(tlfrBal3, ((x / 2) + 1) + 50);
            console.log("expect3", aliceBal3, ((x / 2) + 50));
            assertEq(aliceBal3, (x / 2) + 50);
        }

        hevm.warp(1100);
        tlfr.claimWrapped(address(xyz));
        assertEq(xyz.balanceOf(address(tlfr)), 0);
        assertEq(xyz.balanceOf(alice), x + 100);
    }

    function testFinalRateWithFuzz(uint256 x) public {
        hevm.warp(1100);
        assertEq(tlfr.calculateRate(x, 1100, 0), x);
    }

    function testIntermediateRateWithFuzz(uint256 x) public {
        hevm.warp(600);
        uint256 val = tlfr.calculateRate(x, 600, 0);
        assertEq(val, x / 2);
    }
}
