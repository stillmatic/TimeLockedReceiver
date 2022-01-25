# Timelocked Stream Receiver

This is a smart contract which receives flows (in ETH and other tokens) and allows a governance owner to claim the funds. However, this contract enforces timelocks on the claiming.

A simple reading is to say, these flows vest over 4 years, and therefore after 1 year, 25% of them are claimable. We also enable cliffs (vesting remains linear but an owner may not claim before a certain time). Any new inflows can be claimed pro-rata as well: e.g. at 1 year, you can claim 25% of any new incoming transaction. When fully vested, the owner can receive all funds.

Why is this good?

- Contract owners can signal their long-term focus by agreeing to lock funds for a longer period of time. For example, NFT project creators can show their long-term intent by dedicating royalty fees to this contract.
- Token owners can also signal their long term intent by timelocking funds.
- In the future, we could support delegating flows from this contract to other wallets. This flow delegation would be tricky if the flows went directly to a end user wallet.

Other implementation details:

- Tested and fuzzed with [Foundry](https://github.com/gakonst/foundry/). Fuzzing caught a number of overflow errors and things seem reasonably solid but --- this is unaudited code that should not be used for anything meaningful!
- We use a clone factory approach to minimize gas costs of additional deploys.
- A deploy currently costs about 92k gwei, half of a Uniswap swap. A withdrawal costs about 50k gwei for ERC20 and 33k for native ETH, versus 25k for a native ERC20 transfer cost.

## Development

Initialization

```bash
git submodule update --init --recursive  ## initialize submodule dependencies
npm install ## install development dependencies
forge build
forge test
```

Pre-configured `solhint` and `prettier-plugin-solidity`. Can be run by

```
npm run solhint
npm run prettier
```
