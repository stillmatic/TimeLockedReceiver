// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import {Clone} from "clones-with-immutable-args/Clone.sol";
import {Utils} from "./Utils.sol";

/** @title TimeLockedFundsReceiver
 *
 * A simple receiver which receives funds and allows users to withdraw according to a
 * defined vesting schedule.
 */
contract TimelockedFundsReceiver is ReentrancyGuard, Ownable, Clone {
    bool private isReady;

    event Withdrawal(address who, address token, uint256 amount);

    fallback() external payable {}

    receive() external payable {}

    function _createdAt() internal pure returns (uint256) {
        return _getArgUint256(64);
    }

    function _vestDuration() internal pure returns (uint256) {
        return _getArgUint256(0);
    }

    function _cliffDuration() internal pure returns (uint256) {
        return _getArgUint256(32);
    }

    function createdAt() external pure returns (uint256) {
        return _createdAt();
    }

    function vestDuration() external pure returns (uint256) {
        return _vestDuration();
    }

    function cliffDuration() external pure returns (uint256) {
        return _cliffDuration();
    }

    /**
     * @dev returns the current rate that the owner is allowed to take funds at
     * We are guaranteed the vestDuration > 0 from the constructor so not checking here
     * No divide by zero check because if _vestDuration() it returns beforehand.
     *
     * @param amount -- the amount you are checking.
     */
    function _calculateRate(uint256 amount, uint256 ts)
        internal
        pure
        returns (uint256)
    {
        uint256 elapsed = ts - _createdAt(); // solhint-disable-line not-rely-on-time
        if (elapsed < _cliffDuration()) return 0;
        if (elapsed >= _vestDuration()) return amount;
        return Utils.mulDiv(amount, elapsed, _vestDuration());
    }

    function calculateRate(uint256 amount, uint256 ts)
        external
        pure
        returns (uint256)
    {
        return _calculateRate(amount, ts);
    }

    /**
     * @notice Claims ETH sent to this contract
     *
     * @param amount how much to attempt to claim
     */
    function claimNative(uint256 amount)
        external
        payable
        nonReentrant
        onlyOwner
    {
        uint256 ts = block.timestamp;
        uint256 claimable = _calculateRate(address(this).balance, ts);
        require(amount <= claimable, "claimed too much");
        payable(owner()).transfer(amount);
        emit Withdrawal(owner(), address(0), amount);
    }

    /**
     * @notice Claims tokens sent to this contract
     *
     * Calculates total coins available then withdraws them.
     *
     * @param token the token address to claim
     * @param amount how much to attempt to claim
     */
    function claimWrapped(address token, uint256 amount)
        external
        nonReentrant
        onlyOwner
    {
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, "no token balance");
        uint256 ts = block.timestamp;
        uint256 claimable = _calculateRate(bal, ts);
        require(amount <= claimable, "claimed too much");
        IERC20(token).transfer(owner(), amount);
        emit Withdrawal(owner(), token, amount);
    }

    function init(address intendedOwner) external {
        require(!isReady, "already initialized");
        _transferOwnership(intendedOwner);
        isReady = true;
    }
}
