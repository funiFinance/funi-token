module.exports = {
  networks: {
      bscTestnet: {
          host: "https://data-seed-prebsc-1-s1.binance.org",
          port: 8545,
          network_id: "97",
      },
      bscMainnet: {
          host: "https://bsc-dataseed.binance.org",
          port: 8545,
          network_id: "56",
      },
  },
  compilers: {
      solc: {
          version: "0.6.12"
      },
  },
  plugins: [
      'truffle-plugin-verify'
  ]
};