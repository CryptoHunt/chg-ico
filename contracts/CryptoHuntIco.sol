pragma solidity ^0.4.18;

import './TokenTimedChestMulti.sol';
import '../node_modules/zeppelin-solidity/contracts/math/SafeMath.sol';
import '../node_modules/zeppelin-solidity/contracts/ownership/Ownable.sol';
import '../node_modules/zeppelin-solidity/contracts/crowdsale/RefundVault.sol';

contract CryptoHuntIco is Ownable {
    using SafeMath for uint256;

    ERC20 public token;

    // address where funds are collected
    address public wallet;

    // how many token units a buyer gets per wei
    uint256 public rate;

    // amount of raised money in wei
    uint256 public weiRaised;

    uint256 public softcap;
    uint256 public hardcap;

    // refund vault used to hold funds while crowdsale is running
    RefundVault public vault;

    // start and end timestamps where investments are allowed (both inclusive)
    uint256 public startTime;
    uint256 public endTime;
    uint256 public whitelistEndTime;
    // duration in days
    uint256 public duration;
    uint256 public wlDuration;

    // A collection of tokens owed to people to be timechested on finalization
    address[] public tokenBuyersArray;
    // A sum of tokenbuyers' tokens
    uint256 public tokenBuyersAmount;
    // A mapping of buyers and amounts
    mapping(address => uint) public tokenBuyersMapping;

    TokenTimedChestMulti public chest;

    // List of addresses who can purchase in pre-sale
    mapping(address => bool) public wl;
    address[] public wls;

    bool public isFinalized = false;

    event Finalized();

    /**
     * event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
    */
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    /**
    * @param addr whitelisted user
    * @param status if whitelisted, will almost always be true unless subsequently blacklisted
    */
    event Whitelisted(address addr, bool status);

    function CryptoHuntIco(uint256 _durationSeconds, uint256 _wlDurationSeconds, address _wallet, address _token) public {
        require(_durationSeconds > 0);
        require(_wlDurationSeconds > 0);
        require(_wallet != address(0));
        require(_token != address(0));
        duration = _durationSeconds;
        wlDuration = _wlDurationSeconds;

        wallet = _wallet;
        vault = new RefundVault(wallet);

        token = ERC20(_token);
        owner = msg.sender;
    }

    /**
    * Setting the rate starts the ICO and sets the end time
    */
    function setRateAndStart(uint256 _rate, uint256 _softcap, uint256 _hardcap) external onlyOwner {

        require(_rate > 0 && rate < 1);
        require(_softcap > 0);
        require(_hardcap > 0);
        require(_softcap < _hardcap);
        rate = _rate;

        softcap = _softcap;
        hardcap = _hardcap;

        startTime = now;
        whitelistEndTime = startTime.add(wlDuration * 1 seconds);
        endTime = whitelistEndTime.add(duration * 1 seconds);
    }

    // fallback function can be used to buy tokens
    function() external payable {
        buyTokens(msg.sender);
    }

    function whitelistAddresses(address[] users) onlyOwner external {
        for (uint i = 0; i < users.length; i++) {
            wl[users[i]] = true;
            wls.push(users[i]);
            Whitelisted(users[i], true);
        }
    }

    function unwhitelistAddresses(address[] users) onlyOwner external {
        for (uint i = 0; i < users.length; i++) {
            wl[users[i]] = false;
            Whitelisted(users[i], false);
        }
    }

    // low level token purchase function
    function buyTokens(address beneficiary) public payable {
        require(beneficiary != address(0));
        require(validPurchase());

        uint256 weiAmount = msg.value;

        // calculate token amount to be created
        uint256 tokenAmount = getTokenAmount(weiAmount);

        // update state
        weiRaised = weiRaised.add(weiAmount);

        tokenBuyersMapping[beneficiary] = tokenBuyersMapping[beneficiary].add(tokenAmount);
        tokenBuyersArray.push(beneficiary);
        tokenBuyersAmount.add(tokenAmount);

        TokenPurchase(msg.sender, beneficiary, weiAmount, tokenAmount);

        forwardFunds();
    }

    // @return true if crowdsale event has ended
    function hasEnded() public view returns (bool) {
        return (weiRaised > hardcap) || now > endTime;
    }

    function getTokenAmount(uint256 weiAmount) internal view returns (uint256) {
        return weiAmount.mul(rate).div(1e6);
    }

    // send ether to the fund collection wallet
    function forwardFunds() internal {
        vault.deposit.value(msg.value)(msg.sender);
    }

    // @return true if the transaction can buy tokens
    function validPurchase() internal view returns (bool) {
        // Sent more than 0 eth
        bool nonZeroPurchase = msg.value != 0;

        // Still under hardcap
        bool withinCap = weiRaised.add(msg.value) <= hardcap;

        // if in regular period, ok
        bool withinPeriod = now >= whitelistEndTime && now <= endTime;

        // if whitelisted, and in wl period, and value is <= 5, ok
        bool whitelisted = now >= startTime && now <= whitelistEndTime && msg.value <= 5 && wl[msg.sender];

        return withinCap && (withinPeriod || whitelisted) && nonZeroPurchase;
    }

    /**
     * @dev Must be called after crowdsale ends, to do some extra finalization
     * work. Calls the contract's finalization function.
     */
    function finalize() onlyOwner public {
        require(!isFinalized);
        require(hasEnded());

        finalization();
        Finalized();

        isFinalized = true;

    }

    // if crowdsale is unsuccessful, investors can claim refunds here
    function claimRefund() public {
        require(isFinalized);
        require(!goalReached());

        vault.refund(msg.sender);
    }

    function goalReached() public view returns (bool) {
        return weiRaised >= softcap;
    }

    function forceRefundState() external onlyOwner {
        vault.enableRefunds();
        token.transfer(owner, token.balanceOf(address(this)));
        Finalized();
        isFinalized = true;
    }

    /**
     * @dev Can be overridden to add finalization logic. The overriding function
     * should call super.finalization() to ensure the chain of finalization is
     * executed entirely.
     */
    function finalization() internal {

        if (goalReached()) {
            vault.close();
            // create timed chests for all participants
            createTimedChest();
            token.transfer(chest, tokenBuyersAmount);

            for (uint i = 0; i < tokenBuyersArray.length; i++) {
                uint256 bought = tokenBuyersMapping[tokenBuyersArray[i]];
                uint256 fraction = bought.div(uint256(8));
                for (uint8 j = 1; j <= 8; j++) {
                    // addBeneficiary(uint _releaseDelay, uint _amount, address _token, address _beneficiary)
                    chest.addBeneficiary(604800 * j, fraction, address(token), tokenBuyersArray[i]);
                }
            }

        } else {
            vault.enableRefunds();
        }
        // Transfer leftover tokens to owner
        token.transfer(owner, token.balanceOf(address(this)));
    }

    /**
    * Instantiates a new timelocked token chest and stores it in ICO's state
    */
    function createTimedChest() internal {
        chest = new TokenTimedChestMulti();
    }

    /**
    * Initiates a withdraw-all-due command on the chest, sending due tokens
    * Only callable if the crowdsale was successful and it's finished
    */
    function withdrawAllDue() public onlyOwner {
        require(isFinalized && goalReached());
        chest.withdrawAllDue();
    }
}