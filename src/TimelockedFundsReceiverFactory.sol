// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "./TimelockedFundsReceiver.sol";
import "./MinimalProxy.sol";

contract TimelockedFundsReceiverFactory is MinimalProxy {
    TimelockedFundsReceiver[] public children;
    address public mainContract;

    constructor(address _mainContract) {
        mainContract = _mainContract;
    }

    event ReceiverCreated(
        address childAddress,
        address creatorAddress,
        address ownerAddress,
        uint256 vestDuration,
        uint256 cliffDuration
    );

    function createReceiver(
        uint256 vestDuration,
        uint256 cliffDuration,
        address intendedOwner
    ) external {
        address payable childContract = payable(this.clone(mainContract));
        TimelockedFundsReceiver tlfr = TimelockedFundsReceiver(childContract);
        tlfr.init(vestDuration, cliffDuration, intendedOwner);
        children.push(tlfr);
        emit ReceiverCreated(
            address(tlfr),
            msg.sender,
            intendedOwner,
            vestDuration,
            cliffDuration
        );
    }
}
