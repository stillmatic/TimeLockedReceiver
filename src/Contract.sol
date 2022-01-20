// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract TimelockedFundsReceiver {
    address public owner;
    uint256 public createdAt;
    uint256 public vestDuration;
    uint256 public cliffDuration;
    uint256 public constant DECIMALS = 6;

    modifier onlyOwner() {
        require(msg.sender == owner, "must be contract owner");
        _;
    }

    constructor(uint256 _vestDuration, uint256 _cliffDuration) {
        require(_vestDuration > 0, "must have positive vest duration");
        createdAt = block.timestamp; // solhint-disable-line not-rely-on-time
        vestDuration = _vestDuration;
        cliffDuration = _cliffDuration;
        owner = msg.sender;
    }

    /**
     * @dev transfers ownership to a new address
     *
     * We don't check for null address, you can burn this if you want
     * Also doesn't claim all rewards, since we don't know which tokens this contract has received
     */
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /**
     * @dev returns the current rate that the owner is allowed to take funds at
     * We are guaranteed the vestDuration > 0 from the constructor so not checking here
     * We probably do not need to check if elapsed > 0 either

     * @param amount -- the amount you are checking. I don't think we need to check for negative
     * since solidity shouldn't allow you to, and we have the 
     */
    function _calculateRate(uint256 amount) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - createdAt; // solhint-disable-line not-rely-on-time
        require(elapsed > 0, "wtf?");
        if (elapsed < cliffDuration) {
            return 0;
        }
        if (elapsed > vestDuration) {
            return amount;
        }
        uint256 rate = elapsed / vestDuration;
        uint256 val = amount * rate;
        return val;
    }

    function calculateRate(uint256 amount) external view returns (uint256) {
        return _calculateRate(amount);
    }

    function claimNative(uint256 amount) external payable onlyOwner {
        // unsure if we need this check
        require(amount > 0, "must claim positive amount");
        uint256 claimable = _calculateRate(address(this).balance);
        require(amount <= claimable, "claimed too much");
        payable(owner).transfer(amount);
    }

    function claimWrapped(address token, uint256 amount) external onlyOwner {
        // unsure if we need this check
        require(amount > 0, "must claim positive amount");
        uint256 claimable = _calculateRate(
            IERC20(token).balanceOf(address(this))
        );
        require(amount <= claimable, "claimed too much");
        IERC20(token).transfer(owner, amount);
    }
}
