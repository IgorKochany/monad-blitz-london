# FairRide 🚗⚡

**Uber without the middleman — riders and drivers agree the price directly, on Monad.**

Built at Monad Blitz London 2026.

## What it does

A rider posts a trip (pickup → drop-off, on a real map) with the price they want to pay, in **£ GBP** — settlement happens in MON under the hood. Drivers see the trip **instantly** (300ms Monad blocks) and bid their own price under the rider's time limit. Two modes:

- ⚡ **Need it fast (speed prioritized)** — the rider escrows their max price up front; the *first bid at or under it wins instantly*, on-chain, no human in the loop. The rider is auto-refunded the difference.
- 💰 **Review bids (saving money prioritized)** — drivers compete downward; the rider picks the best offer, and only then is their payment escrowed.

Funds sit in contract escrow until the rider confirms completion, then release straight to the driver. **The platform takes 0% — there is no platform.** Money only ever flows rider → escrow → driver.

## Why Monad

- 300ms blocks / 600ms finality make the bid feed feel like a Web2 realtime app — the driver dashboard polls the chain every 2.5s and never feels stale.
- Fees low enough that a £3 ride isn't eaten by gas.
- Full EVM compatibility: one Solidity contract, standard tooling.

## How to run it

**Live demo:** open the deployed URL (see submission). No install needed:
- 👀 **Watch** — works with no wallet at all (reads via public RPC)
- ✨ **Instant wallet** — one tap generates a wallet in your browser; tap your address to copy it and grab free MON at https://faucet.monad.xyz, then post trips or bid
- 🦊 MetaMask also supported (auto-adds Monad Testnet)
- **Presentation mode:** append `?present=1` for a self-generating QR code + live stats screen

**Deploy your own:**
1. Deploy `RideMarket.sol` to Monad Testnet (chain 10143) — e.g. paste into Remix, compile with solc 0.8.24+, deploy via Injected Provider.
2. Host `index.html` anywhere static (Netlify/Vercel/GitHub Pages) — it's a single self-contained file.
3. Point it at your contract: either edit `HARDCODED_ADDRESS` in `index.html`, or just open `your-site/?c=0xYourContractAddress`.

## Architecture

- `RideMarket.sol` — one contract: ride posting, open bidding with per-bid expiry, on-chain auto-accept with instant refund, escrow, completion payout, cancellation. No owner, no fees, no admin keys.
- `index.html` — the entire dApp in one file: ethers.js v6 (CDN), Leaflet/OpenStreetMap for pickup/drop-off pins and journey view, GBP↔MON pricing (live CoinGecko rate with graceful fallback), in-browser instant wallets, RPC failover across three public Monad endpoints.
- No backend, no indexer, no database. The chain is the backend.

## Contract (Monad Testnet)

- Address: `SEE SUBMISSION / ?c= PARAM`
- Explorer: https://testnet.monadvision.com

## Team

Built during the Blitz window — all code written today.
