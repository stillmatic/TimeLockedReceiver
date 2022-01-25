// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import {Clone} from "clones-with-immutable-args/Clone.sol";

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

    /// @notice Calculates floor(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    /// @dev Credit to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = a * b
        // Compute the product mod 2**256 and mod 2**256 - 1
        // then use the Chinese Remainder Theorem to reconstruct
        // the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2**256 + prod0
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        // Make sure the result is less than 2**256.
        // Also prevents denominator == 0
        require(denominator > prod1);

        ///////////////////////////////////////////////
        // 512 by 256 division.
        ///////////////////////////////////////////////

        // Make division exact by subtracting the remainder from [prod1 prod0]
        // Compute remainder using mulmod
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // Subtract 256 bit number from 512 bit number
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // Factor powers of two out of denominator
        // Compute largest power of two divisor of denominator.
        // Always >= 1.
        unchecked {
            uint256 twos = (type(uint256).max - denominator + 1) & denominator;
            // Divide denominator by power of two
            assembly {
                denominator := div(denominator, twos)
            }

            // Divide [prod1 prod0] by the factors of two
            assembly {
                prod0 := div(prod0, twos)
            }
            // Shift in bits from prod1 into prod0. For this we need
            // to flip `twos` such that it is 2**256 / twos.
            // If twos is zero, then it becomes one
            assembly {
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;

            // Invert denominator mod 2**256
            // Now that denominator is an odd number, it has an inverse
            // modulo 2**256 such that denominator * inv = 1 mod 2**256.
            // Compute the inverse by starting with a seed that is correct
            // correct for four bits. That is, denominator * inv = 1 mod 2**4
            uint256 inv = (3 * denominator) ^ 2;
            // Now use Newton-Raphson iteration to improve the precision.
            // Thanks to Hensel's lifting lemma, this also works in modular
            // arithmetic, doubling the correct bits in each step.
            inv *= 2 - denominator * inv; // inverse mod 2**8
            inv *= 2 - denominator * inv; // inverse mod 2**16
            inv *= 2 - denominator * inv; // inverse mod 2**32
            inv *= 2 - denominator * inv; // inverse mod 2**64
            inv *= 2 - denominator * inv; // inverse mod 2**128
            inv *= 2 - denominator * inv; // inverse mod 2**256

            // Because the division is now exact we can divide by multiplying
            // with the modular inverse of denominator. This will give us the
            // correct result modulo 2**256. Since the precoditions guarantee
            // that the outcome is less than 2**256, this is the final result.
            // We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inv;
            return result;
        }
    }

    function mulDivExt(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) external pure returns (uint256 result) {
        return mulDiv(a, b, denominator);
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
        return mulDiv(amount, elapsed, _vestDuration());
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
     * Calculates total coins available then checks how many of those are claimable.
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
