// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MADToken} from "../src/MADToken.sol";
import {TestBase} from "./helpers/TestBase.sol";

/// @dev All token holders are in this closed actor set. The model tracks expected balances and
/// allowances independently of the token, including unsuccessful calls and self-transfers.
contract MADHandler is TestBase {
    MADToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public modelBalance;
    mapping(address => mapping(address => uint256)) public modelAllowance;

    constructor() {
        token = new MADToken();
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCA401)];
        modelBalance[address(this)] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = rawAmount % (modelBalance[from] + 1);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 mode)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Deliberately mix finite, infinite and revoked allowances in operation sequences.
        uint256 amount = mode % 3 == 0 ? 0 : mode % 3 == 1 ? type(uint256).max : rawAmount;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        modelAllowance[owner][spender] = amount;
    }

    function transferFrom(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 rawAmount,
        bool validAmount
    ) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = modelAllowance[from][spender];
        uint256 limit = allowed < modelBalance[from] ? allowed : modelBalance[from];
        uint256 amount = validAmount ? rawAmount % (limit + 1) : rawAmount;

        vm.prank(spender);
        (bool ok, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        if (amount <= allowed && amount <= modelBalance[from]) {
            assertTrue(ok);
            assertTrue(abi.decode(result, (bool)));
            if (allowed != type(uint256).max) modelAllowance[from][spender] = allowed - amount;
            _move(from, to, amount);
        } else {
            assertFalse(ok);
        }
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.prank(from);
        (bool ok,) =
            address(token).call(abi.encodeCall(token.transfer, (to, modelBalance[from] + 1)));
        assertFalse(ok);
    }

    function _move(address from, address to, uint256 amount) private {
        modelBalance[from] -= amount;
        modelBalance[to] += amount;
    }
}

contract MADTokenInvariantTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    MADHandler internal handler;
    MADToken internal token;

    function setUp() public {
        handler = new MADHandler();
        token = handler.token();
    }

    /// @dev Foundry's native invariant targeting interface, without an external test dependency.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function invariant_supplyAndBalancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.modelBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.modelAllowance(owner, spender));
            }
        }
    }
}
