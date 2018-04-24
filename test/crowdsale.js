import ether from './helpers/ether'
import {advanceBlock} from './helpers/advanceToBlock'
import {increaseTimeTo, duration} from './helpers/increaseTime'
import latestTime from './helpers/latestTime'
import EVMRevert from './helpers/EVMRevert'

const BigNumber = web3.BigNumber

const should = require('chai')
  .use(require('chai-as-promised'))
  .use(require('chai-bignumber')(BigNumber))
  .should()

const MinervaToken       = artifacts.require('../contracts/MinervaToken')
const Crowdsale          = artifacts.require('../contracts/Crowdsale')
const MultiSigWallet     = artifacts.require('../contracts/MultiSigWallet')

// Promisify get balance of ether
const promisify = (inner) =>
  new Promise((resolve, reject) =>
    inner((err, res) => {
      if (err) { reject(err) }
      resolve(res);
    })
  );

const getBalance = (account, at) =>
  promisify(cb => web3.eth.getBalance(account, at, cb));

contract('Crowdsale', function ([_, wallet]) {

  before(async function() {
    //Advance to the next block to correctly read time in the solidity "now" function interpreted by testrpc
    await advanceBlock()

    this.owner        = web3.eth.accounts[9];
    this.owner2       = web3.eth.accounts[8];
    this.participant1 = web3.eth.accounts[1];
    this.participant2 = web3.eth.accounts[2];
    this.participant3 = web3.eth.accounts[3];
    this.participant4 = web3.eth.accounts[4];
    this.participant5 = web3.eth.accounts[5];

    this.startTime    = latestTime() + duration.minutes(15)
    this.endTime      = latestTime() + duration.hours(15)
    this.usdRaised    = 0
    this.hardCap      = 650000


    this.multisig = await MultiSigWallet.new([this.owner, this.owner2], 2, {from: this.owner});

    this.crowdsale = await Crowdsale.new(
      this.startTime, 
      this.endTime, 
      this.hardCap, 
      this.owner, 
      this.multisig.address, 
      this.multisig.address,
      15
      ,{from: this.owner});

    this.token = await MinervaToken.new(this.owner, this.crowdsale.address);
      
  })

  describe('-- PREP FUNCTIONALITY CHECKS --', function () {

    it('should have cap of $6,500 USD', async function () {
      let cap = await this.crowdsale.cap.call();
      cap.should.be.bignumber.equal(this.hardCap);
    })

    it('should have correct owner', async function () {
      let owner = await this.crowdsale.owner.call();
      owner.should.be.equal(this.owner);
    })

    it('should set token to MinervaToken', async function () {
      let tx = await this.crowdsale.setToken(this.token.address, {from: this.owner});
      assert.isOk(tx);

      let address = await this.crowdsale.getTokenAddress();
      address.should.be.equal(this.token.address);
    })

    it('should fail to set new MinervaToken by non owner', async function () {
      await this.crowdsale.setToken(this.token.address, {from: this.participant1}).should.be.rejectedWith(EVMRevert);
    })

    it('should fail to set new MinervaToken to 0x0', async function () {
      await this.crowdsale.setToken("0x0", {from: this.owner}).should.be.rejectedWith(EVMRevert);
    })

    it('should fail to set new MinervaToken to non contract', async function () {
      await this.crowdsale.setToken(this.owner, {from: this.owner}).should.be.rejectedWith(EVMRevert);
    })

  })

  describe('-- PRE CROWDSALE CHECKS --', function () {

    it('update timeframe to new values', async function () {

      let startTime = latestTime() + duration.minutes(60)
      let endTime = latestTime() + duration.hours(3)

      let tx = await this.crowdsale.updateTimeframe(startTime, endTime, {from: this.owner});
      assert.isOk(tx);

      let start = await this.crowdsale.startTime.call();
      start.should.be.bignumber.equal(startTime);
      let end = await this.crowdsale.endTime.call();
      end.should.be.bignumber.equal(endTime);

      this.startTime = startTime
      this.endTime = endTime

    })

    it('update per owl price to $0.20 usd', async function () {

      let tx = await this.crowdsale.setOwlPrice(20, {from: this.owner});
      assert.isOk(tx);

      let price = await this.crowdsale.perOwlPrice.call();
      price.should.be.bignumber.equal(20);

    })

    it('should fail to buy tokens before crowdsale starts', async function () {
      await this.crowdsale.buyTokens(this.participant1, { value: ether(1), from: this.participant1 }).should.be.rejectedWith(EVMRevert);
    })

    it('should fail to send ether to fallback before crowdsale starts', async function () {
      try {
        await web3.eth.sendTransaction({
            from: this.participant1, 
            to: this.crowdsale.address, 
            value: ether(1)
        });
      } catch(error) {
        assert.isAbove(error.message.search('revert'), -1, 'Reverted');
      }
    })

    it('should fail to dispurse team tokens before crowdsale starts', async function () {
      await this.crowdsale.disburseTeamTokens({from: this.owner}).should.be.rejectedWith(EVMRevert);
    })

    it('should fail to pause crowdsale before it starts', async function () {
      await this.crowdsale.manualPause(true, {from: this.owner}).should.be.rejectedWith(EVMRevert);
    })
    
    it('should show crowdsale has not ended yet', async function () {
      let ended = await this.crowdsale.hasEnded();
      ended.should.be.equal(false);
    })

    it('update conversion rate of ETH:USD to $1000.00', async function () {
      let tx = await this.crowdsale.updateConversion(100000, {from: this.owner});
      assert.isOk(tx)

      let cents = await this.crowdsale.usdCentsPerEther.call();
      cents.should.be.bignumber.equal(100000)

    })

    it('set discount rates', async function () {
      let tx = await this.crowdsale.setDiscountRate(40, 1, {from: this.owner});
      assert.isOk(tx)

      tx = await this.crowdsale.setDiscountRate(30, 3, {from: this.owner});
      assert.isOk(tx)

      tx = await this.crowdsale.setDiscountRate(20, 7, {from: this.owner});
      assert.isOk(tx)

    })

  })

  describe('-- CROWDSALE ACTIVE --', function () {

    it('increase time to simulate crowdsale has begun', async function () {
      await increaseTimeTo(this.startTime + duration.hours(1))
    })

    it('participant 1 sending ether should fail because they are no accredited', async function () {
      await this.crowdsale.buyTokens(this.participant1, { value: ether(1), from: this.participant1 }).should.be.rejectedWith(EVMRevert);
    })

    it('try adding a contract to accredited parties and fail', async function () {
      await this.crowdsale.addAccreditedParty(this.token.address, {from: this.owner}).should.be.rejectedWith(EVMRevert);
    })

    it('add accredited parties', async function () {
      let tx = await this.crowdsale.addAccreditedParty(this.participant1, {from: this.owner});
      assert.isOk(tx);
      tx = await this.crowdsale.addAccreditedParty(this.participant2, {from: this.owner});
      assert.isOk(tx);
      tx = await this.crowdsale.addAccreditedParty(this.participant3, {from: this.owner});
      assert.isOk(tx);
      tx = await this.crowdsale.addAccreditedParty(this.participant4, {from: this.owner});
      assert.isOk(tx);
      tx = await this.crowdsale.addAccreditedParty(this.participant5, {from: this.owner});
      assert.isOk(tx);
    })

    it('participant 1 should buy 1 ether worth of tokens', async function () {
      let tx = await this.crowdsale.buyTokens(this.participant1, { value: ether(1), from: this.participant1 });
      assert.isOk(tx)

      let tokens = await this.token.balanceOf(this.participant1);
      let calcTokenValue = calculateTokenAmount(1, 1000, 40, 20); // 8333.333333333334 -> 1 ether @ $1000 usd

      // rounded to 1 precision because of bignumber 15 digit warnings
      let roundedTokens = Math.floor(web3.fromWei(tokens, "ether").toNumber())
      let roundedCalcValue = Math.floor(calcTokenValue)

      roundedTokens.should.be.equal(roundedCalcValue)

      let usdRaised = await this.crowdsale.usdRaised.call()
      usdRaised.should.be.bignumber.equal(this.usdRaised + 100000);
      this.usdRaised += 100000;

      console.log("contract usd: ", usdRaised.toNumber());
      console.log("internal usd: ", this.usdRaised)

    })

    it('make sure multisig has 1 ether in it', async function () {
      let sigBalance = await getBalance(this.multisig.address);
      sigBalance.should.be.bignumber.equal(ether(1));
    })

    it('should pause crowdsale', async function () {
      let tx = await this.crowdsale.manualPause(true, {from: this.owner});
      assert.isOk(tx)
    })

    it('participant 2 should fail to buy tokens because crowdsale is paused', async function () {
      await this.crowdsale.buyTokens(this.participant1, { value: ether(1), from: this.participant1 }).should.be.rejectedWith(EVMRevert);
    })

    it('should unpause crowdsale', async function () {
      let tx = await this.crowdsale.manualPause(false, {from: this.owner});
      assert.isOk(tx)
    })

    it('participant 2 should buy 1.4353 ether worth of tokens', async function () {
      let tx = await this.crowdsale.buyTokens(this.participant2, { value: ether(1.4353), from: this.participant2 });
      assert.isOk(tx)

      let tokens = await this.token.balanceOf(this.participant2);
      let calcTokenValue = calculateTokenAmount(1.4353, 1000, 30, 20);

      // rounded to 1 precision because of bignumber 15 digit warnings
      let roundedTokens = Math.floor(web3.fromWei(tokens, "ether").toNumber())
      let roundedCalcValue = Math.floor(calcTokenValue)

      roundedTokens.should.be.equal(roundedCalcValue)

      let usdRaised = await this.crowdsale.usdRaised.call()
      usdRaised.should.be.bignumber.equal(this.usdRaised + 143530);
      this.usdRaised += 143530;

      console.log("contract usd: ", usdRaised.toNumber());
      console.log("internal usd: ", this.usdRaised)

    })

    it('make sure multisig has 2.4353 ether in it', async function () {
      let sigBalance = await getBalance(this.multisig.address);
      sigBalance.should.be.bignumber.equal(ether(2.4353));
    })

    it('update conversion rate of ETH:USD to $1102.51', async function () {
      let tx = await this.crowdsale.updateConversion(110251, {from: this.owner});
      assert.isOk(tx)

      let cents = await this.crowdsale.usdCentsPerEther.call();
      cents.should.be.bignumber.equal(110251)

    })

    it('participant 3 should buy 3.214 ether worth of tokens at new conversion price (triggers discount overflow)', async function () {
      let tx = await this.crowdsale.buyTokens(this.participant3, { value: ether(3.214), from: this.participant3 });
      assert.isOk(tx)

      let tokens = await this.token.balanceOf(this.participant3);

      // calculate the remaining cap of 30% discount range
      let calcTokenValue = calculateTokenAmount(0.5647, 1102.51, 30, 20); // 8333.333333333334 -> 1 ether @ $1000 usd
      let roundedCalcValue = Math.floor(calcTokenValue)

      // calculate the second batch of discounting that will trigger 
      calcTokenValue = calculateTokenAmount(2.6493, 1102.51, 20, 20); // 8333.333333333334 -> 1 ether @ $1000 usd
      roundedCalcValue += Math.floor(calcTokenValue)

      // rounded to 1 precision because of bignumber 15 digit warnings
      let roundedTokens = Math.floor(web3.fromWei(tokens, "ether").toNumber())

      roundedTokens.should.be.equal(roundedCalcValue)

      let usdRaised = await this.crowdsale.usdRaised.call()
      console.log("usd: ", usdRaised.toNumber())
      usdRaised.should.be.bignumber.equal(this.usdRaised + Math.floor(354346.714));
      this.usdRaised += Math.floor(354346.714);

      console.log("contract usd: ", usdRaised.toNumber());
      console.log("internal usd: ", this.usdRaised)
    })

    it('make sure multisig has 5.6493 ether in it', async function () {
      let sigBalance = await getBalance(this.multisig.address);
      sigBalance.should.be.bignumber.equal(ether(5.6493));
    })

    it('block participant4', async function () {
      let tx = await this.crowdsale.blockAccreditedParty(this.participant4, {from: this.owner});
      assert.isOk(tx);
    })

    it('participant 3 from should fail trying to send to a blocked beneficiary', async function () {
      await this.crowdsale.buyTokens(this.participant4, { value: ether(1), from: this.participant3 }).should.be.rejectedWith(EVMRevert);
    })

    it('participant 4 from should fail after being blocked', async function () {
      await this.crowdsale.buyTokens(this.participant4, { value: ether(1), from: this.participant1 }).should.be.rejectedWith(EVMRevert);
    })

    it('should fail to set a new token mid crowdsale', async function () {
      await this.crowdsale.setToken(this.token.address, {from: this.owner}).should.be.rejectedWith(EVMRevert);
    })

    it('participant 5 from should get reach hardcap and get refunded the rest', async function () {

      let remaining = Math.floor(this.hardCap - this.usdRaised)
      let remainingEther = (remaining / 110251)

      // get previous amount of ether for participant 5
      let prevBalance = await getBalance(this.participant5)
      console.log("prev ether balance: ", prevBalance.toNumber())

      // send 1 ether to cap the crowdsale
      let tx = await this.crowdsale.buyTokens(this.participant5, { value: ether(1), from: this.participant5 });
      assert.isOk(tx)

      // calculate gas used on transaction
      let gasUsed = web3.toWei(tx["receipt"]["gasUsed"] / 10000, "finney")

      // get post balance of ether for participant 5
      let postBalance = await getBalance(this.participant5)
      console.log("post ether balance: ", postBalance.toNumber())

      // calculate refunds internally and from wallet balances
      let calculatePost = ether(1) - ether(remainingEther) - gasUsed - 7200
      let calculateRefund = ether(1) - (prevBalance.toNumber() - postBalance.toNumber())

      console.log("calc ether balance:", calculatePost)
      console.log("calc refund:", calculateRefund)

      // make sure refund is accurate (sometimes off by slight fluctuations of gas)
      calculateRefund.should.be.equal(calculatePost)

      // calculate token counts based on non-refunded ether
      let tokens = await this.token.balanceOf(this.participant5);
      let calcTokenValue = calculateTokenAmount(remainingEther, 1102.51, 20, 20);

      // rounded using math floor to match evm rounding
      let roundedTokens = Math.floor(web3.fromWei(tokens, "ether").toNumber())
      let roundedCalcValue = Math.floor(calcTokenValue)

      // calculate rounding
      roundedTokens.should.be.equal(roundedCalcValue)

      // make sure usd raised is accurately at cap
      let usdRaised = await this.crowdsale.usdRaised.call()
      usdRaised.should.be.bignumber.equal(this.usdRaised + remaining);
      this.usdRaised += remaining;

      console.log("contract usd: ", usdRaised.toNumber());
      console.log("internal usd: ", this.usdRaised)
    })

    it('participant 3 from should fail after hitting cap', async function () {
      await this.crowdsale.buyTokens(this.participant3, { value: ether(1), from: this.participant3 }).should.be.rejectedWith(EVMRevert);
    })

  })

  describe('-- CROWDSALE ENDED --', function () {

    it('increase time to simulate crowdsale has ended', async function () {
      await increaseTimeTo(this.endTime + duration.minutes(15))
    })

    it('participant 2 should fail to buy tokens because crowdsale has ended', async function () {
      await this.crowdsale.buyTokens(this.participant1, { value: ether(1), from: this.participant1 }).should.be.rejectedWith(EVMRevert);
    })

  })

  describe('-- TOKEN DISTRIBUTION --', function () {

    it('should disperse tokens to team and bounties', async function () {
      let tx = await this.crowdsale.disburseTeamTokens({from: this.owner})
      assert.isOk(tx);
    })

    it('make sure multisig has ## tokens in it', async function () {

      let tokensRaised = await this.crowdsale.tokensRaised.call()
      console.log("tokens raised", web3.fromWei(tokensRaised.toNumber(), "ether"))

      let sigTokens = await this.token.balanceOf(this.multisig.address);
      console.log("sig tokens", web3.fromWei(sigTokens.toNumber(), "ether"))
      sigTokens.should.be.bignumber.equal(ether(20044.8));
    })

    it('should fail to disperse tokens to team and bounties because theyve already been sent', async function () {
      await this.crowdsale.disburseTeamTokens({from: this.owner}).should.be.rejectedWith(EVMRevert);
    })

  })

  function calculateTokenAmount(etherAmount, usd, discount, pricePerOwl) {
     return (etherAmount * usd) / ((((100 - discount) * pricePerOwl) / 100) / 100);
  }

  function precisionRound(number, precision) {
    var factor = Math.pow(10, precision);
    return Math.round(number * factor) / factor;
  }

})