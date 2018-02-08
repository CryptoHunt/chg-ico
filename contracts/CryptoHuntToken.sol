pragma solidity ^0.4.11;

import "../node_modules/zeppelin-solidity/contracts/token/ERC20/StandardToken.sol";

/**
 * @title CryptoHunt Token
 */
contract CryptoHuntToken is StandardToken {

    string public constant name = "CryptoHunt Token";
    string public constant symbol = "CH";
    uint8 public constant decimals = 12;
    uint public totalSupply;
    uint public INITIAL_SUPPLY = 500000000000000000000;

    function CryptoHuntToken() public {
        totalSupply = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;
    }
}
