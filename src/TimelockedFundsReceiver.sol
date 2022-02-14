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
    mapping(address => uint256) private claimed;

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
    function _calculateRate(
        uint256 amount,
        uint256 ts,
        uint256 claimedAlready
    ) internal pure returns (uint256) {
        uint256 vestDuration_ = _vestDuration();
        uint256 elapsed = ts - _createdAt(); // solhint-disable-line not-rely-on-time
        if (elapsed < _cliffDuration()) return 0;
        if (elapsed >= vestDuration_) return amount;
        return
            Utils.mulDiv(amount + claimedAlready, elapsed, vestDuration_) -
            claimedAlready;
    }

    function calculateRate(
        uint256 amount,
        uint256 ts,
        uint256 claimedAlready
    ) external pure returns (uint256) {
        return _calculateRate(amount, ts, claimedAlready);
    }

    /**
     * @notice Claims ETH sent to this contract
     *
     * Calculates total ETH available then withdraws them.
     */
    function claimNative() external payable nonReentrant onlyOwner {
        uint256 ts = block.timestamp;
        uint256 claimedAlready = claimed[address(0)];
        uint256 claimable = _calculateRate(
            address(this).balance,
            ts,
            claimedAlready
        );
        claimed[address(0)] = claimed[address(0)] + claimable;
        payable(owner()).transfer(claimable);
        emit Withdrawal(owner(), address(0), claimable);
    }

    /**
     * @notice Claims tokens sent to this contract
     *
     * Calculates total coins available then withdraws them.
     *
     * @param token the token address to claim
     */
    function claimWrapped(address token) external nonReentrant onlyOwner {
        uint256 ts = block.timestamp;
        uint256 bal = IERC20(token).balanceOf(address(this));
        uint256 claimedAlready = claimed[token];
        uint256 claimable = _calculateWrappedAmount(bal, ts, claimedAlready);
        claimed[token] = claimed[token] + claimable;
        IERC20(token).transfer(owner(), claimable);
        emit Withdrawal(owner(), token, claimable);
    }

    function _calculateWrappedAmount(
        uint256 bal,
        uint256 ts,
        uint256 claimedAlready
    ) internal pure returns (uint256) {
        require(bal > 0, "no token balance");
        uint256 claimable = _calculateRate(bal, ts, claimedAlready);
        return claimable;
    }

    /**
     * @notice initialize the contract with an owner
     *
     * This can be called by anyone but only once.
     * In practice, we call this from the create clone function in a factory.
     * Owner must be mutable here, so it can't be in the call pattern.
     */
    function init(address intendedOwner) external {
        require(!isReady, "already initialized");
        _transferOwnership(intendedOwner);
        isReady = true;
    }
}
