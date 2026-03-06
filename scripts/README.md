# Setup Scripts

Quick-start guide for configuring the Potato Tipper on your Universal Profile.

## Prerequisites

- [Foundry](https://getfoundry.sh/) installed (for Solidity scripts)
- [Bun](https://bun.sh/) installed (for TypeScript scripts)
- A LUKSO Universal Profile with a controller that has `ADDUNIVERSALRECEIVERDELEGATE` permission

## 1. Configure environment

Copy the example file and fill in your values:

```bash
cp .env.example .env
```

Edit `.env`:

```
PRIVATE_KEY=0x...               # Controller private key (must have ADDUNIVERSALRECEIVERDELEGATE)
UP_ADDRESS=0x...                # Your Universal Profile address
POTATO_TIPPER_ADDRESS=0x...     # PotatoTipper contract (see deployed addresses)
POTATO_TOKEN_ADDRESS=0x...      # $POTATO token contract
TIP_AMOUNT=42000000000000000000            # 42 POTATO per tip (18 decimals)
MIN_FOLLOWERS=5                            # Minimum followers required to receive a tip
MIN_POTATO_BALANCE=100000000000000000000   # Minimum 100 POTATO balance required
TIPPING_BUDGET=1000000000000000000000      # Total 1000 POTATO authorized for tipping
```

See `deployments/` for deployed contract addresses on mainnet and testnet.

## 2. Pre-flight check (verify permissions)

**Foundry:**
```bash
forge script scripts/PreCheck_SetupPotatoTipper.s.sol:PreCheckSetupPotatoTipper --rpc-url lukso
```

**TypeScript (bun):**
```bash
bun run scripts/precheck-setupPotatoTipper-check.ts
```

## 3. Run setup

**Foundry:**
```bash
forge script scripts/SetupPotatoTipper.s.sol:SetupPotatoTipper --rpc-url lukso --broadcast
```

**TypeScript (bun):**
```bash
bun run scripts/setupPotatoTipper.ts
```

## 4. Verify setup

**Foundry:**
```bash
forge script scripts/PostCheck_SetupPotatoTipper.s.sol:PostCheckSetupPotatoTipper --rpc-url lukso
```

**TypeScript (bun):**
```bash
bun run scripts/postCheck-setupPotatoTipper.ts
```
