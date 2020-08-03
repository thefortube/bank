pragma solidity ^0.4.24;

contract SafeMath {
  function safeMul(uint a, uint b) pure internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeSub(uint a, uint b) pure internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) pure internal returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
  }

}

contract EIP20Interface {
    /* This is a slight change to the ERC20 base standard.
    function totalSupply() constant returns (uint256 supply);
    is replaced with:
    uint256 public totalSupply;
    This automatically creates a getter function for the totalSupply.
    This is moved to the base contract since public getter functions are not
    currently recognised as an implementation of the matching abstract
    function by the compiler.
    */
    /// total amount of tokens
    uint256 public totalSupply;

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) public view returns (uint256 balance);

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) public returns (bool success);

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);

    /// @notice `msg.sender` approves `_spender` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of tokens to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) public returns (bool success);

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) public view returns (uint256 remaining);

    // solhint-disable-next-line no-simple-event-func-name
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

contract ErrorReporter {

    /**
      * @dev `error` corresponds to enum Error; `info` corresponds to enum FailureInfo, and `detail` is an arbitrary
      * contract-specific code that enables us to report opaque error codes from upgradeable contracts.
      **/
    event Failure(string name, uint error);

    enum Error {
        NO_ERROR,
        INVALIDE_ADMIN,
        WITHDRAW_TOKEN_AMOUNT_ERROR,
        WITHDRAW_TOKEN_TRANSER_ERROR,
        TOKEN_INSUFFICIENT_ALLOWANCE,
        TOKEN_INSUFFICIENT_BALANCE,
        TRANSFER_FROM_ERROR,
        LENDER_INSUFFICIENT_BORROW_ALLOWANCE,
        LENDER_INSUFFICIENT_BORROWER_BALANCE,
        LENDER_TRANSFER_FROM_BORROW_ERROR,
        LENDER_INSUFFICIENT_ADMIN_ALLOWANCE,
        LENDER_INSUFFICIENT_ADMIN_BALANCE,
        LENDER_TRANSFER_FROM_ADMIN_ERROR,
        CALL_MARGIN_ALLOWANCE_ERROR,
        CALL_MARGIN_BALANCE_ERROR,
        CALL_MARGIN_TRANSFER_ERROR,
        REPAY_ALLOWANCE_ERROR,
        REPAY_BALANCE_ERROR,
        REPAY_TX_ERROR,
        FORCE_REPAY_ALLOWANCE_ERROR,
        FORCE_REPAY_BALANCE_ERROR,
        FORCE_REPAY_TX_ERROR,
        CLOSE_POSITION_ALLOWANCE_ERROR,
        CLOSE_POSITION_TX_ERROR,
        CLOSE_POSITION_MUST_ADMIN_BEFORE_DEADLINE,
        CLOSE_POSITION_MUST_ADMIN_OR_LENDER_AFTER_DEADLINE,
        LENDER_TEST_TRANSFER_ADMIN_ERROR,
        LENDER_TEST_TRANSFER_BORROWR_ERROR,
        LENDER_TEST_TRANSFERFROM_ADMIN_ERROR,
        LENDER_TEST_TRANSFERFROM_BORROWR_ERROR,
        SEND_TOKEN_AMOUNT_ERROR,
        SEND_TOKEN_TRANSER_ERROR,
        DEPOSIT_TOKEN,
        CANCEL_ORDER,
        REPAY_ERROR,
        FORCE_REPAY_ERROR
    }

    /**
      * @dev use this when reporting a known error from the money market or a non-upgradeable collaborator
      */
    function fail(string name, Error err) internal returns (uint) {
        emit Failure(name, uint(err));

        return uint(err);
    }
}

library ERC20AsmFn {

    function isContract(address addr) internal {
        assembly {
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
    }

    function handleReturnData() internal returns (bool result) {
        assembly {
            switch returndatasize()
            case 0 { // not a std erc20
                result := 1
            }
            case 32 { // std erc20
                returndatacopy(0, 0, 32)
                result := mload(0)
            }
            default { // anything else, should revert for safety
                revert(0, 0)
            }
        }
    }

    function asmTransfer(address _erc20Addr, address _to, uint256 _value) internal returns (bool result) {

        // Must be a contract addr first!
        isContract(_erc20Addr);

        // call return false when something wrong
        require(_erc20Addr.call(bytes4(keccak256("transfer(address,uint256)")), _to, _value), "asmTransfer error");

        // handle returndata
        return handleReturnData();
    }

    function asmTransferFrom(address _erc20Addr, address _from, address _to, uint256 _value) internal returns (bool result) {

        // Must be a contract addr first!
        isContract(_erc20Addr);

        // call return false when something wrong
        require(_erc20Addr.call(bytes4(keccak256("transferFrom(address,address,uint256)")), _from, _to, _value), "asmTransferFrom error");

        // handle returndata
        return handleReturnData();
    }

}

contract TheForceLending is SafeMath, ErrorReporter {
  using ERC20AsmFn for EIP20Interface;

  enum OrderState {
    ORDER_STATUS_PENDING,
    ORDER_STATUS_ACCEPTED
  }

  struct Order_t {
    bytes32 tx_id;
    uint deadline;
    OrderState state;

    address borrower;
    address lender;

    uint lending_cycle;

    address token_get;
    uint amount_get;

    address token_pledge;//tokenGive
    uint amount_pledge;//amountGive

    uint _nonce;

    uint pledge_rate;
    uint interest_rate;
    uint fee_rate;
  }

  address public admin; //the admin address
  address public feeAccount; //the account that will receive fees
  mapping (address => mapping (address => uint)) public tokens; //mapping of token addresses to mapping of account balances (token=0 means Ether)
  mapping (address => mapping(bytes32 => Order_t)) public orderBook;// address->hash->order_t

  event Borrow(address tokenGet,
                  uint amountGet,
                  address tokenGive,
                  uint amountGive,
                  uint nonce,
                  uint lendingCycle,
                  uint pledgeRate,
                  uint interestRate,
                  uint feeRate,
                  address user,
                  bytes32 hash,
                  uint status);
  event Lend(address borrower, bytes32 txId, address token, uint amount, address give);//txId为借款单txId
  event CancelOrder(address borrower, bytes32 txId, address by);//取消借款单，只能被borrower或者合约取消
  event Callmargin(address borrower, bytes32 txId, address token, uint amount, address by);
  event Repay(address borrower, bytes32 txId, address token, uint amount, address by);
  event Closepstion(address borrower, bytes32 txId, address token, address by);
  event Forcerepay(address borrower, bytes32 txId, address token, address by);


  constructor(address admin_, address feeAccount_) public {
    admin = admin_;
    feeAccount = feeAccount_;
  }

  function() public payable {
    revert("fallback can't be payable");
 }

  function changeAdmin(address admin_) public returns (uint){
    if (msg.sender != admin) {
        return fail("changeAdmin", Error.INVALIDE_ADMIN);
    }
    admin = admin_;

    return 0;
  }


  function changeFeeAccount(address feeAccount_) public returns (uint){
    if (msg.sender != admin) {
        return fail("changeFeeAccount", Error.INVALIDE_ADMIN);
    }
    feeAccount = feeAccount_;
    return 0;
  }

  
  function depositToken(address token, uint amount) internal returns (uint){
    //remember to call Token(address).approve(this, amount) or this contract will not be able to do the transfer on your behalf.
   if (token==0) revert("invalid token address!");

    if (EIP20Interface(token).allowance(msg.sender, address(this)) < amount) {
        return uint(Error.TOKEN_INSUFFICIENT_ALLOWANCE); 
    }
    
    if (EIP20Interface(token).balanceOf(msg.sender) < amount) {
        return uint(Error.TOKEN_INSUFFICIENT_ALLOWANCE);
    }


    if (!EIP20Interface(token).asmTransferFrom(msg.sender, address(this), amount)) {
        return uint(Error.TRANSFER_FROM_ERROR);
    }
    tokens[token][msg.sender] = safeAdd(tokens[token][msg.sender], amount);

    
    return 0;
  }

  function withdrawToken(address token, uint amount) internal returns (uint) {
    if (token==0) revert("invalid token address");
    if (tokens[token][msg.sender] < amount) {
        return uint(Error.WITHDRAW_TOKEN_AMOUNT_ERROR);
    }
    tokens[token][msg.sender] = safeSub(tokens[token][msg.sender], amount);
    if (!EIP20Interface(token).asmTransfer(msg.sender, amount)) {
        return uint(Error.WITHDRAW_TOKEN_TRANSER_ERROR);
    }
    return 0;
  }
  
  function sendToken(address token, address to, uint amount) internal returns (uint) {
    if (token==0 || to == 0 || amount == 0) revert("invalid token address or amount");
    if (tokens[token][to] < amount) {
        return uint(Error.SEND_TOKEN_AMOUNT_ERROR);
    }
    tokens[token][to] = safeSub(tokens[token][to], amount);
    if (!EIP20Interface(token).asmTransfer(to, amount)) {
        return uint(Error.SEND_TOKEN_TRANSER_ERROR);
    }
    return 0;
  }

  function balanceOf(address token, address user) public view returns (uint) {
    return tokens[token][user];
  }

  function borrow(address tokenGet, //借出币种地址
                  uint amountGet, //借出币种数量
                  address tokenGive, //抵押币种地址
                  uint amountGive,//抵押币种数量
                  uint nonce,
                  uint lendingCycle,
                  uint pledgeRate,
                  uint interestRate,
                  uint feeRate) public returns (uint){
    bytes32 txid = hash(tokenGet, amountGet, tokenGive, amountGive, nonce, lendingCycle, pledgeRate, interestRate, feeRate);
    uint status = 0;

    orderBook[msg.sender][txid] = Order_t({
      tx_id: txid,
      deadline: 0,
      state: OrderState.ORDER_STATUS_PENDING,
      borrower: msg.sender,
      lender: address(0),
      lending_cycle: lendingCycle,
      token_get: tokenGet,
      amount_get: amountGet,
      token_pledge: tokenGive,
      amount_pledge: amountGive,
      _nonce: nonce,
      pledge_rate: pledgeRate,
      interest_rate: interestRate,
      fee_rate: feeRate
    });

    status = depositToken(tokenGive, amountGive);
    if (status != 0) {
      return fail("borrow", Error.DEPOSIT_TOKEN);
    }

    emit Borrow(tokenGet, amountGet, tokenGive, amountGive, nonce, lendingCycle, pledgeRate, interestRate, feeRate, msg.sender, txid, status);
    return 0;
  }

  function lend(address borrower, bytes32 hash, address token, uint amount, uint feeAmount) public returns (uint) {
    require(orderBook[borrower][hash].borrower != address(0), "order not found");//order not found
    require(orderBook[borrower][hash].borrower != msg.sender, "cannot lend to self");//cannot lend to self
    require(orderBook[borrower][hash].token_get == token, "attempt to use an invalid type of token");//attempt to use an invalid type of token
    require(orderBook[borrower][hash].amount_get == amount - feeAmount, "amount_get != amount - feeAmount");//单个出借金额不足，后续可以考虑多个出借人，现在只考虑一个出借人
    require(orderBook[borrower][hash].state == OrderState.ORDER_STATUS_PENDING, "state != OrderState.ORDER_STATUS_PENDING");

    if (EIP20Interface(token).allowance(msg.sender, address(this)) < amount) {
        return fail("lend", Error.TOKEN_INSUFFICIENT_ALLOWANCE);
    }
    if (EIP20Interface(token).balanceOf(msg.sender) < amount) {
        return fail("lend", Error.LENDER_INSUFFICIENT_BORROWER_BALANCE);
    }
    if (!EIP20Interface(token).asmTransferFrom(msg.sender, orderBook[borrower][hash].borrower, orderBook[borrower][hash].amount_get)) {
        return fail("lend", Error.LENDER_TRANSFER_FROM_BORROW_ERROR);
    }

    if (EIP20Interface(token).allowance(msg.sender, address(this)) < feeAmount) {
        return fail("lend", Error.LENDER_INSUFFICIENT_ADMIN_ALLOWANCE);
    }
    if (EIP20Interface(token).balanceOf(msg.sender) < feeAmount) {
        return fail("lend", Error.LENDER_INSUFFICIENT_ADMIN_BALANCE);
    }
    if (!EIP20Interface(token).asmTransferFrom(msg.sender, feeAccount, feeAmount)) {
        return fail("lend", Error.LENDER_TRANSFER_FROM_ADMIN_ERROR);
    }
    
    orderBook[borrower][hash].deadline = now + orderBook[borrower][hash].lending_cycle * (1 days);
    orderBook[borrower][hash].lender = msg.sender;
    orderBook[borrower][hash].state = OrderState.ORDER_STATUS_ACCEPTED;       

    emit Lend(borrower, hash, token, amount, msg.sender);
    return 0;
  }

  function cancelOrder(address borrower, bytes32 hash) public {
    require(orderBook[borrower][hash].borrower != address(0), "order not found");//order not found
    require(orderBook[borrower][hash].borrower == msg.sender || msg.sender == admin,
      "only borrower or admin can do this operation");//only borrower or contract can do this operation
    require(orderBook[borrower][hash].state == OrderState.ORDER_STATUS_PENDING, "state != OrderState.ORDER_STATUS_PENDING");
    uint status = 0;
    
    status = sendToken(orderBook[borrower][hash].token_pledge, orderBook[borrower][hash].borrower, orderBook[borrower][hash].amount_pledge);  


    if (status == 0) {
        delete orderBook[borrower][hash];
        emit CancelOrder(borrower, hash, msg.sender);
    } else {
      fail("cancelOrder", Error.CANCEL_ORDER);
    }
  }

  function callmargin(address borrower, bytes32 hash, address token, uint amount) public returns (uint){
    require(orderBook[borrower][hash].borrower != address(0), "order not found");
    require(amount > 0, "amount must >0");
    require(token != address(0), "invalid token");
    require(orderBook[borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != OrderState.ORDER_STATUS_ACCEPTED");
    require(orderBook[borrower][hash].token_pledge == token, "invalid pledge token");

    if (EIP20Interface(token).allowance(msg.sender, address(this)) < amount) {
        return fail("callmargin", Error.CALL_MARGIN_ALLOWANCE_ERROR);
    }
    
    orderBook[borrower][hash].amount_pledge += amount;
    tokens[token][borrower] = safeAdd(tokens[token][borrower], amount);     
    
    if (EIP20Interface(token).balanceOf(msg.sender) < amount) {
        return fail("callmargin", Error.CALL_MARGIN_BALANCE_ERROR);
    }

    if (!EIP20Interface(token).asmTransferFrom(msg.sender, address(this), amount)) {
        return fail("callmargin", Error.CALL_MARGIN_TRANSFER_ERROR);
    }

    emit Callmargin(borrower, hash, token, amount, msg.sender);
    return 0;
  }

  function repay(address borrower, bytes32 hash, address token, uint amount, uint feeAmount) public returns (uint){
    require(orderBook[borrower][hash].borrower != address(0), "order not found");
    require(orderBook[borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != OrderState.ORDER_STATUS_ACCEPTED");
    require(token != address(0), "invalid token");
    require(token == orderBook[borrower][hash].token_get, "invalid repay token");
    require(amount > orderBook[borrower][hash].amount_get, "invalid reapy amount");//还款数量，为借款数量加上利息
    require(msg.sender == orderBook[borrower][hash].borrower, "invalid repayer, must be borrower");
    uint status = 0;

    //允许contract花费借款者的所借的token+利息token
    if (EIP20Interface(token).allowance(msg.sender, address(this)) < amount) {
        return fail("repay", (Error.REPAY_ALLOWANCE_ERROR));
    }
    
    if (EIP20Interface(token).balanceOf(msg.sender) < amount) {
        return fail("repay", (Error.REPAY_BALANCE_ERROR));
    }

    if (!EIP20Interface(token).asmTransferFrom(msg.sender, orderBook[borrower][hash].lender, amount)) {
        return fail("repay", (Error.REPAY_TX_ERROR));
    }
    
    if (!EIP20Interface(token).asmTransferFrom(msg.sender, feeAccount, feeAmount)) {
        return fail("repay", (Error.REPAY_TX_ERROR));
    }
    
    status = withdrawToken(orderBook[borrower][hash].token_pledge, orderBook[borrower][hash].amount_pledge);

    if (status == 0) {
        delete orderBook[borrower][hash];        
        emit Repay(borrower, hash, token, amount, msg.sender);
    } else {
      return fail("repay", Error.REPAY_ERROR);
    }

    return status;
  }

  //逾期强制归还，由合约管理者调用，非borrower，非lender调用
  function forcerepay(address borrower, bytes32 hash, address token) public returns (uint){
    require(orderBook[borrower][hash].borrower != address(0), "order not found");
    require(token != address(0), "invalid forcerepay token address");
    require(token == orderBook[borrower][hash].token_pledge, "invalid forcerepay token");
    require(orderBook[borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != OrderState.ORDER_STATUS_ACCEPTED");
    require(msg.sender == admin, "forcerepay must be admin");
    require(now > orderBook[borrower][hash].deadline, "cannot forcerepay before deadline");
    uint status = 0;

    tokens[token][borrower] = safeSub(tokens[token][borrower], orderBook[borrower][hash].amount_pledge);
    if (!EIP20Interface(token).asmTransfer(orderBook[borrower][hash].lender, orderBook[borrower][hash].amount_pledge)) {
        status = uint(Error.FORCE_REPAY_TX_ERROR);
    }//合约管理员发送抵押资产到出借人

    if (status == 0) {
        delete orderBook[borrower][hash];
        emit Forcerepay(borrower, hash, token, msg.sender);
    } else {
      return fail("forcerepay", Error.FORCE_REPAY_ERROR);
    }

    return status;
  }

  //价格波动平仓
  function closepstion(address borrower, bytes32 hash, address token) public returns (uint){
    require(orderBook[borrower][hash].borrower != address(0), "order not found");
    require(token != address(0), "invalid token");
    require(token == orderBook[borrower][hash].token_pledge, "invalid token");
    require(orderBook[borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != OrderState.ORDER_STATUS_ACCEPTED");
    require(msg.sender == admin, "closepstion must be admin");

    //未逾期
    if (orderBook[borrower][hash].deadline > now) {
      if (msg.sender != admin) {
        //only admin of this contract can do this operation before deadline
        return fail("closepstion", Error.CLOSE_POSITION_MUST_ADMIN_BEFORE_DEADLINE);
      }
    } else {
      if (!(msg.sender == admin || msg.sender == orderBook[borrower][hash].lender)) {
        //only lender or admin of this contract can do this operation
        return fail("closepstion", Error.CLOSE_POSITION_MUST_ADMIN_OR_LENDER_AFTER_DEADLINE);
      }
    }
    tokens[token][borrower] = safeSub(tokens[token][borrower], orderBook[borrower][hash].amount_pledge);
    if (!EIP20Interface(token).asmTransfer(orderBook[borrower][hash].lender, orderBook[borrower][hash].amount_pledge)) {
      return fail("closepstion", Error.CLOSE_POSITION_TX_ERROR);
    }//合约管理员或者lender发送抵押资产到出借人
    delete orderBook[borrower][hash];          

    emit Closepstion(borrower, hash, token, address(this));

    return 0;
  }

    // ADDITIONAL HELPERS ADDED FOR TESTING
    function hash(
        address tokenGet,
        uint amountGet,
        address tokenGive,
        uint amountGive,
        uint nonce,
        uint lendingCycle,
        uint pledgeRate,
        uint interestRate,
        uint feeRate
    )
        public
        view
        returns (bytes32)
    {
        //return sha256(this, tokenGet, amountGet, tokenGive, amountGive, nonce, lendingCycle, pledgeRate, interestRate, feeRate);
        return sha256(abi.encodePacked(address(this), tokenGet, amountGet, tokenGive, amountGive, nonce, lendingCycle, pledgeRate, interestRate, feeRate));
    }
}
