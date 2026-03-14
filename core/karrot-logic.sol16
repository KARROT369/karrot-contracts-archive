// karrot-logic.js

let selectedAggregator = "PulseX";

const aggregatorTokens = {
  PulseX: [
    { address: "0x6b175474e89094c44da98b954eedeac495271d0f", label: "DAI", logo: "img/dai.png" },
    { address: "0x6910076eee8f4b6ea251b7cca1052dd744fc04da", label: "KARROT", logo: "img/karrot-hex.jpg" }
  ],
  Ray: [
    { address: "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643", label: "MXDAI", logo: "img/mxdai.png" },
    { address: "0x4fabb145d64652a948d72533023f6e7a623c7c53", label: "BUSD", logo: "img/busd.png" }
  ],
  ZK: [
    { address: "0xabc1abc1abc1abc1abc1abc1abc1abc1abc1abc1", label: "ZKToken", logo: "img/zk-token.png" },
    { address: "0xabc2abc2abc2abc2abc2abc2abc2abc2abc2abc2", label: "ZKUSD", logo: "img/zkusd.png" }
  ],
  "9mm": [
    { address: "0x9001900190019001900190019001900190019001", label: "9USDC", logo: "img/usdc.png" },
    { address: "0x9002900290029002900290029002900290029002", label: "9K", logo: "img/karrot-hex.jpg" }
  ],
  Piteas: [
    { address: "0x8881888188818881888188818881888188818881", label: "PUSD", logo: "img/usdc.png" },
    { address: "0x8882888288828882888288828882888288828882", label: "PK", logo: "img/karrot-hex.jpg" }
  ],
  Uniswap: [
    { address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", label: "USDC", logo: "img/usdc.png" },
    { address: "0x6920076eee8f4b6ea251b7cca1052dd744fc04da", label: "KARROT", logo: "img/karrot-hex.jpg" }
  ],
  PancakeSwap: [
    { address: "0xe9e7cea3dedca5984780bafc599bd69add087d56", label: "BUSD", logo: "img/busd.png" },
    { address: "0xbbb2bbb2bbb2bbb2bbb2bbb2bbb2bbb2bbb2bbb2", label: "BNB", logo: "img/bnb.png" }
  ],
  CowSwap: [
    { address: "0xcccccccccccccccccccccccccccccccccccccccc", label: "COW", logo: "img/default-token.png" },
    { address: "0xcccccccccccccccccccccccccccccccccccccccd", label: "ETH", logo: "img/eth.png" }
  ],
  "1inch": [
    { address: "0x111111111117dc0aa78b770fa6a738034120c302", label: "1INCH", logo: "img/default-token.png" },
    { address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", label: "ETH", logo: "img/eth.png" }
  ],
  Matcha: [
    { address: "0x1234123412341234123412341234123412341234", label: "MATCH", logo: "img/default-token.png" },
    { address: "0x5678567856785678567856785678567856785678", label: "mDAI", logo: "img/dai.png" }
  ],
  ThorSwap: [
    { address: "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef", label: "RUNE", logo: "img/default-token.png" },
    { address: "0xdeedbeefdeedbeefdeedbeefdeedbeefdeedbeef", label: "THORUSD", logo: "img/usdc.png" }
  ]
};

const DEFAULTS = {
  PulseX: {
    from: "0x6b175474e89094c44da98b954eedeac495271d0f",
    to: "0x6910076eee8f4b6ea251b7cca1052dd744fc04da"
  },
  Ray: {
    from: "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643",
    to: "0x4fabb145d64652a948d72533023f6e7a623c7c53"
  },
  ZK: {
    from: "0xabc1abc1abc1abc1abc1abc1abc1abc1abc1abc1",
    to: "0xabc2abc2abc2abc2abc2abc2abc2abc2abc2abc2"
  },
  "9mm": {
    from: "0x9001900190019001900190019001900190019001",
    to: "0x9002900290029002900290029002900290029002"
  },
  Piteas: {
    from: "0x8881888188818881888188818881888188818881",
    to: "0x8882888288828882888288828882888288828882"
  },
  Uniswap: {
    from: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
    to: "0x6920076eee8f4b6ea251b7cca1052dd744fc04da"
  },
  PancakeSwap: {
    from: "0xe9e7cea3dedca5984780bafc599bd69add087d56",
    to: "0xbbb2bbb2bbb2bbb2bbb2bbb2bbb2bbb2bbb2bbb2"
  },
  CowSwap: {
    from: "0xcccccccccccccccccccccccccccccccccccccccc",
    to: "0xcccccccccccccccccccccccccccccccccccccccd"
  },
  "1inch": {
    from: "0x111111111117dc0aa78b770fa6a738034120c302",
    to: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  },
  Matcha: {
    from: "0x1234123412341234123412341234123412341234",
    to: "0x5678567856785678567856785678567856785678"
  },
  ThorSwap: {
    from: "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
    to: "0xdeedbeefdeedbeefdeedbeefdeedbeefdeedbeef"
  }
};
async function executeSwap(tokenIn, tokenOut, amount, userAddr) {
  switch (selectedAggregator) {
    case "PulseX":
      return swapPulseX(tokenIn, tokenOut, amount, userAddr);
    case "Ray":
      return swapRay(tokenIn, tokenOut, amount, userAddr);
    case "ZK":
      return swapZK(tokenIn, tokenOut, amount, userAddr);
    case "9mm":
      return swap9mm(tokenIn, tokenOut, amount, userAddr);
    case "Piteas":
      return swapPiteas(tokenIn, tokenOut, amount, userAddr);
    case "Uniswap":
      return swapUniswap(tokenIn, tokenOut, amount, userAddr);
    case "PancakeSwap":

