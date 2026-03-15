# 📦 Karrot Contracts Archive

**Historical Smart Contract Collection for the Karrot Ecosystem**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## Overview

This repository serves as the **comprehensive archive** for all smart contracts developed for the Karrot369 ecosystem. It contains production contracts, draft versions, legacy implementations, test contracts, and the new **immutable** versions that represent the purest form of decentralized finance.

**Total Contracts:** 100+  
**Categories:** 10  
**Lines of Code:** 50,000+

---

## Repository Structure

```
karrot-contracts-archive/
├── core/                    # Production-ready core contracts (24)
│   ├── KarrotDexAggregator_v4.sol
│   ├── KarrotEscrow_Production.sol
│   ├── KarrotMeshOracle_Production.sol
│   ├── KarrotStabilizationVault_Production.sol
│   └── ...
├── immutable/               # Immutable contracts (5) ⭐ NEW
│   ├── KarrotDexAggregator_Immutable.sol
│   ├── KarrotEscrow_Immutable.sol
│   ├── KarrotMeshOracle_Immutable.sol
│   ├── KarrotStabilizationVault_Immutable.sol
│   ├── PxAssetMinter_Immutable.sol
│   └── README.md
├── staking/                 # Staking-related contracts (17)
│   ├── earnRH.sol
│   ├── KS.sol
│   ├── Ncelbi2stake.sol
│   └── ...
├── stablecoin/              # MX DAI and pxAsset contracts (1)
│   └── mxDAIBurner.sol
├── nft/                     # NFT integration contracts (1)
│   └── NFTBoostRegistry.sol
├── archive-extras/          # Additional ecosystem contracts (19)
│   ├── SigmaInterestModel.sol
│   ├── SigmaLiquidator.sol
│   ├── Verifier.sol
│   └── ...
├── tests/                   # Test and verification contracts (10)
│   ├── BlackHat_Destructive.t.sol
│   ├── BreakTheDex_Hardcore.t.sol
│   ├── ImmutableSystem.t.sol
│   └── ...
├── infrastructure/          # Supporting infrastructure (7)
│   ├── EntropyEngine.sol
│   ├── HyperNovaEvent.sol
│   └── ...
├── drafts/                  # Work-in-progress versions (5)
│   ├── KarrotDexAggregator_v3_Draft.sol
│   └── ...
└── legacy/                  # Original versions (5)
    ├── KarrotDexAggregator_Original_NeedsRework.sol
    └── ...
```

---

## Contract Categories

### 🏆 Core Contracts (Production)
These are the **main production contracts** currently deployed or ready for deployment:

| Contract | Purpose | Lines |
|----------|---------|-------|
| KarrotDexAggregator_v4.sol | Universal DEX aggregator | 673 |
| KarrotEscrow_Production.sol | Cross-chain escrow | 200+ |
| KarrotMeshOracle_Production.sol | Multi-oracle consensus | 250+ |
| KarrotStabilizationVault_Production.sol | Peg defense vault | 400+ |

### 🔒 Immutable Contracts (NEW)
**No admin, no pause, no upgrade.** Everything set in constructor:

| Contract | Difference from Production |
|----------|---------------------------|
| KarrotDexAggregator_Immutable | No owner, routers fixed at deploy |
| KarrotEscrow_Immutable | No emergency withdraw, oracles immutable |
| KarrotMeshOracle_Immutable | No setters, config permanent |
| KarrotStabilizationVault_Immutable | No pause, params locked |
| PxAssetMinter_Immutable | No asset registration, limits fixed |

See `immutable/README.md` for detailed comparison.

---

## Security

### Audit Status
- ✅ **40+ attack vectors** tested and mitigated
- ✅ **Critical fixes** applied to all production contracts
- ✅ **Reentrancy protection** on all state-changing functions
- ✅ **Access control** properly implemented
- ✅ **Immutable versions** available for maximum trustlessness

### Known Limitations
1. **MEV Protection** — Protocol-level, not contract-level
2. **Rebasing Tokens** — Explicitly unsupported
3. **Oracle Centralization** — Escrow uses single oracle (MeshOracle uses quorum)

---

## Usage

### For Developers

```bash
# Clone the repository
git clone https://github.com/KARROT369/karrot-contracts-archive.git

# Install dependencies
npm install

# Compile contracts
npx hardhat compile

# Run tests
npx hardhat test

# Deploy to testnet
npx hardhat run scripts/deploy.js --network pulsechainTestnet
```

### Contract Integration

```solidity
// Import from archive
import "./core/KarrotDexAggregator_v4.sol";

// Or use immutable version
import "./immutable/KarrotDexAggregator_Immutable.sol";
```

---

## Token Addresses

| Token | Address | Network |
|-------|---------|---------|
| KARROT | 0x6910076Eee8F4b6ea251B7cCa1052dd744Fc04DA | PulseChain |
| RH (Rabbit Hole) | 0xDB75a19203a65Ba93c1baaac777d229bf08452Da | PulseChain |
| MX DAI | TBD | PulseChain |

---

## Ecosystem Integration

```
Karrot DEX (16 aggregators)
    ↓
Karrot Escrow (cross-chain)
    ↓
PxAsset Minter (wrapped assets)
    ↓
Karrot Mesh Oracle (price feeds)
    ↓
Stabilization Vault (peg defense)
    ↓
Staking Platforms (4 modes)
```

---

## Contributing

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/AmazingFeature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/AmazingFeature`)
5. **Open** a Pull Request

### Contribution Guidelines
- Follow Solidity style guide
- Include comprehensive NatSpec documentation
- Add tests for new functionality
- Update this README with new contracts

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Related Repositories

| Repository | Purpose | Link |
|------------|---------|------|
| karrot-dex | DEX frontend | https://github.com/KARROT369/karrot-dex |
| karrot_shrine | AI interface | https://github.com/KARROT369/karrot_shrine |
| ncelbi2 | Staking + NFT | https://github.com/KARROT369/ncelbi2 |
| ncelbi2-staking | Time rewards | https://github.com/KARROT369/ncelbi2-staking |
| entropy | Entropy mechanics | https://github.com/KARROT369/entropy |
| stake | Gamified staking | https://github.com/KARROT369/stake |
| B-twap | BRICS data | https://github.com/KARROT369/B-twap |
| KARROT-PROTOCOL | Active development | https://github.com/KARROT369/KARROT-PROTOCOL |

---

## Connect

- **GitHub:** https://github.com/KARROT369
- **Ecosystem:** KARROT369 DeFi + DadBule VTOL + Nova AI
- **Status:** Production contracts complete, awaiting testnet validation

---

## Acknowledgments

- **CJ** — Founder and visionary
- **Peter** — Neural Familiar, contract development
- **Community** — Testers, auditors, and supporters

---

*The root grows deep. The familiar stands ready.* 🥕

---

*Last Updated: March 14, 2026*
