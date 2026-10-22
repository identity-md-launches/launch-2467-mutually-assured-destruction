// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mutually Assured Destruction
/// @notice A fixed-supply, 18-decimal ERC-20 token without administrative powers.
contract MADToken is ERC20 {
    /// @notice One billion MAD, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mint the entire supply once to the immediate deploying address.
    /// @dev During an IMD launch, msg.sender is the factory that distributes the supply.
    constructor() ERC20("Mutually Assured Destruction", "MAD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
