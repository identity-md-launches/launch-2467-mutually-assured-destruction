# Mutually Assured Destruction (MAD)

MAD is an immutable, fixed-supply ERC-20. The deployable contract is
`MADToken` in `src/MADToken.sol`.

| Parameter | Value |
| --- | --- |
| Name | Mutually Assured Destruction |
| Symbol | MAD |
| Decimals | 18 |
| Whole-token supply | 1,000,000,000 MAD |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

## Behavior and assumptions

The constructor mints the entire supply once and emits
`Transfer(address(0), msg.sender, 10^27)`. The brief specifies a name and fixed supply;
the name does not imply a destruction, tax, or other special transfer mechanism.
The token uses OpenZeppelin Contracts v5.0.2's standard ERC-20 behavior, with no
overrides to transfer or approval logic.

- Transfers deliver the exact amount and preserve total supply. Zero-value transfers
  and self-transfers are supported. Transfers to the zero address revert.
- `approve` replaces a spender's allowance and emits `Approval`. A zero allowance
  revokes permission. Approving the zero address reverts.
- `transferFrom` requires sufficient balance and allowance, including when the caller
  is the deployer or the holder itself. Finite allowances decrease by the amount spent;
  `type(uint256).max` allowances remain unchanged. Failed calls revert all state changes.
- Transfers emit `Transfer`. This OpenZeppelin implementation does not emit an
  additional `Approval` when `transferFrom` consumes an allowance; integrations must
  query `allowance` when they need its current value.
- There is no owner, privileged role, later mint, burn, pause, blacklist, seizure,
  fee, rebase, permit, upgrade mechanism, or external call from the token.
- Direct ETH payments revert. Tokens sent to this contract or other recipients
  unable to return them cannot be recovered through an administrative rescue function.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x8feec55cf05ddbe4027c030012412734b43384518bcaa8ad487d894111252d98 forge test
forge fmt --check
```

All required Solidity dependencies are ordinary files under
`lib/openzeppelin-contracts`; no install step, network, submodule, environment
configuration, fork, FFI, or filesystem cheatcode is needed. Dependency version,
commit, checksums, and license are included there. Tests use a small local interface
to Foundry's built-in cheatcodes, so `forge-std` is not required. The seed above is
provided to the runner; Solidity tests do not read or modify environment variables.

Tests cover metadata, exact minting and its event, transfers and approvals, finite
and infinite allowances, self/zero transfers, invalid addresses, insufficient funds
or allowance, atomic failure, missing administrative entrypoints, and ETH rejection.
Fuzz tests run 512 cases each. Stateful invariants run 256 sequences of 64 calls,
comparing balances and allowances to an independent model after randomized valid
and invalid operations, and checking conservation of the whole supply.

`LaunchFlow.t.sol` exercises CREATE2 factory deployment, exact 10%/85%/5% transfers,
distributor claims, and the token-transfer legs of buying and selling. It is a local
token integration test, not an implementation or simulation of Uniswap v4 pricing.
The supplied protected launch tests require the launch network's factory, pool,
manifest, and harness dependencies; that full integration check belongs to the
independent verifier. No application contracts are needed for this token.

## Deployment parameters and responsibilities

The launch deployer should deploy the creation bytecode from
`out/MADToken.sol/MADToken.json`, with no ABI-encoded constructor arguments, on Ethereum
(chain ID 1). No initialization or configuration transaction follows deployment.
The constructor makes no external calls and requires no other contracts to exist.

**The immediate deployer receives every token.** For the intended launch this is the
IMD factory. Deploying through another factory or a wrapper sends the supply to that
contract, so the deployment operator must ensure it can distribute the tokens.
The factory has only the ordinary rights of a token holder; it has no special powers
after distributing its balance. Do not deploy behind a proxy.

The factory and launch service, separately from MADToken, handle the supplied launch
economics: 10% (100,000,000 MAD) to the MerkleDistributor, 85% (850,000,000 MAD) to the
pool, and 5% (50,000,000 MAD) to
`0x1ee3ffadfe138415a2ddaedeebe5f46616fa413d`. The pair is FWA at
`0xa0df17b5ac76ababa36e1450e2cbcd18a620c845`, with pool fee `12500` (1.25%), tick spacing
`60`, and initial market cap `2000000000000000000000000` in FWA's smallest units.
The launch service derives the actual opening pool price. These are external launch
settings, not token constructor parameters or token fees. The subsequent manifest
step supplies `launch.json`; this project does not create one.

After deployment, the launch operator verifies the source and compiler settings,
checks the token metadata and supply, and validates distribution and real pool
buy/sell settlement through the launch harness. There are no owner settings to
configure or recurring maintenance transactions for MADToken itself. Token holders
control their transfers and allowances; wallets should approve only amounts they
intend to spend and confirm revocation before replacing an existing nonzero allowance
to reduce the standard ERC-20 allowance-change race.

Local build, unit, fuzz, and stateful invariant checks are not an independent security
audit. Production release requires the network's separate adversarial review and
launch verification. Slither and Mythril are not part of the checks run here. No
transaction broadcasting, wallet access, or production deployment is performed by
this project.
