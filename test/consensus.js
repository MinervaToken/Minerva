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

const Consensus = artifacts.require('../contracts/Consensus')
const MinervaToken = artifacts.require('../contracts/MinervaToken')

contract('Consensus', function ([_, wallet]) {

  before(async function() {
    //Advance to the next block to correctly read time in the solidity "now" function interpreted by testrpc
    await advanceBlock()
 
    this.owner  = web3.eth.accounts[0];
    this.voter1 = web3.eth.accounts[1];
    this.voter2 = web3.eth.accounts[2];
    this.voter3 = web3.eth.accounts[3];
    this.voter4 = web3.eth.accounts[4];
    this.voter5 = web3.eth.accounts[5];
    this.voter6 = web3.eth.accounts[6];
    this.voter7 = web3.eth.accounts[7];
    this.voter8 = web3.eth.accounts[8];

    this.nonvoter = web3.eth.accounts[9];

    this.consensus = await Consensus.new(this.voter1, this.voter2, this.voter3)
    this.token = await MinervaToken.new(this.owner, this.owner);

    this.token.ownerUpdate(0, 0, 0, this.consensus.address);

    await this.consensus.setToken(this.token.address)

  })

  describe("-- ADD/REMOVE VOTER FUNCTIONALITY --", function() {

    it('should fail if not a registered voter', async function () {
      await this.consensus.voteVoter(this.nonvoter, {from: this.nonvoter}).should.be.rejectedWith(EVMRevert);
    })

    it('should fail to add an already registered voter', async function () {
      await this.consensus.voteVoter(this.voter1, {from: this.nonvoter}).should.be.rejectedWith(EVMRevert);
    })

    it('should cast votes and add voter', async function () {
      await this.consensus.voteVoter(this.nonvoter, {from: this.voter1});
      await this.consensus.voteVoter(this.nonvoter, {from: this.voter2});
      await this.consensus.voteVoter(this.voter4, {from: this.nonvoter}); // new voter has access now
    })

    it('should cast votes and fail because new voter is already registered', async function () {
      await this.consensus.voteVoter(this.nonvoter, {from: this.voter1}).should.be.rejectedWith(EVMRevert);
    })

    it('should cast votes and remove voter', async function () {

      let total = await this.consensus.totalVoters();
      total.should.be.bignumber.equal(4);

      await this.consensus.voteRemoveVoter(this.voter3, {from: this.voter1});
      await this.consensus.voteRemoveVoter(this.voter3, {from: this.voter2});

      total = await this.consensus.totalVoters();
      total.should.be.bignumber.equal(3);
    })

    it('cast votes and remove voter nonvoter for next tests', async function () {
      await this.consensus.voteRemoveVoter(this.nonvoter, {from: this.voter1});
      await this.consensus.voteRemoveVoter(this.nonvoter, {from: this.voter2});

      let total = await this.consensus.totalVoters();
      total.should.be.bignumber.equal(2);
    })

    it('should fail to remove a voter if we only have 2', async function () {
      await this.consensus.voteRemoveVoter(this.voter1, {from: this.voter2}).should.be.rejectedWith(EVMRevert);
    })

    it('should fail when newly removed voter tries to vote', async function () {
      await this.consensus.voteRemoveVoter(this.voter1, {from: this.nonvoter}).should.be.rejectedWith(EVMRevert);
    })

  })

  describe("-- TOKEN INTERACTION FUNCTIONS --", function() {

    it('change owner of minerva token to nonvoter', async function () {
      await this.consensus.voteOwner(this.nonvoter, {from: this.voter1});
      await this.consensus.voteOwner(this.nonvoter, {from: this.voter2});

      let owner = await this.token.owner.call()
      owner.should.equal(this.nonvoter);
    })

    it('change owner should fail', async function () {
      await this.consensus.voteOwner(this.consensus.address, {from: this.voter1});
      await this.consensus.voteOwner(this.consensus.address, {from: this.voter2}).should.be.rejectedWith(EVMRevert);
    })

    it('change owner back to consensus', async function () {
      let tx = await this.token.ownerUpdate(0, 0, 0, this.consensus.address, {from: this.nonvoter});
      assert.isOk(tx)
    })

    it('change bank address of minerva token to nonvoter', async function () {
      await this.consensus.voteBank(this.nonvoter, {from: this.voter1});
      await this.consensus.voteBank(this.nonvoter, {from: this.voter2});

      let bank = await this.token.bankAddress.call();
      bank.should.equal(this.nonvoter);
    })

    it('change voting address of minerva token to nonvoter', async function () {
      await this.consensus.voteBooth(this.nonvoter, {from: this.voter1});
      await this.consensus.voteBooth(this.nonvoter, {from: this.voter2});

      let voting = await this.token.votingAddress.call()
      voting.should.equal(this.nonvoter);
    })

    it('change tax of minerva token to 50', async function () {
      await this.consensus.voteTax(50, {from: this.voter1});
      await this.consensus.voteTax(50, {from: this.voter2});

      let tax = await this.token.taxRate.call()
      tax.should.be.bignumber.equal(50);
    })

    it('add new partner (nonvoter) to minerva token', async function () {
      await this.consensus.votePartner(this.nonvoter, 100, {from: this.voter1});
      await this.consensus.votePartner(this.nonvoter, 100, {from: this.voter2});

      let isPartner = await this.token.isPartner(this.nonvoter);
      isPartner.should.equal(true);
    })


  })


})