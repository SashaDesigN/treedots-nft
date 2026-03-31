# Tree Dots

**1,000 fully on-chain generative three-dot NFTs — no IPFS, no reveal.**

Every piece lives entirely on-chain: the SVG image, the JSON metadata, all of it. No external dependencies once deployed. The contract generates art from a pseudo-random seed at mint time and encodes it straight into the token URI as a base64 data URI. Open the token in any NFT marketplace and you're reading pixels that live inside the Ethereum state trie.

---

## The Collection

- **1,000 supply** — token IDs 0 through 999
- **Genesis set (IDs 0–19):** three green dots. Positions are random, colors are locked green. These 20 are the only way to ever hold three-green.
- **Rest (IDs 20–999):** three dots, each randomly colored yellow / green / blue / red. The contract enforces at mint that this set can never produce all-three-green — that combination is permanently reserved for the genesis set.

Each token stores 9 bytes on-chain:

```
[c0, c1, c2,  x0, x1, x2,  y0, y1, y2]
 ^colors       ^x-coords    ^y-coords
```

Packed into a `bytes9` via uint72 bit-shifting. Cheap storage, no struct overhead.

---

## Contract

```
src/TreeDots.sol
```

- Extends `ERC721` + `ERC2981` + `Ownable` (OpenZeppelin v5)
- **Mint price:** 0.04 ETH
- **Royalty:** 2% ERC-2981, paid to deployer wallet
- `tokenURI` returns a `data:application/json;base64,...` URI built entirely with `abi.encodePacked` + `Base64.encode` — zero off-chain calls
- Pseudo-randomness uses `block.prevrandao` (EIP-4399) + `tokenId` + `msg.sender` + `block.timestamp` as entropy

---

## Stack

- [Foundry](https://book.getfoundry.sh/) — build, test, deploy
- [OpenZeppelin Contracts v5](https://github.com/OpenZeppelin/openzeppelin-contracts) — ERC721, ERC2981, Ownable, Base64, Strings

---

## Getting Started

**Clone and install dependencies:**

```bash
git clone <repo>
cd nft-dots
forge install
```

**Build:**

```bash
forge build
```

**Run tests:**

```bash
forge test -vvv
```

**Local node + manual mint:**

```bash
# terminal 1 — spin up a local chain
anvil

# terminal 2 — deploy
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast --private-key <ANVIL_PK>

# mint one
cast send <CONTRACT_ADDR> "mint()" --value 0.04ether --rpc-url http://localhost:8545 --private-key <ANVIL_PK>

# inspect the on-chain token URI
cast call <CONTRACT_ADDR> "tokenURI(uint256)" 0 --rpc-url http://localhost:8545
```

Copy the returned base64 string, strip the `data:application/json;base64,` prefix, and decode it — you'll see the raw JSON with the SVG embedded inside.

---

## Deploy

**Testnet (e.g. Sepolia):**

```bash
forge script script/Deploy.s.sol \
  --rpc-url $SEPOLIA_RPC \
  --broadcast \
  --private-key $PRIVATE_KEY \
  --verify \
  --etherscan-api-key $ETHERSCAN_KEY
```

**Mainnet — same command, different RPC.** Double-check your private key env var and gas settings before pulling the trigger.

**Ledger / hardware wallet:**

```bash
forge script script/Deploy.s.sol \
  --rpc-url $MAINNET_RPC \
  --broadcast \
  --ledger
```

The deployer address automatically becomes the owner and ERC-2981 royalty receiver. Call `setRoyalty(address, uint96)` if you want to point royalties elsewhere after deploy.

---

## Withdrawing Mint Revenue

```bash
cast send <CONTRACT_ADDR> "withdraw()" \
  --rpc-url $RPC_URL \
  --private-key $OWNER_PK
```

Only the owner can call this. Sends the full contract balance to the owner address.

---

## Reading Dot Data

`getDots(tokenId)` returns the raw trait bytes — useful if you're building a frontend or indexer and want to reconstruct the SVG client-side without calling `tokenURI`:

```bash
cast call <CONTRACT_ADDR> "getDots(uint256)" 42 --rpc-url $RPC_URL
```

Returns: `c0, c1, c2, x0, x1, x2, y0, y1, y2` — all `uint8`.

Color mapping: `0 = Yellow`, `1 = Green`, `2 = Blue`, `3 = Red`.

---

## On-chain Metadata — How It Works

```solidity
// SVG built as bytes via abi.encodePacked
bytes memory svg = abi.encodePacked(
    '<svg ...><rect .../>',
    _circle(x0, y0, _colorHex(c0)),
    ...
    '</svg>'
);

// JSON wraps a base64-encoded SVG
bytes memory metadata = abi.encodePacked(
    '{"name":"Tree Dots #', tokenId.toString(), '",',
    '"image":"data:image/svg+xml;base64,', Base64.encode(svg), '",',
    ...
);

// Final return value: data URI
return string(abi.encodePacked(
    "data:application/json;base64,", Base64.encode(metadata)
));
```

No `tokenBaseURI`, no IPFS, no centralized server. The art is the contract.

---

## Foundry Cheatsheet

```bash
forge build              # compile
forge test -vvv          # run tests with traces
forge fmt                # format Solidity
forge snapshot           # gas snapshots
forge script             # run a script
cast call                # read chain state
cast send                # send a tx
anvil                    # local EVM node
```

Full docs: [book.getfoundry.sh](https://book.getfoundry.sh/)
