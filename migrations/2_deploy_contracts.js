// 27 000 000
// 15% = 4 050 000
// 15 * 6 = 90%
// 4 050 000 * 6 = 24300000
// 10% = 2 700 000

var CryptoHuntGameIco = artifacts.require('CryptoHuntGameIco');
module.exports = function(deployer) {
  deployer.deploy(CryptoHuntGameIco, 600, 600, 0x440DC991000dB2e86ad5Cdd7948188c9E0d66758, 0x840172f8ab2e370c9f28214c752e69adac476d3d);
}

// var TokenTimedChestMulti = artifacts.require("TokenTimedChestMulti");
// module.exports = function(deployer) {
//   deployer.deploy(TokenTimedChestMulti);
// };
