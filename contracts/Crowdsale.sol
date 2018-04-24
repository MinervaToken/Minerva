pragma solidity ^0.4.17;
import "./SafeMath.sol";
import "./MinervaToken.sol";


/**
 * @title Crowdsale 
 * @dev Crowdsale is a base contract for managing a token crowdsale.
 * Crowdsales have a start and end timestamps, where investors can make
 * token purchases and the crowdsale will assign them tokens based
 * on a token per ETH rate. Funds collected are forwarded to a wallet 
 * as they arrive.
 * 
 * We're using a method to combat volatility risks by ensuring all 
 * contributions and the cap are measured in USD, not Eth. We do this
 * by frequently updating the USD:Eth conversion using a script.
**/

// contract MinervaToken { function mint(address _to, uint256 _value) public returns (bool); }
contract Crowdsale {
  using SafeMath for uint256;
  
  MinervaToken public token;                                // Token being sold
  address public owner;                                     // Owner of the contract can mint, end, and update conversion
  address public teamContract;                              // Address of the consensus contract to send team tokens to
  address public distributor;                               // Wallet used to distribute bounty tokens

  uint256 public startTime;                                 // Start accepting crowdsale donations
  uint256 public endTime;                                   // Stop accepting crowdsale donations

  uint256 public cap;                                       // Crowdsale cap in USD cents
  address public wallet;                                    // Address where funds are collected
  uint256 public weiRaised;                                 // Amount raised in wei
  uint256 public tokensRaised;                              // Amount raised in tokens
  uint256 public usdCentsPerEther;                          // Current USD:Ether conversion rate
  uint256 public perOwlPrice;                               // Amount of USD per Owl Token
  uint256 public usdRaised;                                 // Amount of USD raised
  
  bool public crowdsalePaused;                              // Owner can manually pause
  bool public teamTokensMinted;                             // Allows team tokens to be minted (once!) after crowdsale
  mapping (address => uint256) public approvedParties;      // KYC Approved Parties
  mapping (address => uint256) public presaleParticipants;  // Presale KYC approved Parties

  mapping (uint256 => uint256) public discountRates;        // Discount Rates
  

  /**
   * event for token purchase logging
   * @param purchaser who paid for the tokens
   * @param beneficiary who got the tokens
   * @param value weis paid for purchase
   * @param amount amount of tokens purchased
  **/ 
  event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
  event PresalePurchase(address indexed purchaser, uint256 indexed amount);

  /**
   * @dev Constructor with variables needed for Crowdsale
   * @param _startTime Time at which the public crowdsale begins
   * @param _endTime Time at which the public crowdsale getCurrentDiscount
   * @param _cap Max amount of USD to be raised from the crowdsale
   * @param _distributor Distributor that is allowed to control misc. initial tokens (bounty)
   * @param _wallet Multisig wallet that ether funds will be released to
  **/
  function Crowdsale(uint256 _startTime, uint256 _endTime, uint256 _cap, address _distributor, address _wallet, address _teamContract, uint256 _perOwlPrice) public {
    require(_startTime >= block.timestamp);
    require(_endTime >= _startTime);
    require(_wallet != 0x0);
    require(_teamContract != 0x0);
    require(_distributor != 0x0);
    require(_cap > 0);
    require(_perOwlPrice > 0);

    owner = msg.sender;
    startTime = _startTime;
    endTime = _endTime;
    cap = _cap;
    distributor = _distributor;
    wallet = _wallet;
    teamContract = _teamContract;
    crowdsalePaused = false;
    perOwlPrice = _perOwlPrice;
  }

  /**
   * @dev fallback function can be used to buy tokens
  **/
  function () 
    isApproved(msg.sender)
    public 
    payable 
  {
    buyTokens(msg.sender);
  }

  /**
   * @dev Low level token purchase function
   * @param beneficiary Wallet to give the tokens to
  **/
  function buyTokens(address beneficiary) 
    isApproved(msg.sender)
    public
    payable 
  returns (bool success) 
  {
    require(beneficiary != 0x0);
    require(approvedParties[beneficiary] > 0);
    require(validPurchase());

    uint256 weiAmount = getWeiAmount();
    uint256 tokens = weiToTokens(weiAmount);
    tokensRaised = tokensRaised.add(tokens);

    require(token.mint(beneficiary, tokens));
    TokenPurchase(msg.sender, beneficiary, weiAmount, tokens);

    forwardFunds(weiAmount);
    return true;
  }
  
  /**
   * @dev Has the crowdsale ended? Primarily for internal used
   * @return True if crowdsale has ended, false if it is ongoing
  **/
  function hasEnded() 
    public 
    constant 
  returns (bool) 
  {
    bool capReached = usdRaised >= cap;
    bool afterEndTime = block.timestamp > endTime;
    return afterEndTime || capReached;
  }
  
/** ***************************** onlyOwner ******************************* **/

  /**
   * @dev Owner updates frequently (using a script) to ensure accurate USD raising
   * @param _centsPerEth How many US cents one Ether is worth
  **/
  function updateConversion(uint256 _centsPerEth)
    external
    onlyOwner
  returns (bool success)
  {
    usdCentsPerEther = _centsPerEth;
    return true;
  }

  /**
   * @dev Allow an approved party to participate in the crowdsale
   * @param _party Ether address of approved Party
  **/
  function addApprovedParty(address _party) 
    external
    onlyOwner
  returns(bool success)
  {
    require(_party != 0x0);
    // only allow wallets to be approved parties
    require(!isContract(_party));
    approvedParties[_party] = 1;

    return true;
  }

  /**
   * @dev Block an Approved party from participating
   * @param _party Ether address of Approved Party
  **/
  function blockApprovedParty(address _party) 
    external
    onlyOwner
  returns(bool success)
  {
    require(_party != 0x0);
    approvedParties[_party] = 0;

    return true;
  }

  /**
   * @dev Update time frame of crowdsale start/finish
   * @param _startTime Beginning of crowdsale
   * @param _endTime End of crowdsale
  **/
  function updateTimeframe(uint256 _startTime, uint256 _endTime)
    external
    onlyOwner
  returns (bool success)
  {
    // ensure timeframe can only be changed prior to starting
    require(block.timestamp < _startTime);
    // ensure new timestamps are appropriate
    require(_startTime >= block.timestamp);
    require(_endTime >= _startTime);

    startTime = _startTime;
    endTime = _endTime;
    return true;
  }

  /**
   * @dev Used for the owner to distribute presale tokens
   * @param _to Address to receive minted presale tokens
   * @param _tokens Amount of tokens to mint to the recipient
  **/
  function ownerMint(address _to, uint256 _tokens)
    external
    isApproved(_to)
    onlyOwner
    mintable
  returns (bool success)
  {
    require(token.mint(_to, _tokens));
    tokensRaised = tokensRaised.add(_tokens);
    PresalePurchase(_to, _tokens);
    return true;
  }

  /**
   * @dev Owner can pause or resume
   * @param _crowdsalePaused Whether or not you want to pause or unpause
  **/
  function manualPause(bool _crowdsalePaused)
    external
    onlyOwner
  returns (bool success)
  {
    // make sure crowsdale is finished running
    require(block.timestamp >= startTime && block.timestamp <= endTime);
  
    crowdsalePaused = _crowdsalePaused;
    return true;
  }

    /**
   * @dev Owner can destroy contract after crowdsale has ended
  **/
  function manualDestroy()
    external
    onlyOwner
  returns (bool success)
  {
    // make sure crowsdale is finished running
    require(block.timestamp > endTime);
    selfdestruct(owner);
    return true;
  }
  
  /**
   * @dev Set the Minerva token address
   * @param _token Address of the Minerva ERC20 contract
  **/
  function setToken(address _token)
    external
    onlyOwner
  returns (bool success)
  {
    // must run before crowdsale starts
    require(block.timestamp < startTime);
    // make sure address is a contract
    require(isContract(_token));

    token = MinervaToken(_token);
    return true;
  }
  
  /**
   * @dev Set the price per Owl Token
   * @param _price Price in USD cents Per Token
  **/
  function setOwlPrice(uint256 _price)
    external
    onlyOwner
  {
    // must run before crowdsale starts
    require(block.timestamp < startTime);
    // make sure address is a contract
    require(_price > 0);

    perOwlPrice = _price;
  }

 /**
   * @dev Set the different discount rates by ether amounts
   * @param _rate Rate for ether cap
   * @param _etherCap Amount of ether for each cap
  **/
  function setDiscountRate(uint256 _rate, uint256 _etherCap) 
    external
    onlyOwner
  {
    require(block.timestamp < startTime);
    require(_rate > 0);
    require(_etherCap > 0);

    discountRates[_rate] = _etherCap.mul(1 ether);

  }

  /**
   * @dev Used when crowdsale ends to disburse team tokens to a holding contract
   * @dev and to disburse bounty tokens to the distributor wallet
  **/
  function disburseTeamTokens()
    external
    onlyOwner
  {
    require(hasEnded());
    require(!teamTokensMinted);
    
    uint256 tokenPool               = (tokensRaised.div(40)).mul(100); // 100% - 60% = 40% remaining for distribution
    
    uint256 teamAndAdvisorTokens    = (tokenPool.mul(10)).div(100);
    uint256 managementTokens        = (tokenPool.mul(10)).div(100);
    uint256 strategicAdvisorTokens  = (tokenPool.mul(7)).div(100);
    uint256 longTermCostsTokens     = (tokenPool.mul(5)).div(100);
    uint256 partnershipTokens       = (tokenPool.mul(5)).div(100);
    uint256 bountyTokens            = (tokenPool.mul(3)).div(100);

    require(token.mint(teamContract, teamAndAdvisorTokens));
    require(token.mint(teamContract, managementTokens));
    require(token.mint(teamContract, strategicAdvisorTokens));
    require(token.mint(teamContract, longTermCostsTokens));
    require(token.mint(teamContract, partnershipTokens));
    require(token.mint(distributor, bountyTokens));

    // // The team's 27% of all tokens is equivalent to 45% of tokens raised in crowdsale
    // uint256 illiquidAmount = tokensRaised * 45 / 100;
    // token.mint(teamContract, illiquidAmount);
    
    // // Bounty programs 13% of all tokens is 21.66666% of tokens raised in crowdsale
    // uint256 liquidAmount = tokensRaised * 21666 / 100000;
    // token.mint(distributor, liquidAmount);
    teamTokensMinted = true;
  }

/** ***************************** Internal ********************************* **/

  /**
   * @dev Send ether to the fund collection wallet
   * @dev Used internally with every purchase
   * @param _funds Amount of wei to forward to wallet
  **/
  function forwardFunds(uint256 _funds) internal {
    wallet.transfer(_funds);
  }
    
  /**
   * @dev Will just be msg.value unless the person donating hits the cap, then it'll be less
   * @dev This is not working when cap is overflowed by contribution...need to figure that out. 
   * @return _amount The amount of wei we can accept as donation
  **/
  function getWeiAmount()
    internal
  returns (uint256 _amount)
  {
    //uint256 usdRaised = weiToUsdCents(weiRaised);
    uint256 usdContribution = weiToUsdCents(msg.value);
    uint256 newRaised = usdRaised.add(usdContribution);         // Total raised after this contribution
    if (newRaised <= cap) {
      return msg.value;                                         // Most all txs will end here
    }
    
    uint256 difference = newRaised.sub(cap);                    // Find the amount past cap donated
    uint256 refund = difference.mul(1 ether).div(usdCentsPerEther);// Get amount past cap in wei
    msg.sender.transfer(refund);                                // Refund amount past cap
    
    return msg.value.sub(refund);                               // Continue with buy tokens without refunded amount
  }
  
  /**
   * @dev Returns a uint in the smallest unit of our token
   * @param _weiAmount Wei amount of ether that we are calculating token price for
   * @return _tokens How many tokens the input amount of wei is worth
  **/
  function weiToTokens(uint256 _weiAmount) 
    internal
  returns (uint256 _tokens)
  {
    uint256 discountPercent = getCurrentDiscount();                        // returns percent discount (ex: 40)
    uint256 tokenPrice = (100 - discountPercent).mul(perOwlPrice).div(100);   // tokenPrice in cents (ex: 36)
    uint256 oneCentOfWei = usdCentsPerEther.div(1 ether);                     // How many wei $0.01 is worth
    uint256 weiPerToken = tokenPrice.mul(oneCentOfWei);                    // How many wei in a token

    uint256 overflow = discountOverflow(_weiAmount);                       // Check to see if total ether sent will over flow the current discount
    uint256 tokens = 0; 

    // if overflow == 0, we are still within the same discount range
    // calculate the token data normally
    if (overflow == 0) {

      tokens = (_weiAmount.div(weiPerToken)).mul(1 ether);                    // (*1 ether) because tokens is in "token wei" 

      // update wei raised state
      weiRaised = weiRaised.add(_weiAmount);



    // if overflow > 0, we have oversold the current discount range
    // first, calculate the last of the current discount
    // them, re-adjust the remaining ether to the next discount level
    } else {
      tokens = (overflow.div(weiPerToken)).mul(1 ether);
      // update wei raised state of overflow only first
      weiRaised = weiRaised.add(overflow);

      // calculate wei difference after overflow
      uint256 weiDiff = _weiAmount.sub(overflow);

      // recalculate discount
      discountPercent = getCurrentDiscount();
      tokenPrice = (100 - discountPercent).mul(perOwlPrice).div(100);   // tokenPrice in cents (ex: 36)
      weiPerToken = tokenPrice.mul(oneCentOfWei);                    // How many wei in a token
      tokens = tokens.add((weiDiff.div(weiPerToken)).mul(1 ether));

      // update state with the remaining wei
      weiRaised = weiRaised.add(weiDiff);

    }

    // update usd raised state
    usdRaised = usdRaised.add(_weiAmount.div(oneCentOfWei));

    return tokens;
  }
  
  /**
   * @dev Calculates any overflow for discount rates
   * @param _amount The amount of wei sent with the transaction
   * @return _overflow Amount of overflow in wei
  **/
  function discountOverflow(uint256 _amount)
    internal
    view
  returns (uint256 _overflow) 
  {
    uint256 currentDiscount = getCurrentDiscount();
    if (currentDiscount == 0) { 
      return 0; 
    }

    uint256 discountLeft = discountRates[currentDiscount].sub(weiRaised);
    if (discountLeft < _amount) {
      return discountLeft;
    }

    return 0;
  }


  /**
   * @dev Get current rate of OWLs per USD cent (changes based on USD raised)
   * @dev These specific discounts are subject to changes
   * @return _discount The current discounted price of tokens (if any)
  **/
  function getCurrentDiscount()
    internal
    view
  returns (uint256 _discount)
  {
    if (weiRaised < discountRates[40]) {
      return 40;
    } else if (weiRaised < discountRates[30]) {
      return 30;
    } else if (weiRaised < discountRates[20]) {
      return 20;
    } else {
      return 0;
    }
  }


  /**
   * @dev Calculates how much USD the weiAmount is worth
   * @param _weiAmount The amount of wei we need to determine USD value for
   * @return _usdCents US cents that the wei amount is worth
  **/
  function weiToUsdCents(uint256 _weiAmount)
    internal
    view
  returns (uint256 _usdCents)
  {
    _usdCents = _weiAmount.mul(usdCentsPerEther).div(1 ether);
    return _usdCents;
  }

  /**
   * @dev Valid purchase used for each attempted contribution (ensures we're under cap, etc.)
   * @return true if the transaction can buy tokens
  **/
  function validPurchase() 
    internal 
    constant 
  returns (bool) 
  {
    bool withinPeriod = block.timestamp >= startTime && block.timestamp <= endTime;
    bool nonZeroPurchase = msg.value != 0;
    
    //uint256 usdRaised = weiToUsdCents(weiRaised);
    bool withinCap = usdRaised < cap;
    return withinPeriod && nonZeroPurchase && !crowdsalePaused && withinCap;
  }


  //assemble the given address bytecode. If bytecode exists then the _addr is a contract.
  function isContract(address _addr) 
    internal
    view
  returns (bool) 
  {
    uint length;
    assembly {
        //retrieve the size of the code on target address, this needs assembly
        length := extcodesize(_addr)
    }
    return (length>0);
  }
  
/** *************************** Modifiers ******************************* **/

  /**
   * @dev Used to ensure mint cannot be called after crowdsale
  **/
  modifier mintable()
  {
    require(block.timestamp <= endTime);
    require(!crowdsalePaused);
    _;
  }

  /**
   * @dev Used to ensure only approved parties can participate in the crowdsale
  **/
  modifier isApproved(address _party) {
    require (approvedParties[_party] > 0);
    _;
  }
  
  /** 
   * @dev Only owner is for both presale minting and updating USD:Eth conversion
  **/
  modifier onlyOwner()
  {
    require(msg.sender == owner);
    _;
  }
}
