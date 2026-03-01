# EcoRound — Smart Contracts

Foundry project containing the two core contracts deployed on a **Tenderly virtual fork of Base Mainnet**.

## Contracts

### `FactoryMatch.sol`
Factory that deploys a new `VaultMatch` per match. Maintains a registry of all vaults.

| Function | Description |
|---|---|
| `createMatch(teamA, teamB)` | Deploys a new VaultMatch, returns `(matchId, vaultAddress)` |
| `getVault(matchId)` | Returns vault address for a given match ID |
| `nextMatchId()` | Current match counter |

### `VaultMatch.sol`
Per-match no-loss prediction vault. Lifecycle: **Open → Locked → Resolved → Claim**

| Function | Access | Description |
|---|---|---|
| `deposit(team, amount)` | Public | Deposit USDC to predict a team (Open only) |
| `lockMatch()` | Oracle | Locks match, deposits all USDC into Morpho |
| `resolveMatch(winner)` | Oracle | Redeems from Morpho, distributes yield |
| `claim()` | Public | Winners get deposit + yield share; losers get full deposit back |
| `getTotalDeposits()` | View | Total USDC deposited |
| `getYieldBalance()` | View | Current yield accrued in Morpho |

### `IVaultMatch.sol`
Interface defining shared enums, events, and errors.

- `MatchStatus`: `Open(0)`, `Locked(1)`, `Resolved(2)`
- `Team`: `None(0)`, `TeamA(1)`, `TeamB(2)`

## Deployed Addresses (Tenderly Base Fork)

| Contract | Address |
|---|---|
| **FactoryMatch** | `0x602473fc59ff5eefbe5d6c86d3af5c64ac7987bc` |
| **USDC** (Base native) | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| **Morpho ERC4626 Vault** | `0x050cE30b927Da55177A4914EC73480238BAD56f0` |

> VaultMatch contracts are deployed per match by the factory. Each match gets its own vault.

## Network

| Parameter | Value |
|---|---|
| Chain ID | `84531` |
| RPC | `https://virtual.rpc.tenderly.co/ecoround/ecoround/private/ecoround/9cf903bc-95b4-4882-bf0d-1625e4dca2b5` |
| Explorer | [Tenderly Dashboard](https://dashboard.tenderly.co/EndPx/project/testnet/ecoround-base) |

## Setup & Usage

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

cd contracts

# Build
forge build

# Test
forge test -vvv

# Deploy FactoryMatch to Tenderly fork
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Yield Mechanics

1. Users deposit USDC during Open phase — funds sit in the VaultMatch
2. Oracle calls `lockMatch()` → all USDC deposited into Morpho ERC4626 vault
3. While Locked, Morpho accrues yield on USDC
4. Oracle calls `resolveMatch(winner)` → Morpho redeems all shares → `totalYield` calculated
5. Winners call `claim()` → receive principal + proportional yield share
6. Losers call `claim()` → receive 100% principal back (no loss)
