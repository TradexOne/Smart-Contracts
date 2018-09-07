pragma solidity ^0.4.9;

contract SafeMath {
  function safeMul(uint a, uint b) internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeSub(uint a, uint b) internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) internal returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
  }

  function assert(bool assertion) internal {
    if (!assertion) throw;
  }
}

contract Token {
  /// @return total amount of tokens
  function totalSupply() constant returns (uint256 supply) {}

  /// @param _owner The address from which the balance will be retrieved
  /// @return The balance
  function balanceOf(address _owner) constant returns (uint256 balance) {}

  /// @notice send `_value` token to `_to` from `msg.sender`
  /// @param _to The address of the recipient
  /// @param _value The amount of token to be transferred
  /// @return Whether the transfer was successful or not
  function transfer(address _to, uint256 _value) returns (bool success) {}

  /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
  /// @param _from The address of the sender
  /// @param _to The address of the recipient
  /// @param _value The amount of token to be transferred
  /// @return Whether the transfer was successful or not
  function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {}

  /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
  /// @param _spender The address of the account able to transfer the tokens
  /// @param _value The amount of wei to be approved for transfer
  /// @return Whether the approval was successful or not
  function approve(address _spender, uint256 _value) returns (bool success) {}

  /// @param _owner The address of the account owning tokens
  /// @param _spender The address of the account able to transfer the tokens
  /// @return Amount of remaining tokens allowed to spent
  function allowance(address _owner, address _spender) constant returns (uint256 remaining) {}

  event Transfer(address indexed _from, address indexed _to, uint256 _value);
  event Approval(address indexed _owner, address indexed _spender, uint256 _value);

  uint public decimals;
  string public name;
}

contract StandardToken is Token {

  function transfer(address _to, uint256 _value) returns (bool success) {
    //Default assumes totalSupply can't be over max (2^256 - 1).
    //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
    //Replace the if with this one instead.
    if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
    //if (balances[msg.sender] >= _value && _value > 0) {
      balances[msg.sender] -= _value;
      balances[_to] += _value;
      Transfer(msg.sender, _to, _value);
      return true;
    } else { return false; }
  }

  function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
    //same as above. Replace this line with the following if you want to protect against wrapping uints.
    if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
    //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
      balances[_to] += _value;
      balances[_from] -= _value;
      allowed[_from][msg.sender] -= _value;
      Transfer(_from, _to, _value);
      return true;
    } else { return false; }
  }

  function balanceOf(address _owner) constant returns (uint256 balance) {
    return balances[_owner];
  }

  function approve(address _spender, uint256 _value) returns (bool success) {
    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
    return true;
  }

  function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
    return allowed[_owner][_spender];
  }

  mapping(address => uint256) balances;

  mapping (address => mapping (address => uint256)) allowed;

  uint256 public totalSupply;
}

// More comments at https://github.com/forkdelta/smart_contract/blob/master/contracts/ForkDelta.sol
contract ReserveToken is StandardToken, SafeMath {
  address public minter;
  function ReserveToken() {
    minter = msg.sender;
  }
  function create(address account, uint amount) {
    if (msg.sender != minter) throw;
    balances[account] = safeAdd(balances[account], amount);
    totalSupply = safeAdd(totalSupply, amount);
  }
  function destroy(address account, uint amount) {
    if (msg.sender != minter) throw;
    if (balances[account] < amount) throw;
    balances[account] = safeSub(balances[account], amount);
    totalSupply = safeSub(totalSupply, amount);
  }
}

contract EtherDelta is SafeMath {
  address public admin; //the admin address
  address public feeAccount; //the account that will receive fees
  mapping (address => uint) public feeMake; //percentage times (1 ether) (sell fee)
  mapping (address => uint) public feeTake; //percentage times (1 ether) (buy fee)
  uint public feeRebate; //percentage times (1 ether)
  mapping (address => uint) public feeDeposit; //percentage times (1 ether)
  mapping (address => uint) public feeWithdraw; //percentage times (1 ether)
  
  mapping (address => mapping (address => uint)) public tokens; //mapping of token addresses to mapping of account balances (token=0 means Ether)
  mapping (address => mapping (bytes32 => bool)) public orders; //mapping of user accounts to mapping of order hashes to booleans (true = submitted by user, equivalent to offchain signature)
  mapping (address => mapping (bytes32 => uint)) public orderFills; //mapping of user accounts to mapping of order hashes to uints (amount of order that has been filled)
  mapping (address => bool) public activeTokens;
  mapping (address => uint) public tokensMinAmountBuy;
  mapping (address => uint) public tokensMinAmountSell;

  event Order(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user);
  event Cancel(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user);
  event Trade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, address get, address give);
  event Deposit(address token, address user, uint amount, uint balance);
  event Withdraw(address token, address user, uint amount, uint balance);

  function EtherDelta(address admin_, address feeAccount_, uint feeRebate_) {
    admin = admin_;
    feeAccount = feeAccount_;
    feeRebate = feeRebate_;
  }

  function() {
    throw;
  }
  
  
  function activateToken(address token) {
    if (msg.sender != admin) throw;
    activeTokens[token] = true;
  }
  function deactivateToken(address token) {
    if (msg.sender != admin) throw;
    activeTokens[token] = false;
  }
  function isTokenActive(address token) constant returns(bool) {
    if (token == 0)
      return true; // eth is always active
    return activeTokens[token];
  }
  
  function setTokenMinAmountBuy(address token, uint amount) {
    if (msg.sender != admin) throw;
    tokensMinAmountBuy[token] = amount;
  }
  function setTokenMinAmountSell(address token, uint amount) {
    if (msg.sender != admin) throw;
    tokensMinAmountSell[token] = amount;
  }
  
  function setTokenFeeMake(address token, uint feeMake_) {
    if (msg.sender != admin) throw;
    feeMake[token] = feeMake_;
  }
  function setTokenFeeTake(address token, uint feeTake_) {
    if (msg.sender != admin) throw;
    //if (feeTake_ < feeRebate) throw;
    feeTake[token] = feeTake_;
  }
  function setTokenFeeDeposit(address token, uint feeDeposit_) {
    if (msg.sender != admin) throw;
    feeDeposit[token] = feeDeposit_;
  }
  function setTokenFeeWithdraw(address token, uint feeWithdraw_) {
    if (msg.sender != admin) throw;
    feeWithdraw[token] = feeWithdraw_;
  }
  
  
  function changeAdmin(address admin_) {
    if (msg.sender != admin) throw;
    admin = admin_;
  }

  function changeFeeAccount(address feeAccount_) {
    if (msg.sender != admin) throw;
    feeAccount = feeAccount_;
  }

  function changeFeeRebate(uint feeRebate_) {
    if (msg.sender != admin) throw;
    //if (feeRebate_ < feeRebate || feeRebate_ > feeTake) throw;
    feeRebate = feeRebate_;
  }

  function deposit() payable {
    uint feeDepositXfer = safeMul(msg.value, feeDeposit[0]) / (1 ether);
    uint depositAmount = safeSub(msg.value, feeDepositXfer);
    tokens[0][msg.sender] = safeAdd(tokens[0][msg.sender], depositAmount);
    tokens[0][feeAccount] = safeAdd(tokens[0][feeAccount], feeDepositXfer);
    Deposit(0, msg.sender, msg.value, tokens[0][msg.sender]);
  }

  function withdraw(uint amount) {
    if (tokens[0][msg.sender] < amount) throw;
    uint feeWithdrawXfer = safeMul(amount, feeWithdraw[0]) / (1 ether);
    uint withdrawAmount = safeSub(amount, feeWithdrawXfer);
    tokens[0][msg.sender] = safeSub(tokens[0][msg.sender], amount);
    tokens[0][feeAccount] = safeAdd(tokens[0][feeAccount], feeWithdrawXfer);
    if (!msg.sender.call.value(withdrawAmount)()) throw;
    Withdraw(0, msg.sender, amount, tokens[0][msg.sender]);
  }

  function depositToken(address token, uint amount) {
    //remember to call Token(address).approve(this, amount) or this contract will not be able to do the transfer on your behalf.
    if (token==0) throw;
    if (!isTokenActive(token)) throw;
    if (!Token(token).transferFrom(msg.sender, this, amount)) throw;
    uint feeDepositXfer = safeMul(amount, feeDeposit[token]) / (1 ether);
    uint depositAmount = safeSub(amount, feeDepositXfer);
    tokens[token][msg.sender] = safeAdd(tokens[token][msg.sender], depositAmount);
    tokens[token][feeAccount] = safeAdd(tokens[token][feeAccount], feeDepositXfer);
    Deposit(token, msg.sender, amount, tokens[token][msg.sender]);
  }

  function withdrawToken(address token, uint amount) {
    if (token==0) throw;
    if (tokens[token][msg.sender] < amount) throw;
    uint feeWithdrawXfer = safeMul(amount, feeWithdraw[token]) / (1 ether);
    uint withdrawAmount = safeSub(amount, feeWithdrawXfer);
    tokens[token][msg.sender] = safeSub(tokens[token][msg.sender], amount);
    tokens[token][feeAccount] = safeAdd(tokens[token][feeAccount], feeWithdrawXfer);
    if (!Token(token).transfer(msg.sender, withdrawAmount)) throw;
    Withdraw(token, msg.sender, amount, tokens[token][msg.sender]);
  }

  function balanceOf(address token, address user) constant returns (uint) {
    return tokens[token][user];
  }

  function order(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce) returns (bytes32) {
    if (!isTokenActive(tokenGet) || !isTokenActive(tokenGive)) throw;
    if (amountGet < tokensMinAmountBuy[tokenGet]) throw;
    if (amountGive < tokensMinAmountSell[tokenGive]) throw;
    bytes32 hash = sha256(this, tokenGet, amountGet, tokenGive, amountGive, expires, nonce);
    orders[msg.sender][hash] = true;
    Order(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, msg.sender);
  }

  function trade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint amount) {
    if (!isTokenActive(tokenGet) || !isTokenActive(tokenGive)) throw;
    //amount is in amountGet terms
    bytes32 hash = sha256(this, tokenGet, amountGet, tokenGive, amountGive, expires, nonce);
    if (!(orders[user][hash] && block.number <= expires && safeAdd(orderFills[user][hash], amount) <= amountGet)) throw;
    tradeBalances(tokenGet, amountGet, tokenGive, amountGive, user, amount);
    orderFills[user][hash] = safeAdd(orderFills[user][hash], amount);
    Trade(tokenGet, amount, tokenGive, amountGive * amount / amountGet, user, msg.sender);
  }

  function tradeBalances(address tokenGet, uint amountGet, address tokenGive, uint amountGive, address user, uint amount) private {
    uint feeMakeXfer = safeMul(amount, feeMake[tokenGet]) / (1 ether);
    uint feeTakeXfer = safeMul(amount, feeTake[tokenGet]) / (1 ether);
    uint feeRebateXfer = 0;
    tokens[tokenGet][msg.sender] = safeSub(tokens[tokenGet][msg.sender], safeAdd(amount, feeTakeXfer));
    tokens[tokenGet][user] = safeAdd(tokens[tokenGet][user], safeSub(safeAdd(amount, feeRebateXfer), feeMakeXfer));
    tokens[tokenGet][feeAccount] = safeAdd(tokens[tokenGet][feeAccount], safeSub(safeAdd(feeMakeXfer, feeTakeXfer), feeRebateXfer));
    tokens[tokenGive][user] = safeSub(tokens[tokenGive][user], safeMul(amountGive, amount) / amountGet);
    tokens[tokenGive][msg.sender] = safeAdd(tokens[tokenGive][msg.sender], safeMul(amountGive, amount) / amountGet);
  }

  function testTrade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint amount, address sender) constant returns(bool) {
    if (!isTokenActive(tokenGet) || !isTokenActive(tokenGive)) return false;
    if (!(
      tokens[tokenGet][sender] >= amount &&
      availableVolume(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, user) >= amount
    )) return false;
    return true;
  }

  function availableVolume(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user) constant returns(uint) {
    bytes32 hash = sha256(this, tokenGet, amountGet, tokenGive, amountGive, expires, nonce);
    if (!(orders[user][hash] && block.number <= expires)) return 0;
    uint available1 = safeSub(amountGet, orderFills[user][hash]);
    uint available2 = safeMul(tokens[tokenGive][user], amountGet) / amountGive;
    if (available1<available2) return available1;
    return available2;
  }

  function amountFilled(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user) constant returns(uint) {
    bytes32 hash = sha256(this, tokenGet, amountGet, tokenGive, amountGive, expires, nonce);
    return orderFills[user][hash];
  }

  function cancelOrder(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce) {
    bytes32 hash = sha256(this, tokenGet, amountGet, tokenGive, amountGive, expires, nonce);
    if (!orders[msg.sender][hash]) throw;
    orderFills[msg.sender][hash] = amountGet;
    Cancel(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, msg.sender);
  }
}