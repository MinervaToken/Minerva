# Minerva Token, Crowdsale and Consensus Contracts

We've supplied the truffle testing inside of this repo for anyone who is interested in diving deeper into the code.
All contracts available to the public have been audited.

# Minerva ERC20 Token Contract

This contract is a standard ERC20 compliant contract with added features for Partnerships. As you can see inside of the transfer and transferFrom there is programming logic for our partners. The percentages at any given time will be determined by the current price of OWL using Oracles. 

The "ownerUpdate" function is used by the consensus contract to manage current taxation rate, voting smart contract address, bank smart contract address and owner address. 

# Crowdsale Contract

Our crowdsale contract is designed in a different way than most normal crowdsale contracts. We've added approved party management, which will directly reflect our KYC. After an interested party has completed our KYC process, we will require them to give us one ethereum address associated with their KYC. That will be the only ethereum address they can use to participate.

Ethereum addresses for approved parties can only be added by the owner until the crowdsale has completed.

We've also created a hardcap that is constructed around USD value instead of overall ETH value. Participants will receive the amount of OWL tokens based on current discount rate and price of ether at the time of purchase. We've done this to maintain our hard cap goal and distribute the tokens fairly despite the price of ether at the current moment.

# Consensus Contract

The consensus contract manages our token's taxation rate, ownership and has the ability to switch in and out our voting contract.

We've hard coded a requirement to have at least 2 votes and 2 voters at any given time. As we add more voters that can manage the token contract, it will require as many votes as needed to reach a majority.

While the consensus contract is primarly created to change specific features of our token, it also has an internal system to add and remove new voters.
