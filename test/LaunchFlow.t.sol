// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MADToken} from "../src/MADToken.sol";
import {TestBase} from "./helpers/TestBase.sol";

/// @dev Local test harness only; this is not the production launch factory or a deployable app.
contract FactoryHarness {
    function deploy(bytes32 salt) external returns (MADToken) {
        return new MADToken{salt: salt}();
    }

    function distribute(MADToken token, address distributor, address pool, address remainder)
        external
    {
        uint256 supply = token.totalSupply();
        require(token.transfer(distributor, supply / 10));
        require(token.transfer(pool, supply * 85 / 100));
        require(token.transfer(remainder, supply * 5 / 100));
    }
}

contract LaunchFlowTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant POOL = address(0x9001);
    address internal constant REMAINDER = address(0x9002);
    address internal constant CLAIMANT = address(0xC1A1);
    address internal constant TRADER = address(0x9003);

    function test_factoryGetsEntireSupplyAndLaunchTransfersArriveWhole() public {
        FactoryHarness factory = new FactoryHarness();
        bytes32 salt = keccak256("local launch test");
        MADToken token = factory.deploy(salt);
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(factory),
                            salt,
                            keccak256(type(MADToken).creationCode)
                        )
                    )
                )
            )
        );
        assertEq(address(token), predicted);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        factory.distribute(token, DISTRIBUTOR, POOL, REMAINDER);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(DISTRIBUTOR), 100_000_000 ether);
        assertEq(token.balanceOf(POOL), 850_000_000 ether);
        assertEq(token.balanceOf(REMAINDER), 50_000_000 ether);

        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(CLAIMANT, 100_000_000 ether));
        assertEq(token.balanceOf(CLAIMANT), 100_000_000 ether);
        assertEq(token.balanceOf(DISTRIBUTOR), 0);

        // Exercise the token legs of a buy and sell. Actual AMM pricing/settlement is external.
        vm.prank(POOL);
        assertTrue(token.transfer(TRADER, 100 ether));
        assertEq(token.balanceOf(TRADER), 100 ether);
        vm.prank(TRADER);
        assertTrue(token.transfer(POOL, 100 ether));
        assertEq(token.balanceOf(TRADER), 0);
        assertEq(token.balanceOf(POOL), 850_000_000 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_constructorMintsToImmediateDeployer(address deployer) public {
        // Foundry-only callers: no production addresses are supplied by this test.
        if (deployer == address(0) || deployer == address(vm)) return;
        vm.prank(deployer);
        MADToken token = new MADToken();
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
