# Minerva Token, Crowdsale and Consensus Contracts

We've supplied the truffle testing inside of this repo for anyone who is interested in diving deeper into the code. All contracts presently available to the public have been security audited by a blockchain group at Berkeley.

The following smart contracts now qualify for the Minerva bug bounty:

# Minerva OWL ERC20 Token Contract: contracts/MinervaToken.sol

This contract is a standard ERC20 compliant contract with added features for Partnerships. As you can see inside of the transfer and transferFrom there is programming logic for integrated merchant platforms. The percentages at any given time will be determined by the current price of OWL/USD using a system of Oracles. 

The "ownerUpdate" function is used by the consensus contract to manage current taxation rate, voting smart contract address, bank smart contract address and owner address. 

# Crowdsale Contract: contracts/Crowdsale.sol

Our crowdsale (or token sale) contract is designed in a different way than most normal token sale contracts. We've added approved party management, which will directly reflect our KYC/AML/CFT procedures. After an interested party has completed the KYC process, we will require them to give us an Ethereum address associated with their KYC. That will be the only Ethereum address they can use to participate. Ethereum addresses for approved parties can only be added by the owner until the crowdsale has completed. We've also created a hard cap ($10MM) that is constructed around USD value instead of overall ETH value. Participants will receive the amount of OWL tokens based on current discount rate and price of ether at the time of purchase. We've done this to maintain our hard cap goal and distribute the tokens fairly despite the price of Ether in near real-time.

# Consensus Contract: contracts/Consensus.sol

The consensus contract manages the OWL token's taxation rate, ownership and has the ability to switch in and out the voting contract. We've hard coded a requirement to have at least 2 votes and 2 voters at any given time. As new voters are added that can manage the token contract, it will require as many votes that are necessary to reach a majority consensus. While the consensus contract is primarly created to change specific features of our token, it also has an internal system to add and remove new voters.
