var SafeMath            = artifacts.require("./SafeMath.sol");
var MinervaToken        = artifacts.require("./MinervaToken.sol");
// var Bounties      = artifacts.require("./Bounties.sol");
// var Consensus     = artifacts.require("./Consensus.sol");
var Crowdsale           = artifacts.require("./Crowdsale.sol");
//var MultiSigWallet      = artifacts.require("./MultiSigWallet.sol");
// var MVP           = artifacts.require("./MVP.sol");
//var Subscriptions = artifacts.require("./Subscriptions.sol");

module.exports = function(deployer) {
  deployer.deploy(SafeMath);
  deployer.link(SafeMath, MinervaToken);
  deployer.deploy(MinervaToken);

  //deployer.deploy(Bounties);
  //deployer.deploy(Consensus);
  deployer.link(SafeMath, Crowdsale);
  //deployer.deploy(MultiSigWallet);
  //deployer.deploy(Crowdsale);
  //deployer.deploy(MVP);
  //deployer.deploy(Subscriptions);
};
