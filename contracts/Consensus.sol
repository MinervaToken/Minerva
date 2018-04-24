pragma solidity ^0.4.17;
import "./MinervaToken.sol";

contract Consensus {
    MinervaToken token;                                     // Minerva ERC20
    bool public tokenSet;                                   // Has the Minerva Token contract been set
    address[] voterArray;                                   // Array of all the voters
    uint256 public requiredVotes;                           // Number of votes to pass new owner
    mapping (address => bool) public approvedVoters;        // Voters approved by the original address
    mapping (address => Ballot) public voterBallots;        // Holds a struct with all votes for each voter
  
    struct Ballot {
        address addVoter;                                   // Add multisig voter
        address removeVoter;                                // Remove multisig voter
        uint256 requiredVotes;                              // Change votes required for multisig operations
        address owner;                                      // Change owner of token contract
        address bank;                                       // Change bank address of token contract
        address votingBooth;                                // Change voting address of token contract
        uint256 tax;                                        // Change tax given to bank on token contract
        mapping (address => uint256) partner;               // Add/change a partner merchant bonus
        mapping (address => uint256) transfer;              // Transfer team tokens off contract
    }
    
    event PartnerVote(address indexed partner, uint256 bonus);

    /**
     * @dev These first three voters will add all other voters and decide requiredVotes
     * @param _firstVoter Address of first voter in consensus
     * @param _secondVoter Address of second voter in consensus
     * @param _thirdVoter Address of third voter in consensus
    **/ 
    function Consensus(address _firstVoter, address _secondVoter, address _thirdVoter) public {
        requiredVotes = 2;
        addVoter(_firstVoter);
        addVoter(_secondVoter);
        addVoter(_thirdVoter);
    }
    
    /**
     * @dev Sets the token for Minerva ERC20 contract...once!!
     * @param _token Address of the Minerva ERC20
    **/
    function setToken(address _token)
      external
    returns (bool success)
    {
        require(!tokenSet);
        token = MinervaToken(_token);
        tokenSet = true;
        return true;
    }
    
    /**
     * @dev voteVoter is used to add an address allowed to vote
     * @param _newVoter Address of the new member in our consensus contract
     * @dev Comments here apply to all functions below!
    **/
    function voteVoter(address _newVoter) 
      external
      onlyVoter
      validAddress(_newVoter)
    returns (bool success) 
    {

        require(!approvedVoters[_newVoter]);            // reject already approved voters

        delete voterBallots[msg.sender];                // Clear the ballot of old/failed votes.
        voterBallots[msg.sender].addVoter = _newVoter;  // Declare voter's vote
        
        uint256 voteCount;
        for (uint i = 0; i < voterArray.length; i++) {   // Loop through all votes
            if (voterBallots[voterArray[i]].addVoter == _newVoter) {
                voteCount++; // Count how many are the same as voter's vote
            }
        }
        
        if (voteCount >= requiredVotes) {               // If enough votes are the same...
            require(addVoter(_newVoter));                // Action
            clearBallots();                             // Clear ballots of ALL votes (only 1 "election" can happen at a time)
        }
        return true;
    }
    
    /**
     * @dev Voters use this to remove an address/voter from their ranks
     * @param _oldVoter Address to remove voting permissions from
    **/
    function voteRemoveVoter(address _oldVoter) 
      external
      onlyVoter
      validAddress(_oldVoter)
    returns (bool success)
    {

        require(approvedVoters[_oldVoter]);                 // must be an approved voter
        require(voterArray.length > 2);                     // must maintain at least 2 approved voters

        delete voterBallots[msg.sender];
        voterBallots[msg.sender].removeVoter = _oldVoter;

        uint256 voteCount;
        for (uint i = 0; i < voterArray.length; i++) {
            if (voterBallots[voterArray[i]].removeVoter == _oldVoter) {
                voteCount++;
            }
        }
        
        if (voteCount >= requiredVotes) {
            require(removeVoter(_oldVoter));
            clearBallots();
        }
        return true;
    }

    function totalVoters() 
        external view
    returns (uint) 
    {
        return voterArray.length;        
    }
    
    /**
     * @dev voteRequired can change n in the n-of-m consensus protocl
     * @param _newRequired uint of owners required for a vote to go through
    **/
    function voteRequired(uint256 _newRequired) 
      external
      onlyVoter
      validUint(_newRequired)
    returns (bool success) 
    {
        require(_newRequired != requiredVotes);
        require(_newRequired >= 2);
        require(_newRequired <= voterArray.length);

        delete voterBallots[msg.sender];
        voterBallots[msg.sender].requiredVotes = _newRequired;
        
        uint256 voteCount;
        for (uint i = 0; i < voterArray.length; i++) {
            if (voterBallots[voterArray[i]].requiredVotes == _newRequired) {
                voteCount++;
            }
        }
        
        if (voteCount >= requiredVotes) {
            requiredVotes = _newRequired;
            clearBallots();
        }
        return true;
    }
    
    /**
     * @dev voteOwner allows a new owner (consensus or DAO--this is owner now) to be voted in
     * @param _newOwner Contract address of the new owner of the token Contract
    **/
    function voteOwner(address _newOwner) 
      external
      onlyVoter
      validAddress(_newOwner)
      isTokenSet
    returns (bool success) 
    {
        delete voterBallots[msg.sender];
        voterBallots[msg.sender].owner = _newOwner;
        
        uint256 voteCount;
        for (uint i = 0; i < voterArray.length; i++) {
            if (voterBallots[voterArray[i]].owner == _newOwner) {
                voteCount++;
            }
        }
        
        if (voteCount >= requiredVotes) {
            require(token.ownerUpdate(0, 0, 0, _newOwner));
            clearBallots();
        }   
        return true;
    }
    
    /** 
     * @dev Each voter uses this to vote for a new Minerva bank address (stores MVP funds)
     * @param _newBank Address of the new bank for funds to be given to
    **/
    function voteBank(address _newBank) 
      external
      onlyVoter
      validAddress(_newBank)
      isTokenSet
    returns (bool success) 
    {
        delete voterBallots[msg.sender];
        voterBallots[msg.sender].bank = _newBank;
        
        uint256 voteCount;
        for (uint i = 0; i < voterArray.length; i++) {
            if (voterBallots[voterArray[i]].bank == _newBank) {
                voteCount++;
            }
        }
        
        if (voteCount >= requiredVotes) {
            require(token.ownerUpdate(0, 0, _newBank, 0));
            clearBallots();
        }
        return true;
    }
    
    /**
     * @dev voteBooth allows users to vote in a new contract that can change reward ownerUpdate
     * @param _newBooth Address of the new Schelling point voting contract
    **/
    function voteBooth(address _newBooth) 
      external
      onlyVoter
      validAddress(_newBooth)
      isTokenSet
    returns (bool success) 
    {
        delete voterBallots[msg.sender];
        voterBallots[msg.sender].votingBooth = _newBooth;
        
        uint256 voteCount;
        for (uint i = 0; i < voterArray.length; i++) {
            if (voterBallots[voterArray[i]].votingBooth == _newBooth) {
                voteCount++;
            }
        }
        
        if (voteCount >= requiredVotes) {
            require(token.ownerUpdate(0, _newBooth, 0, 0));
            clearBallots();
        }
        return true;
    }
    
    /**
     * @dev Each voter uses this to vote for a new Minerva reward tax (tax goes to mvp bank)
     * @param _newTax New % we want to take from rewards to give to company/bank
    **/
    function voteTax(uint256 _newTax) 
      external
      onlyVoter
      validUint(_newTax)
      isTokenSet
    returns (bool success) 
    {
        delete voterBallots[msg.sender];
        voterBallots[msg.sender].tax = _newTax;
        
        uint256 voteCount;
        for (uint i = 0; i < voterArray.length; i++) {
            if (voterBallots[voterArray[i]].tax == _newTax) {
                voteCount++;
            }
        }
        
        if (voteCount >= requiredVotes) {
            require(token.ownerUpdate(_newTax, 0, 0, 0));
            clearBallots();
        }
        return true;
    }
    
    /**
     * @dev Used to update/add merchant partner % bonus -- 100 equals default reward rate
     * @dev To make the bonus 0, we must vote for a bonus of 10000
     * @param _newPartner Ethereum address of the new merchant partner
     * @param _newBonus Bonus that new partner will receive
    **/
    function votePartner(address _newPartner, uint256 _newBonus) 
      external
      onlyVoter
      validAddress(_newPartner)
      isTokenSet
    returns (bool success) 
    {
        require(_newBonus > 0);
        
        delete voterBallots[msg.sender];
        voterBallots[msg.sender].partner[_newPartner] = _newBonus;
        
        uint256 voteCount;
        for (uint i = 0; i < voterArray.length; i++) {
            if (voterBallots[voterArray[i]].partner[_newPartner] == _newBonus) {
                voteCount++;
            }
        }
        
        uint256 passBonus = _newBonus;
        if (_newBonus == 10000) {
            passBonus = 0;
        } 
        if (voteCount >= requiredVotes) {
            require(token.updatePartner(_newPartner, passBonus));
            PartnerVote(_newPartner, passBonus);
            clearBallots();
        }
        return true;
    }
    
    /**
     * @dev Each voter uses this to vote for a new token transfer.
     * @dev These transfers can only happen after 12 months.
     * @param _to Address to transfer tokens to
     * @param _amount Amount of tokens to be transferred
    **/
    function voteTransfer(address _to, uint256 _amount) 
      external
      onlyVoter 
      validAddress(_to)
      validUint(_amount)
      isTokenSet
    returns (bool success) 
    {
        delete voterBallots[msg.sender];
        voterBallots[msg.sender].transfer[_to] = _amount;
        
        uint256 voteCount;
        for (uint i = 0; i < voterArray.length; i++) {
            if (voterBallots[voterArray[i]].transfer[_to] == _amount) {
                voteCount++;
            }
        }
        
        if (voteCount >= requiredVotes) {
            require(token.transfer(_to, _amount));
            clearBallots();
        }
        return true;
    }
    
/** *************************** Internal *************************** **/
    
    /**
     * @dev Voters must vote to enact addVoter to add a voting address 
     * @param _newVoter Address to give voting rights to
    **/
    function addVoter(address _newVoter) 
      internal
    returns (bool success) 
    {
        approvedVoters[_newVoter] = true;
        voterArray.push(_newVoter);        
        updateRequiredVotes();
        return true;
    }

    function updateRequiredVotes()
        internal
    returns (bool success)
    {

        // maintain at least 2 votes at all times
        if (voterArray.length == 2) {
            requiredVotes = 2;
            return true;
        }

        uint newRequiredVotes = voterArray.length % 2;

        if (newRequiredVotes != 0) {
            newRequiredVotes = voterArray.length / 2 + 1;
        } else {
            newRequiredVotes = voterArray.length / 2;
        }

        requiredVotes = newRequiredVotes;

        return true;
    }
    
    /**
     * @dev Voters must vote to enact removeVoter to get rid of a voting address
     * @param _oldVoter Address whose voting rights are being removed
    **/
    function removeVoter(address _oldVoter) 
      internal 
    returns (bool success) 
    {
        approvedVoters[_oldVoter] = false;
        for (uint i = 0; i < voterArray.length - 1; i++) {
            if (voterArray[i] == _oldVoter) {
                voterArray[i] = voterArray[voterArray.length - 1];
                break;
            }
        }

        delete voterArray[voterArray.length-1];
        voterArray.length -= 1;
        updateRequiredVotes();
        return true;
    }
    
    /**
     * @dev Used to clear all votes after every successful vote 
    **/
    function clearBallots() internal {
        for (uint i = 0; i < voterArray.length; i++) {
            delete voterBallots[voterArray[i]];
        }
    }
    
/** *************************** Modifiers ***************************** **/
    
    /**
     * @dev Ensures only approved voters may use these functions 
    **/
    modifier onlyVoter()
    {
        require(approvedVoters[msg.sender]);
        _;
    }
    
    /**
     * @dev Make sure people aren't voting for an empty address (same reasoning as below)
     * @param _newAddress Address we're checking validity o
    **/
    modifier validAddress(address _newAddress)
    {
        require(_newAddress != address(0));
        _;
    }
    
    /**
     * @dev Ensure uint doesn't equal 0 (if it did someone entering 0 could almost always clear the vote)
     * @param _newUint The uint we're checking the value of
    **/
    modifier validUint(uint256 _newUint)
    {
        require(_newUint != 0);
        _;
    }

    modifier isTokenSet()
    {
        require(tokenSet);
        _;
    }
}
