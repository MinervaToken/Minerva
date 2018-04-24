pragma solidity ^0.4.17;
import "./SafeMath.sol";
/** 
  * @title Minerva Token
  * @dev Primarily an ERC20 contract with a few extra functions: 
  * bonus value is added if transferring to partner,
  * vote allows one to vote on the current USD:OWL conversion rate from token
  * voteAndTransfer function allows you to vote at in the same function your transfer,
  * updatePartner, updateVote, etc. are used for the owner (or owners) to update the contract.
**/

contract VotingBooth { function submitVotes(uint256[] _votes, address _voter, uint256 _deposit) public; }


contract MinervaToken {
    using SafeMath for uint256;
    
    /* Public variables of the token */
    string public name          = "Minerva";
    string public symbol        = "OWL";
    uint256 public decimals     = 18;
    uint256 public totalSupply;                                         // Supply decided by number of coins minted in crowdsale

    address minter;                                                     // Crowdsale contract is the minter
    address public owner;                                               // Consensus contract that can update
    address public votingAddress;                                       // Address where voting contract is located
    // Do we need crowdsaleAddress public?
    address public crowdsaleAddress;                                    // Address of the crowdsale contract to confirm initial distribution info
    uint256 public taxRate;                                             // Rate at which rewards are taxed for voting, MVP, and foundation
    address public bankAddress;                                         // Address where voting/MVP bank is located
    uint256 public rewardRate;                                          // Current reward rate--changed by reward calculator; 2 digits to signify 1 decimal place

    /* Mapping of all partners affiliated with Minerva -- partner address => bonus percent */
    mapping (address => uint256) public partners;
    mapping (address => uint256) public balances;
    mapping (address => mapping (address => uint256)) public allowed;

    /* Public events for the eponymous functions */
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Burn(address indexed from, uint256 value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    event Mint(address indexed to, uint256 amount);

    /**
     * @dev Initializes contract, assigning owner for updating variables (consensus) and crowdsale as minter
     * @param _owner Consensus or DAO that controls all functions on this contract
     * @param _minter Contract (crowdsale) that can mint coins during our crowdsale
    **/
    function MinervaToken(address _owner, address _minter) public {
        owner = _owner;                                                     // Owner--used for permission to set partner bonuses
        minter = _minter;                                                   // Crowdsale contract is only minter
    }
    
    function transfer(address _to, uint256 _value) 
      public
    returns (bool success) 
    {
        require(_to != address(0));                                                          // Prevent transfer to 0x0 address. Use burn() instead
        require(balances[msg.sender] >= _value);                                   // Check if the sender has enough

        uint256 bonus;                                                              // Declare bonus, 0 if not partner
        if (partners[_to] > 0) {
            bonus = addTokens(_value, partners[_to]);            // Add the reward if transaction is to partner       
        }
        balances[msg.sender] = balances[msg.sender].sub(_value);                  // Subtract from the sender
        balances[_to] = balances[_to].add(_value.add(bonus));                     // Add the same to the recipient
        Transfer(msg.sender, _to, _value);                                          // Notify anyone listening that this transfer took place
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) 
      external
    returns (bool success) 
    {
        require(_to != address(0));                                                          // Prevent transfer to 0x0 address. Use burn() instead
        require(balances[_from] >= _value);                                        // Require from address has enough balance
        require(allowed[_from][msg.sender] >= _value);                            // Check allowance

        uint256 _bonus;
        if (partners[_to] > 0) {
            _bonus = addTokens(_value, partners[_to]);                  // Add the reward if transaction is to partner       
        }
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);    // Subtract from allowance
        balances[_from] = balances[_from].sub(_value);                            // Subtract from sender
        balances[_to] = balances[_to].add(_value.add(_bonus));                    // Add the same to the recipient
        Transfer(_from, _to, _value);                                               // This happens early so value is what was sent, not received in case of partner
        return true;
    }

    function approve(address _spender, uint256 _value)
      external
    returns (bool success) 
    {
        // protects race condition
        require((_value == 0) || (allowed[msg.sender][_spender] == 0));
        
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function burn(uint256 _value) 
      external
    returns (bool success) 
    {
        require(balances[msg.sender] >= _value);                       // Check if the sender has enough
        balances[msg.sender] = balances[msg.sender].sub(_value);      // Subtract from the sender
        totalSupply = totalSupply.sub(_value);                          // Updates totalSupply
        Burn(msg.sender, _value);
        return true;
    }

    function burnFrom(address _from, uint256 _value) 
      external
    returns (bool success) 
    {
        require(balances[_from] >= _value);                                        // Check if the sender has enough
        require(_value <= allowed[_from][msg.sender]);                            // Check allowance
        balances[_from] = balances[_from].sub(_value);                            // Subtract from the sender
        totalSupply = totalSupply.sub(_value);                                      // Updates totalSupply
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);    // remove value from allownace
        Burn(_from, _value);
        return true;
    }
    
    /**
     * @dev Return total supply of token.
    **/
    function totalSupply() 
      external
      view 
    returns (uint256) 
    {
        return totalSupply;
    }

    /**
     * @dev Return balance of a certain address.
     * @param _owner The address whose balance we want to check.
    **/
    function balanceOf(address _owner)
      external
      view 
    returns (uint256) 
    {
        return balances[_owner];
    }
    
    /**
     * @dev Return the allowed amount of tokens to be trasnferFrom'd.
     * @param _owner The current owner of the tokens.
     * @param _spender The address allowed to spend the owner's tokens.
    **/
    function allowance(address _owner, address _spender)
      external
      view
    returns (uint256)
    {
        return allowed[_owner][_spender];
    }

/** ***************************** Custom ******************************** **/
    
    /**
     * @dev Just a normal vote. Will be costly so not likely to be used alone (see transferAndVote)
     * @param _votes Array of recent market prices of the Minerva token
     * @param _deposit The deposit put down that will give assign your vote weight and reward
    **/
    function vote(uint256[] _votes, uint256 _deposit) public
        returns (bool success) 
    {
        require(votingAddress != address(0));                                                // Voting contract must exist
        require(_deposit > 0);                                                      // Deposit to vote must be made
        require(transfer(votingAddress, _deposit));                                  // Transfer deposit...is this too costly?
        VotingBooth(votingAddress).submitVotes(_votes, msg.sender, _deposit);       // Enact actual votes

        return true;
    }
        
    
    /**
     * @dev Transfer like normal but also vote on current exchange price in one tx.
     * @dev If voting address is set to 0, this can't be used.
     * @param _value The amount of tokens to transferAndVote
     * @param _to The address to transfer tokens to
     * @param _votes An array of recent market prices of Minerva tokens at different times
     * @param _deposit The deposit to put down for voting
    **/
    function transferAndVote(uint256 _value, address _to, uint256[] _votes, uint256 _deposit)
      external
    returns (bool success) 
    {
        require(votingAddress != address(0));                                                // Voting contract must exist
        require(transfer(_to, _value));                                              // Transfer from msg.sender like normal
        require(vote(_votes, _deposit));                                             // Vote from msg.sender like normal
        return true;
    }
    
/** *************************** onlyMinter ******************************* **/
    
    /**
     * @dev Only useable by crowdsale contract while the crowdsale is active 
     * @param _to The recipient address of the minted coins
     * @param _value The amount of coins to mint
    **/
    function mint(address _to, uint256 _value)
      external
      onlyMinter
    returns (bool success)
    {
        require(_to != address(0));
        require(_value > 0);
        balances[_to] = balances[_to].add(_value);
        totalSupply = totalSupply.add(_value);
        
        Mint(_to, _value);

        return true;
        
    }
    
/** ************************** ownerOrVoting ***************************** **/
    
    /**
     * @dev Used to update the current reward rate.
     * @dev This rate is a multiple digit uint that signifies 1 decimal place (21 reward rate = 2.1%)
     * @param _rewardRate the % bonus a partner will get for each transaction
    **/
    function updateReward(uint256 _rewardRate) 
      external
      ownerOrVoting
    returns (bool success) 
    {
        rewardRate = _rewardRate;
        return true;
    }

    function getRewardRate()
        external view
    returns (uint256) 
    {
        return rewardRate;
    }        


/** **************************** onlyOwner ******************************* **/
    
    /**
     * @dev All variables an owner (the consensus contract for now) can update
     * @param _tax The tax that should be taken from partner rewards for MVP bank
     * @param _votingAddress The address allowed to change reward rate
     * @param _bank The address where taxes are sent
     * @param _owner The consensus/DAO that can edit these variables
    **/
    function ownerUpdate(uint256 _tax, address _votingAddress, address _bank, address _owner)
      external
      onlyOwner
    returns (bool success)
    {
        if (_tax != 0) {
            if (_tax >= 101) {
                taxRate = 0;
            } else {
                taxRate = _tax; 
            }
        }
        if (_votingAddress != address(0)) {
            votingAddress = _votingAddress; 
        }

        if (_bank != address(0)) {
            bankAddress = _bank;
        }

        if (_owner != address(0)) {
            owner = _owner;
        }

        return true;
    }

    function getOwner()
        external view
    returns (address) 
    {
        return owner;
    }        

    function getVotingAddress()
        external view
    returns (address) 
    {
        return votingAddress;
    }        

    function getBankAddress()
        external view
    returns (address) 
    {
        return bankAddress;
    }        

    function getTaxRate()
        external view
    returns (uint256) 
    {
        return taxRate;
    }        

    
    /**
     * @dev Updates the percent of the reward rate the partner gets (100 = default)
     * @param _partner The address of the partner merchant
     * @param _bonus The percent of the reward rate the partner will received
    **/
    function updatePartner(address _partner, uint256 _bonus) 
      external
      onlyOwner
    returns (bool success) 
    {
        partners[_partner] = _bonus;
        return true;
    }

    function isPartner(address _partner)
        external view
    returns (bool success) 
    {
        require(partners[_partner] > 0);
        return true;
    }
    
/** *************************** Internal ********************************* **/
    
    /**
     * @dev Adds bonus -- to be used in transfer if _to == partner
     * @dev partners mapping will show what % of default bonus partner will received
     * @param _value The amount of tokens originally sent in the transaction
     * @param _bonus The bonus percent a partner will receive
     * @return partnerTokens The number of tokens that should be added to the transaction
    **/
    function addTokens(uint256 _value, uint256 _bonus) 
      internal 
    returns (uint256 partnerTokens) 
    {
        uint256 defaultNewTokens = (_value.mul(rewardRate)).div(1000);               // Default bonus value for merchant partners--rewardRate is not just a % but % with 1 decimal
        uint256 newTokens = (defaultNewTokens.mul(_bonus)).div(100);                // Bonus tokens after taking into account individual partner bonus
        uint256 taxTokens = (newTokens.mul(taxRate)).div(100);                      // Taxes are taken out of reward
        partnerTokens = newTokens.sub(taxTokens);                           // Tokens to go to partner website
        
        totalSupply = totalSupply.add(newTokens);                           // Add the newly minted coins to total supply
        balances[bankAddress] = balances[bankAddress].add(taxTokens);
        return partnerTokens;
    }
    
/** *************************** Modifiers ******************************** **/
    
    /**
     * @dev This modifier used to update variables--will start as Consensus.sol 
    **/
    modifier onlyOwner() 
    {
        require(msg.sender == owner);
        _;
    }
    
    /**
     * @dev ONLY the crowdsale address is allowed to mint (owner may mint presales through that)
    **/
    modifier onlyMinter() 
    {
        require(msg.sender == minter);
        _;
    }
    
    /**
     * @dev Must allow only owner (consensus) or voting contract for reward rate changes.
    **/
    modifier ownerOrVoting() 
    {
        require(msg.sender == owner || msg.sender == votingAddress);
        _;
    }

}
