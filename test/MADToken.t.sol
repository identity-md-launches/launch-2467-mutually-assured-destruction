// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MADToken} from "../src/MADToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase, Vm} from "./helpers/TestBase.sol";

/// @dev A recipient with no token callback support must still receive normal ERC-20 transfers.
contract RejectingRecipient {
    fallback() external {
        revert("unexpected callback");
    }
}

contract MADTokenTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    MADToken internal token;

    function setUp() public {
        token = new MADToken();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        MADToken fresh = new MADToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_transferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 42 ether);
        assertTrue(token.transfer(ALICE, 42 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 42 ether);
        assertEq(token.balanceOf(ALICE), 42 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanMoveAndMoveBack() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToContractDoesNotCallRecipient() public {
        RejectingRecipient recipient = new RejectingRecipient();
        assertTrue(token.transfer(address(recipient), 100 ether));
        assertEq(token.balanceOf(address(recipient)), 100 ether);
    }

    function test_transferToZeroRevertsIncludingZeroAmount() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_insufficientBalanceRevertsWithoutMovingTokens() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_maximumUintTransferReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                SUPPLY,
                type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveEmitsEventWithoutMovingBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 50 ether);
        assertTrue(token.approve(SPENDER, 50 ether));
        assertEq(token.allowance(address(this), SPENDER), 50 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    function test_approveReplacesAndRevokesAllowance() public {
        assertTrue(token.approve(SPENDER, 50 ether));
        assertTrue(token.approve(SPENDER, 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 0);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_approvalDoesNotRequireBalance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromSpendsOnlyItsAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(SPENDER, 50 ether));
        assertTrue(token.approve(BOB, 7 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 20 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 20 ether));
        assertEq(token.allowance(address(this), SPENDER), 30 ether);
        assertEq(token.allowance(address(this), BOB), 7 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
        assertEq(token.balanceOf(ALICE), 20 ether);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    function test_exactAllowanceCanBeExhausted() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 1);
    }

    function test_infiniteAllowanceIsNotReduced() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1 ether));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 2 ether));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 1 ether);
        assertEq(token.balanceOf(BOB), 2 ether);
    }

    function test_transferFromToSelfSpendsAllowanceWithoutChangingBalance() public {
        assertTrue(token.approve(SPENDER, SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_zeroTransferFromWithoutAllowanceSucceeds() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_transferFromExceedingAllowanceRevertsAtomically() public {
        assertTrue(token.approve(SPENDER, 9));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 9, 10)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 10);
        assertEq(token.allowance(address(this), SPENDER), 9);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 20));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, SPENDER), 20);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromZeroReceiverRestoresAllowance() public {
        assertTrue(token.approve(SPENDER, 20));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), SPENDER), 20);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromZeroOwnerCannotMint() public {
        vm.prank(SPENDER);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (address(0), ALICE, 0)));
        assertFalse(ok);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_deployerCannotSpendHolderTokensWithoutApproval() public {
        assertTrue(token.transfer(ALICE, 100));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_noMintBurnOrAdministrativeEntrypoints() public {
        assertTrue(token.transfer(ALICE, 100));
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[6] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[7] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[10] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[11] = abi.encodeWithSignature("owner()");
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerOk,) = address(token).call(calls[i]);
            assertFalse(deployerOk);
            vm.prank(BOB);
            (bool strangerOk,) = address(token).call(calls[i]);
            assertFalse(strangerOk);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(BOB), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
    }

    function test_directEtherPaymentIsRejected() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferConservesSupply(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_arbitraryRecipient(address recipient, uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        if (recipient == address(0)) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
            token.transfer(recipient, amount);
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            assertTrue(token.transfer(recipient, amount));
            assertEq(token.balanceOf(recipient), recipient == address(this) ? SUPPLY : amount);
            assertEq(
                token.balanceOf(address(this)),
                recipient == address(this) ? SUPPLY : SUPPLY - amount
            );
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConservesSupplyAndAllowance(uint256 approved, uint256 rawAmount)
        public
    {
        uint256 limit = approved < SUPPLY ? approved : SUPPLY;
        uint256 amount = rawAmount % (limit + 1);
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(
            token.allowance(address(this), SPENDER),
            approved == type(uint256).max ? approved : approved - amount
        );
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceAlwaysReverts(uint256 rawBalance, uint256 rawExtra)
        public
    {
        uint256 balance = rawBalance % (SUPPLY + 1);
        uint256 extra = rawExtra % (type(uint256).max - balance) + 1;
        assertTrue(token.transfer(ALICE, balance));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, balance + extra
            )
        );
        vm.prank(ALICE);
        token.transfer(BOB, balance + extra);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveAllowanceAlwaysReverts(uint256 rawAllowance) public {
        uint256 approved = rawAllowance % SUPPLY;
        assertTrue(token.approve(SPENDER, approved));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, approved + 1
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, approved + 1);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
