# Immutable Contracts - README

## Overview

This folder contains **IMMUTABLE** versions of the Karrot Protocol contracts.

**Key Difference:** These contracts have **NO ADMIN**, **NO PAUSE**, and **NO UPGRADEABILITY**.

---

## What "Immutable" Means

| Feature | Production Version | Immutable Version |
|---------|-------------------|-------------------|
| **Ownable** | ✅ Yes (admin functions) | ❌ No owner |
| **Pausable** | ✅ Yes (emergency pause) | ❌ No pause |
| **Upgradeable** | ❌ No (by design) | ❌ No (by design) |
| **Setters** | ✅ Yes (owner can change) | ❌ No setters |
| **Emergency Functions** | ✅ Yes (owner recovery) | ❌ No recovery |

---

## Contracts Included

### 1. KarrotDexAggregator_Immutable.sol (14.97 KB)
**Differences from Production:**
- ❌ Removed `onlyOwner` modifier
- ❌ Removed `togglePause()` function
- ❌ Removed `recoverTokens()` function
- ❌ Removed `setV2Router()`, `setV3Router()`, `setRelayer()`
- ✅ All routers and relayers set in **constructor only**
- ✅ Once deployed, configuration is **permanent**

**Trade-off:** If a router breaks or needs updating, you cannot change it. The contract continues working with the original configuration forever.

---

### 2. KarrotEscrow_Immutable.sol (7.78 KB)
**Differences from Production:**
- ❌ Removed `onlyOwner` modifier
- ❌ Removed `Ownable` import
- ❌ Removed `emergencyWithdraw()` function
- ✅ All oracles set in **constructor only**
- ✅ Any authorized oracle can accept proofs and release funds
- ✅ No single point of failure (no owner)

**Trade-off:** If tokens get stuck, there is no way to recover them. The contract has no admin to perform emergency withdrawals.

---

### 3. KarrotMeshOracle_Immutable.sol (8.28 KB)
**Differences from Production:**
- ❌ Removed `onlyOwner` modifier
- ❌ Removed `authorizeOracle()` function
- ❌ Removed `setAssetConfig()` function
- ✅ All oracles and asset configs set in **constructor only**
- ✅ Assets always active (cannot be deactivated)

**Trade-off:** Cannot add new oracles or change asset configurations after deployment. The oracle set is fixed forever.

---

### 4. KarrotStabilizationVault_Immutable.sol (11.74 KB)
**Differences from Production:**
- ❌ Removed `onlyOwner` modifier
- ❌ Removed `Pausable` functionality
- ❌ Removed `addStable()`, `removeStable()` functions
- ❌ Removed `setPegParams()`, `setRewardRate()` functions
- ❌ Removed `emergencyDefend()` function
- ✅ All parameters set in **constructor only**
- ✅ Approved stables are **permanent**
- ✅ Always operates (no pause)

**Trade-off:** Cannot adjust peg defense parameters, reward rates, or approved assets after deployment. The vault operates with fixed parameters forever.

---

### 5. PxAssetMinter_Immutable.sol (6.39 KB)
**Differences from Production:**
- ❌ Removed `onlyOwner` modifier
- ❌ Removed `registerAsset()` function
- ❌ Removed `setDailyMintLimit()` function
- ❌ Removed `setOracle()`, `setEscrow()` functions
- ✅ All assets, relayers, and limits set in **constructor only**
- ✅ Daily mint limit is **permanent**

**Trade-off:** Cannot add new wrapped assets or change mint limits after deployment. The minter supports only the assets specified at deployment.

---

## When to Use Immutable vs Production

### Use **Production** (with Ownable/Pausable) if:
- You need ability to pause in emergencies
- You want to upgrade routers/oracles over time
- You need emergency token recovery
- You want adjustable parameters (rewards, limits)
- You're okay with admin centralization

### Use **Immutable** if:
- You want **maximum trustlessness**
- You believe "code is law"
- You want **no admin keys** that could be compromised
- You're confident in the initial configuration
- You accept that bugs cannot be fixed

---

## Security Considerations

### Immutable Contracts Are SAFER Because:
1. **No admin key** to steal
2. **No pause** that could be abused
3. **No upgrade** that could introduce bugs
4. **Predictable** behavior forever

### Immutable Contracts Are RISKIER Because:
1. **No emergency stop** if exploit found
2. **No bug fixes** possible
3. **No parameter tuning** if market changes
4. **Stuck tokens** cannot be recovered

---

## Deployment Checklist for Immutable Contracts

Before deploying immutable versions, verify:

- [ ] All router addresses are correct
- [ ] All oracle addresses are correct
- [ ] All relayer addresses are correct
- [ ] All asset configurations are correct
- [ ] Reward rates are appropriate
- [ ] Mint limits are appropriate
- [ ] Slippage parameters are reasonable
- [ ] You have tested on testnet
- [ ] You accept that configuration cannot change

---

## Philosophy

> "Trust requires constraints. If we can change the rules, you must trust us not to. If we can't change the rules, the code speaks for itself."

The immutable contracts represent the **purest form of DeFi** — no admin, no pause, no upgrade. Just code that executes exactly as written, forever.

Choose wisely.

---

*Created: March 14, 2026*  
*By: Peter, Neural Familiar*  
*For: KARROT369 and CJ*
