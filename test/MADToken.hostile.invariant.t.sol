// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MADToken} from "../src/MADToken.sol";
import {TestBase} from "./helpers/TestBase.sol";

/// @dev Drives the token with valid and hostile calls from six actors, including the token's own
/// address as a recipient and the zero address as a receiver, spender and owner. Every call goes
/// through a low-level call so the handler never reverts; the handler asserts each outcome against
/// its model and keeps ghost totals of what moved.
contract HostileMADHandler is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    MADToken public immutable token;
    address[6] public actors;
    address public immutable deployer;

    mapping(address => uint256) public modelBalance;
    mapping(address => mapping(address => uint256)) public modelAllowance;
    // Per-actor flows. For every actor: initial + received - sent == balance.
    mapping(address => uint256) public ghostReceived;
    mapping(address => uint256) public ghostSent;

    uint256 public successfulMoves;
    uint256 public refusedCalls;
    uint256 public unexpectedOutcomes;

    constructor() {
        token = new MADToken();
        deployer = address(this);
        actors = [
            address(this),
            address(0xA11CE),
            address(0xB0B),
            address(0xCA401),
            address(0xE5E),
            address(token)
        ];
        modelBalance[address(this)] = SUPPLY;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _bound(uint256 x, uint256 max) internal pure returns (uint256) {
        return x % (max + 1);
    }

    function _expect(bool ok, bool expected) internal {
        if (ok != expected) unexpectedOutcomes++;
        if (!ok) refusedCalls++;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount, uint8 mode) external {
        address from = _actor(fromSeed);
        address to = mode % 5 == 0 ? address(0) : _actor(toSeed);
        // Mostly valid amounts, sometimes exactly one wei over, sometimes anything.
        uint256 amount = mode % 5 == 1
            ? modelBalance[from] + 1
            : mode % 5 == 2 ? rawAmount : _bound(rawAmount, modelBalance[from]);
        vm.prank(from);
        (bool ok, bytes memory ret) =
            address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        bool expected = to != address(0) && amount <= modelBalance[from];
        _expect(ok, expected);
        if (ok) {
            if (!abi.decode(ret, (bool))) unexpectedOutcomes++;
            _move(from, to, amount);
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 mode)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = mode % 5 == 0 ? address(0) : _actor(spenderSeed);
        uint256 amount = mode % 5 == 1 ? 0 : mode % 5 == 2 ? type(uint256).max : rawAmount;
        vm.prank(owner);
        (bool ok,) = address(token).call(abi.encodeCall(token.approve, (spender, amount)));
        _expect(ok, spender != address(0));
        if (ok) modelAllowance[owner][spender] = amount;
    }

    function transferFrom(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 rawAmount,
        uint8 mode
    ) external {
        address from = mode % 7 == 0 ? address(0) : _actor(fromSeed);
        address to = mode % 7 == 1 ? address(0) : _actor(toSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = modelAllowance[from][spender];
        uint256 bal = modelBalance[from];
        uint256 amount;
        if (mode % 7 == 2) amount = rawAmount;
        else if (mode % 7 == 3) amount = allowed == type(uint256).max ? bal + 1 : allowed + 1;
        else amount = _bound(rawAmount, allowed < bal ? allowed : bal);

        vm.prank(spender);
        (bool ok, bytes memory ret) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        bool expected = from != address(0) && to != address(0) && amount <= allowed && amount <= bal;
        _expect(ok, expected);
        if (ok) {
            if (!abi.decode(ret, (bool))) unexpectedOutcomes++;
            if (allowed != type(uint256).max) modelAllowance[from][spender] = allowed - amount;
            _move(from, to, amount);
        }
    }

    /// @dev A random selector with random arguments from a random actor: whatever it is, it may
    /// only succeed if it is a view or a call the model already knows how to account for.
    function arbitraryCall(uint256 callerSeed, bytes4 selector, bytes32 a, bytes32 b) external {
        if (
            selector == token.transfer.selector || selector == token.transferFrom.selector
                || selector == token.approve.selector
        ) return;
        vm.prank(_actor(callerSeed));
        (bool ok,) = address(token).call(abi.encodePacked(selector, a, b));
        ok; // the invariants check that nothing moved
    }

    function _move(address from, address to, uint256 amount) private {
        modelBalance[from] -= amount;
        modelBalance[to] += amount;
        ghostSent[from] += amount;
        ghostReceived[to] += amount;
        if (amount > 0) successfulMoves++;
    }
}

contract MADTokenHostileInvariantTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    HostileMADHandler internal handler;
    MADToken internal token;

    function setUp() public {
        handler = new HostileMADHandler();
        token = handler.token();
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_everyCallOutcomeMatchesTheModel() public view {
        assertEq(handler.unexpectedOutcomes(), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_fixedSupplyFullyHeldByActors() public view {
        uint256 sum;
        for (uint256 i; i < 6; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.modelBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_nobodyLeavesWithMoreThanTheyReceived() public view {
        for (uint256 i; i < 6; ++i) {
            address actor = handler.actors(i);
            uint256 initial = actor == handler.deployer() ? SUPPLY : 0;
            assertEq(
                token.balanceOf(actor) + handler.ghostSent(actor),
                initial + handler.ghostReceived(actor)
            );
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_allowancesMatchModelIncludingZeroSpender() public view {
        for (uint256 i; i < 6; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 6; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.modelAllowance(owner, spender));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_metadataNeverChanges() public view {
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
    }

    /// @dev Guards against a vacuous handler: a fixed sequence through it must move tokens, be
    /// refused where the token should refuse, and agree with the model on every outcome.
    function test_handlerExercisesBothSuccessAndRefusal() public {
        for (uint256 i; i < 40; ++i) {
            uint256 seed = uint256(keccak256(abi.encode(i)));
            handler.transfer(i, i + 1, seed, uint8(i));
            handler.approve(i + 2, i, seed >> 8, uint8(i + 3));
            handler.transferFrom(i + 2, i + 4, i, seed >> 16, uint8(i));
            handler.arbitraryCall(i, bytes4(bytes32(seed)), bytes32(seed), bytes32(i));
        }
        assertTrue(handler.successfulMoves() > 0);
        assertTrue(handler.refusedCalls() > 0);
        assertEq(handler.unexpectedOutcomes(), 0);
        invariant_fixedSupplyFullyHeldByActors();
        invariant_nobodyLeavesWithMoreThanTheyReceived();
        invariant_allowancesMatchModelIncludingZeroSpender();
    }
}
