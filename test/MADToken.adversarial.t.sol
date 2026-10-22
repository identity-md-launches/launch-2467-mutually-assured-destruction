// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MADToken} from "../src/MADToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./helpers/TestBase.sol";

/// @dev Cheatcodes beyond the shared helper's subset, used only by this file.
interface VmExtra {
    function startPrank(address sender) external;
    function stopPrank() external;
}

/// @dev Re-enters nothing and calls the token from a contract, to check that contract holders and
/// spenders have exactly the rights of EOAs and nothing more.
contract ContractHolder {
    function send(MADToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    function pull(MADToken token, address from, address to, uint256 amount)
        external
        returns (bool)
    {
        return token.transferFrom(from, to, amount);
    }

    function allow(MADToken token, address spender, uint256 amount) external returns (bool) {
        return token.approve(spender, amount);
    }
}

/// @dev Adversarial unit and fuzz tests: callers and inputs the implementation might not expect.
contract MADTokenAdversarialTest is TestBase {
    VmExtra internal constant vmx =
        VmExtra(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant EVE = address(0xE5E);

    MADToken internal token;

    function setUp() public {
        token = new MADToken();
    }

    function _bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + x % (max - min + 1);
    }

    // ---------------------------------------------------------------- fixed edges

    function test_supplyIsExactlyTenToTheTwentySeven() public view {
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.INITIAL_SUPPLY(), 10 ** 27);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** uint256(token.decimals()));
    }

    function test_oneWeiOverBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1
            )
        );
        token.transfer(ALICE, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_oneWeiTransferAndBack() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_sameTransferTwiceCannotOverdraw() public {
        assertTrue(token.transfer(ALICE, 10));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 10);
        assertEq(token.balanceOf(BOB), 10);
    }

    function test_sameTransferFromTwiceCannotReuseAllowance() public {
        assertTrue(token.approve(EVE, 10));
        vm.prank(EVE);
        assertTrue(token.transferFrom(address(this), EVE, 10));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, EVE, 0, 10)
        );
        vm.prank(EVE);
        token.transferFrom(address(this), EVE, 10);
        assertEq(token.balanceOf(EVE), 10);
    }

    function test_allowanceIsDirectional() public {
        // Alice approving Bob does not let Alice spend Bob's tokens, nor Bob spend for a third party.
        assertTrue(token.transfer(BOB, 100));
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 100));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1)
        );
        vm.prank(ALICE);
        token.transferFrom(BOB, ALICE, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1)
        );
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(BOB), 100);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_ownerNeedsAllowanceForOwnTransferFrom() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(address(this), ALICE, 1);
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.allowance(address(this), address(this)), 0);
    }

    function test_maxAllowanceStillLimitedByBalance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(EVE, type(uint256).max));
        assertTrue(token.transfer(ALICE, 5));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 5, 6)
        );
        vm.prank(EVE);
        token.transferFrom(ALICE, EVE, 6);
        assertEq(token.balanceOf(ALICE), 5);
        assertEq(token.allowance(ALICE, EVE), type(uint256).max);
    }

    function test_maxMinusOneAllowanceIsFiniteAndDecreases() public {
        assertTrue(token.approve(EVE, type(uint256).max - 1));
        vm.prank(EVE);
        assertTrue(token.transferFrom(address(this), EVE, 1));
        assertEq(token.allowance(address(this), EVE), type(uint256).max - 2);
    }

    function test_transferFromEmitsTransferButNoApproval() public {
        assertTrue(token.approve(EVE, 10));
        vm.recordLogs();
        vm.prank(EVE);
        assertTrue(token.transferFrom(address(this), BOB, 4));
        assertEq(vm.getRecordedLogs().length, 1);
        assertEq(token.allowance(address(this), EVE), 6);
    }

    function test_approveZeroOwnerIsImpossibleFromZeroAddressCaller() public {
        // A call whose msg.sender is address(0) cannot exist on chain; the token still refuses it.
        vm.prank(address(0));
        (bool ok,) = address(token).call(abi.encodeCall(token.approve, (EVE, 1)));
        assertFalse(ok);
        assertEq(token.allowance(address(0), EVE), 0);
    }

    function test_tokensSentToTheTokenItselfAreStuckButCounted() public {
        assertTrue(token.transfer(address(token), 7));
        assertEq(token.balanceOf(address(token)), 7);
        assertEq(token.totalSupply(), SUPPLY);
        // The token has no function that moves its own balance.
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 7
            )
        );
        token.transferFrom(address(token), address(this), 7);
        assertEq(token.balanceOf(address(token)), 7);
    }

    function test_contractHoldersBehaveAsEoas() public {
        ContractHolder holder = new ContractHolder();
        ContractHolder spender = new ContractHolder();
        assertTrue(token.transfer(address(holder), 100));
        assertTrue(holder.allow(token, address(spender), 30));
        assertTrue(spender.pull(token, address(holder), BOB, 30));
        assertEq(token.balanceOf(BOB), 30);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(spender), 0, 1
            )
        );
        spender.pull(token, address(holder), BOB, 1);
        assertTrue(holder.send(token, ALICE, 70));
        assertEq(token.balanceOf(address(holder)), 0);
        assertEq(token.balanceOf(ALICE), 70);
    }

    function test_deployerHasNoRightsAfterDistributing() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1
            )
        );
        token.transfer(BOB, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_noFallbackAndNoNoncesOrPermit() public {
        bytes[] memory calls = new bytes[](8);
        calls[0] = hex"";
        calls[1] = hex"00";
        calls[2] = hex"deadbeef";
        calls[3] = abi.encodeWithSignature("nonces(address)", ALICE);
        calls[4] = abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
            ALICE,
            EVE,
            SUPPLY,
            type(uint256).max,
            uint8(27),
            bytes32(0),
            bytes32(0)
        );
        calls[5] = abi.encodeWithSignature("increaseAllowance(address,uint256)", EVE, 1);
        calls[6] = abi.encodeWithSignature("renounceOwnership()");
        calls[7] = abi.encodeWithSignature("rescueTokens(address,uint256)", EVE, 1);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(EVE);
            (bool ok,) = address(token).call(calls[i]);
            assertFalse(ok);
        }
        assertEq(token.allowance(ALICE, EVE), 0);
        assertEq(token.allowance(address(this), EVE), 0);
        assertEq(token.balanceOf(EVE), 0);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory code = address(token).code;
        assertTrue(code.length > 0);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f; // skip PUSH immediates
                continue;
            }
            assertTrue(op != 0xF4 && op != 0xF2 && op != 0xFF);
        }
    }

    function test_runtimeMakesNoExternalCalls() public view {
        bytes memory code = address(token).code;
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            // CALL, STATICCALL, CREATE, CREATE2
            assertTrue(op != 0xF1 && op != 0xFA && op != 0xF0 && op != 0xF5);
        }
    }

    // ---------------------------------------------------------------- fuzz

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_arbitraryCalldataFromStrangerMovesNothing(bytes calldata data, address caller)
        public
    {
        if (
            caller == address(0) || caller == address(this) || caller == address(vm)
                || caller == ALICE || caller == BOB
        ) caller = EVE;
        assertTrue(token.transfer(ALICE, 1000));
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 10));
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        ok; // success or failure are both acceptable; only the effects are checked
        // Whatever the stranger called, nobody's balance or allowance moved and supply held.
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(caller), 0);
        assertEq(token.balanceOf(ALICE), 1000);
        assertEq(token.allowance(ALICE, BOB), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1000);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromOutcomeMatchesModel(
        address owner,
        address spender,
        address to,
        uint256 balance,
        uint256 allowed,
        uint256 amount
    ) public {
        if (owner == address(this) || owner == address(0) || owner == address(vm)) {
            owner = ALICE;
        }
        if (spender == address(0) || spender == address(vm)) spender = EVE;
        balance = _bound(balance, 0, SUPPLY);
        amount = _bound(amount, 0, SUPPLY + 1);
        if (balance > 0) assertTrue(token.transfer(owner, balance));
        vm.prank(owner);
        assertTrue(token.approve(spender, allowed));

        uint256 toBefore = token.balanceOf(to == address(0) ? BOB : to);
        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));

        bool shouldSucceed = to != address(0) && amount <= allowed && amount <= balance;
        assertEq(ok ? 1 : 0, shouldSucceed ? 1 : 0);
        if (ok) {
            assertEq(
                token.allowance(owner, spender),
                allowed == type(uint256).max ? allowed : allowed - amount
            );
            if (to != owner) {
                assertEq(token.balanceOf(owner), balance - amount);
                assertEq(token.balanceOf(to), toBefore + amount);
            } else {
                assertEq(token.balanceOf(owner), balance);
            }
        } else {
            assertEq(token.allowance(owner, spender), allowed);
            assertEq(token.balanceOf(owner), balance);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_splitTransfersEqualOneTransfer(uint256 a, uint256 b) public {
        a = _bound(a, 0, SUPPLY);
        b = _bound(b, 0, SUPPLY - a);
        assertTrue(token.transfer(ALICE, a));
        assertTrue(token.transfer(ALICE, b));
        assertEq(token.balanceOf(ALICE), a + b);
        assertEq(token.balanceOf(address(this)), SUPPLY - a - b);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_roundTripRestoresBalances(uint256 amount, address peer) public {
        if (peer == address(0) || peer == address(this)) peer = BOB;
        amount = _bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(peer, amount));
        vm.prank(peer);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(peer), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveIsIdempotentAndLastWriteWins(uint256 first, uint256 second) public {
        vmx.startPrank(ALICE);
        assertTrue(token.approve(EVE, first));
        assertTrue(token.approve(EVE, first));
        assertEq(token.allowance(ALICE, EVE), first);
        assertTrue(token.approve(EVE, second));
        vmx.stopPrank();
        assertEq(token.allowance(ALICE, EVE), second);
        assertEq(token.allowance(EVE, ALICE), 0);
    }
}
