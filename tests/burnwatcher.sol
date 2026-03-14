// TypeScript off-chain daemon
pulseProvider.on("PxAssetBurned", async (symbol, user, amount, burnId, event) => {
  const proof = generateBurnProof(event); // capture log, block info, tx hash

  await sendToSolana({
    symbol,
    user,
    amount,
    burnId,
    proof,
  });
});
