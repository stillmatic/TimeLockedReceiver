// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "./TimelockedFundsReceiver.sol";
// import "./MinimalProxy.sol";
import "clones-with-immutable-args/ClonesWithImmutableArgs.sol";

contract TimelockedFundsReceiverFactory {
    using ClonesWithImmutableArgs for address payable;
    TimelockedFundsReceiver public mainContract;

    constructor(TimelockedFundsReceiver _mainContract) {
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
    ) external returns (TimelockedFundsReceiver clone) {
        bytes memory data = abi.encodePacked(
            vestDuration,
            cliffDuration,
            block.timestamp
        );
        address payable impl = payable(address(mainContract));
        clone = TimelockedFundsReceiver(payable(impl.clone(data)));
        clone.init(intendedOwner);

        emit ReceiverCreated(
            address(clone),
            msg.sender,
            intendedOwner,
            vestDuration,
            cliffDuration
        );
    }
}
