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

    // function asmApprove(address _erc20Addr, address _spender, uint256 _value) internal returns (bool result) {

    //     // Must be a contract addr first!
    //     isContract(_erc20Addr);

    //     // call return false when something wrong
    //     require(_erc20Addr.call(bytes4(keccak256("approve(address,uint256)")), _spender, _value), "asmApprove error");

    //     // handle returndata
    //     return handleReturnData();
    // }
}

contract TheForceLending is SafeMath, ErrorReporter {
  using ERC20AsmFn for EIP20Interface;

  enum OrderState {
    ORDER_STATUS_PENDING,
    ORDER_STATUS_ACCEPTED
  }

  struct Order_t {
    bytes32 partner_id;
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
  address public offcialFeeAccount; //the account that will receive fees

   mapping (bytes32 => address) public partnerAccounts;// bytes32-> address, eg: platformA->0xa{40}, platfromB->0xb{40}
   mapping (bytes32 => mapping (address => mapping (address => uint))) public partnerTokens;// platform->tokenContract->address->balance
   mapping (bytes32 => mapping (address => mapping (bytes32 => Order_t))) public partnerOrderBook;// platform->address->hash->order_t

  event Borrow(bytes32 partnerId,
                address tokenGet,
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
  event Lend(bytes32 partnerId, address borrower, bytes32 txId, address token, uint amount, address give);//txId为借款单txId
  event CancelOrder(bytes32 partnerId, address borrower, bytes32 txId, address by);//取消借款单，只能被borrower或者合约取消
  event Callmargin(bytes32 partnerId, address borrower, bytes32 txId, address token, uint amount, address by);
  event Repay(bytes32 partnerId, address borrower, bytes32 txId, address token, uint amount, address by);
  event Closepstion(bytes32 partnerId, address borrower, bytes32 txId, address token, address by);
  event Forcerepay(bytes32 partnerId, address borrower, bytes32 txId, address token, address by);

  constructor(address admin_, address offcialFeeAccount_) public {
    admin = admin_;
    offcialFeeAccount = offcialFeeAccount_;
  }

  function() public payable {
    revert("fallback can't be payable");
 }

  modifier onlyAdmin() {
    require(msg.sender == admin, "only admin can do this!");
    _;
  }

  function changeAdmin(address admin_) public onlyAdmin {
    admin = admin_;
  }

  function changeFeeAccount(address offcialFeeAccount_) public onlyAdmin {
    offcialFeeAccount = offcialFeeAccount_;
  }

  //增
  function addPartner(bytes32 partnerId, address partner) public onlyAdmin {
    require(partnerAccounts[partnerId] == address(0), "already exists!");
    partnerAccounts[partnerId] = partner;
  }

  //删
  function delPartner(bytes32 partnerId) public onlyAdmin {
    delete partnerAccounts[partnerId];
  }

  //改
  function modPartner(bytes32 partnerId, address partner) public onlyAdmin {
    require(partnerAccounts[partnerId] != address(0), "not exists!");
    partnerAccounts[partnerId] = partner;
  }

  //查
  function getPartner(bytes32 partnerId) public view returns (address) {
    return partnerAccounts[partnerId];
  }

  function depositToken(bytes32 partnerId, address token, uint amount) internal returns (uint){
    //remember to call Token(address).approve(this, amount) or this contract will not be able to do the transfer on your behalf.
    require(partnerAccounts[partnerId] != address(0), "parnerId must add first");

    if (token == 0) revert("invalid token address!");

    if (EIP20Interface(token).allowance(msg.sender, address(this)) < amount) {
        return uint(Error.TOKEN_INSUFFICIENT_ALLOWANCE);
    }
    
    if (EIP20Interface(token).balanceOf(msg.sender) < amount) {
        return uint(Error.TOKEN_INSUFFICIENT_ALLOWANCE);
    }

    if (!EIP20Interface(token).asmTransferFrom(msg.sender, address(this), amount)) {
        return uint(Error.TRANSFER_FROM_ERROR);
    }
    partnerTokens[partnerId][token][msg.sender] = safeAdd(partnerTokens[partnerId][token][msg.sender], amount);
  
    return 0;
  }

  function withdrawToken(bytes32 partnerId, address token, uint amount) internal returns (uint) {
    require(partnerAccounts[partnerId] != address(0), "parnerId must add first");

    if (token == 0) revert("invalid token address");
    if (partnerTokens[partnerId][token][msg.sender] < amount) {
        return uint(Error.WITHDRAW_TOKEN_AMOUNT_ERROR);
    }
    partnerTokens[partnerId][token][msg.sender] = safeSub(partnerTokens[partnerId][token][msg.sender], amount);
    if (!EIP20Interface(token).asmTransfer(msg.sender, amount)) {
        return uint(Error.WITHDRAW_TOKEN_TRANSER_ERROR);
    }
    return 0;
  }
  
  function sendToken(bytes32 partnerId, address token, address to, uint amount) internal returns (uint) {
    require(partnerAccounts[partnerId] != address(0), "parnerId must add first");

    if (token==0 || to == 0 || amount == 0) revert("invalid token address or amount");
    if (partnerTokens[partnerId][token][to] < amount) {
        return uint(Error.SEND_TOKEN_AMOUNT_ERROR);
    }
    partnerTokens[partnerId][token][to] = safeSub(partnerTokens[partnerId][token][to], amount);
    if (!EIP20Interface(token).asmTransfer(to, amount)) {
        return uint(Error.SEND_TOKEN_TRANSER_ERROR);
    }
    return 0;
  }

  function balanceOf(bytes32 partnerId, address token, address user) public view returns (uint) {
    return partnerTokens[partnerId][token][user];
  }

  function borrow(bytes32 partnerId,//平台标记
                  address tokenGet, //借出币种地址
                  uint amountGet, //借出币种数量
                  address tokenGive, //抵押币种地址
                  uint amountGive,//抵押币种数量
                  uint nonce,
                  uint lendingCycle,
                  uint pledgeRate,
                  uint interestRate,
                  uint feeRate) public returns (uint){
    require(partnerAccounts[partnerId] != address(0), "parnerId must add first");
    bytes32 txid = hash(partnerId, tokenGet, amountGet, tokenGive, amountGive, nonce, lendingCycle, pledgeRate, interestRate, feeRate);
    require(partnerOrderBook[partnerId][msg.sender][txid].borrower == address(0), "order already exists");

    uint status = 0;

    partnerOrderBook[partnerId][msg.sender][txid] = Order_t({
      partner_id: partnerId,
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
    status = depositToken(partnerId, tokenGive, amountGive);
    if (status != 0) {
      return fail("borrow", Error.DEPOSIT_TOKEN);
    }

    emit Borrow(partnerId, tokenGet, amountGet, tokenGive, amountGive, nonce, lendingCycle, pledgeRate, interestRate, feeRate, msg.sender, txid, status);
    return 0;
  }

  //A借款，B出借，A到账数量为申请数量，无砍头息，B出借的数量包括A的申请数量+手续费(项目方手续费+平台合作方手续费，手续费可能为0)
  function lend(bytes32 partnerId, address borrower, bytes32 hash, address token, uint lenderAmount, uint offcialFeeAmount, uint partnerFeeAmount) public returns (uint) {
    require(partnerAccounts[partnerId] != address(0), "parnerId must add first");

    require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");//order not found
    require(partnerOrderBook[partnerId][borrower][hash].borrower != msg.sender, "cannot lend to self");//cannot lend to self
    require(partnerOrderBook[partnerId][borrower][hash].token_get == token, "attempt to use an invalid type of token");//attempt to use an invalid type of token
    require(partnerOrderBook[partnerId][borrower][hash].amount_get == lenderAmount - offcialFeeAmount - partnerFeeAmount, "amount_get != amount - offcialFeeAmount - partnerFeeAmount");//单个出借金额不足，后续可以考虑多个出借人，现在只考虑一个出借人
    require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_PENDING, "state != OrderState.ORDER_STATUS_PENDING");

    if (EIP20Interface(token).allowance(msg.sender, address(this)) < lenderAmount) {
        return fail("lend", Error.TOKEN_INSUFFICIENT_ALLOWANCE);
    }
    if (EIP20Interface(token).balanceOf(msg.sender) < lenderAmount) {
        return fail("lend", Error.LENDER_INSUFFICIENT_BORROWER_BALANCE);
    }
    if (!EIP20Interface(token).asmTransferFrom(msg.sender, partnerOrderBook[partnerId][borrower][hash].borrower, partnerOrderBook[partnerId][borrower][hash].amount_get)) {
        return fail("lend", Error.LENDER_TRANSFER_FROM_BORROW_ERROR);
    }

    if (offcialFeeAmount != 0) {
      if (EIP20Interface(token).allowance(msg.sender, address(this)) < offcialFeeAmount) {
          return fail("lend", Error.LENDER_INSUFFICIENT_ADMIN_ALLOWANCE);
      }
      if (EIP20Interface(token).balanceOf(msg.sender) < offcialFeeAmount) {
          return fail("lend", Error.LENDER_INSUFFICIENT_ADMIN_BALANCE);
      }
      if (!EIP20Interface(token).asmTransferFrom(msg.sender, offcialFeeAccount, offcialFeeAmount)) {
          return fail("lend", Error.LENDER_TRANSFER_FROM_ADMIN_ERROR);
      }
    }

    if (partnerFeeAmount != 0) {
      if (EIP20Interface(token).allowance(msg.sender, address(this)) < partnerFeeAmount) {
          return fail("lend", Error.LENDER_INSUFFICIENT_ADMIN_ALLOWANCE);
      }
      if (EIP20Interface(token).balanceOf(msg.sender) < partnerFeeAmount) {
          return fail("lend", Error.LENDER_INSUFFICIENT_ADMIN_BALANCE);
      }
      if (!EIP20Interface(token).asmTransferFrom(msg.sender, partnerAccounts[partnerId], partnerFeeAmount)) {
          return fail("lend", Error.LENDER_TRANSFER_FROM_ADMIN_ERROR);
      }
    }
    

    partnerOrderBook[partnerId][borrower][hash].deadline = now + partnerOrderBook[partnerId][borrower][hash].lending_cycle * (1 minutes);
    partnerOrderBook[partnerId][borrower][hash].lender = msg.sender;
    partnerOrderBook[partnerId][borrower][hash].state = OrderState.ORDER_STATUS_ACCEPTED;


    emit Lend(partnerId, borrower, hash, token, lenderAmount, msg.sender);
    return 0;
  }

  function cancelOrder(bytes32 partnerId, address borrower, bytes32 hash) public {
    require(partnerAccounts[partnerId] != address(0), "parnerId must add first");
    
    require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");//order not found
    require(partnerOrderBook[partnerId][borrower][hash].borrower == msg.sender || msg.sender == admin,
      "only borrower or admin can do this operation");//only borrower or contract can do this operation
    require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_PENDING, "state != OrderState.ORDER_STATUS_PENDING");
    uint status = 0;
    
    status = sendToken(partnerId, partnerOrderBook[partnerId][borrower][hash].token_pledge, partnerOrderBook[partnerId][borrower][hash].borrower, partnerOrderBook[partnerId][borrower][hash].amount_pledge);


    if (status == 0) {
        delete partnerOrderBook[partnerId][borrower][hash];
	emit CancelOrder(partnerId, borrower, hash, msg.sender);
    } else {
    	fail("cancelOrder", Error.CANCEL_ORDER);
    }
  }

  function callmargin(bytes32 partnerId, address borrower, bytes32 hash, address token, uint amount) public returns (uint){
    require(partnerAccounts[partnerId] != address(0), "parnerId must add first");

    require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");
    require(amount > 0, "amount must >0");
    require(token != address(0), "invalid token");
    require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != OrderState.ORDER_STATUS_ACCEPTED");
    require(partnerOrderBook[partnerId][borrower][hash].token_pledge == token, "invalid pledge token");

    if (EIP20Interface(token).allowance(msg.sender, address(this)) < amount) {
        return fail("callmargin", Error.CALL_MARGIN_ALLOWANCE_ERROR);
    }
    
    partnerOrderBook[partnerId][borrower][hash].amount_pledge += amount;
    partnerTokens[partnerId][token][borrower] = safeAdd(partnerTokens[partnerId][token][borrower], amount);
    
    if (EIP20Interface(token).balanceOf(msg.sender) < amount) {
        return fail("callmargin", Error.CALL_MARGIN_BALANCE_ERROR);
    }

    if (!EIP20Interface(token).asmTransferFrom(msg.sender, address(this), amount)) {
        return fail("callmargin", Error.CALL_MARGIN_TRANSFER_ERROR);
    }

    emit Callmargin(partnerId, borrower, hash, token, amount, msg.sender);
    return 0;
  }

  //A还款，需要支付本金+利息给出借方，给项目方和平台合作方手续费
  function repay(bytes32 partnerId, address borrower, bytes32 hash, address token, uint repayAmount, uint lenderAmount, uint offcialFeeAmount, uint partnerFeeAmount) public returns (uint){
    require(partnerAccounts[partnerId] != address(0), "parnerId must add first");

    require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");
    require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != OrderState.ORDER_STATUS_ACCEPTED");
    require(token != address(0), "invalid token");
    require(token == partnerOrderBook[partnerId][borrower][hash].token_get, "invalid repay token");
    //还款数量，为借款数量加上利息加上项目方手续费+合作方手续费
    require(repayAmount == lenderAmount + offcialFeeAmount + partnerFeeAmount, "invalid repay amount");
    require(lenderAmount >= partnerOrderBook[partnerId][borrower][hash].amount_get, "invalid lender amount");
    require(msg.sender == partnerOrderBook[partnerId][borrower][hash].borrower, "invalid repayer, must be borrower");
    uint status = 0;

    //允许contract花费借款者的所借的token+利息token
    if (EIP20Interface(token).allowance(msg.sender, address(this)) < repayAmount) {
        return fail("repay", Error.REPAY_ALLOWANCE_ERROR);
    }
    
    if (EIP20Interface(token).balanceOf(msg.sender) < repayAmount) {
        return fail("repay", Error.REPAY_BALANCE_ERROR);
    }

    if (!EIP20Interface(token).asmTransferFrom(msg.sender, partnerOrderBook[partnerId][borrower][hash].lender, lenderAmount)) {
        return fail("repay", Error.REPAY_TX_ERROR);
    }

    if (!EIP20Interface(token).asmTransferFrom(msg.sender, offcialFeeAccount, offcialFeeAmount)) {
        return fail("repay", Error.REPAY_TX_ERROR);
    }

    if (!EIP20Interface(token).asmTransferFrom(msg.sender, partnerAccounts[partnerId], partnerFeeAmount)) {
        return fail("repay", Error.REPAY_TX_ERROR);
    }
    
    status = withdrawToken(partnerId, partnerOrderBook[partnerId][borrower][hash].token_pledge, partnerOrderBook[partnerId][borrower][hash].amount_pledge);

    if (status == 0) {
        delete partnerOrderBook[partnerId][borrower][hash];
    	emit Repay(partnerId, borrower, hash, token, repayAmount, msg.sender);
    } else {
    	return fail("repay", Error.REPAY_ERROR);
    }

    return status;
  }

  //逾期强制归还，由合约管理者调用，非borrower，非lender调用，borrower需要支付抵押资产给出借人（本金+利息），平台合作方（手续费）和项目方（手续费），如果还有剩余，剩余部分归还给A
  function forcerepay(bytes32 partnerId, address borrower, bytes32 hash, address token, uint lenderAmount, uint offcialFeeAmount, uint partnerFeeAmount) public returns (uint){
    require(partnerAccounts[partnerId] != address(0), "parnerId must add first");
    
    require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");
    require(token != address(0), "invalid forcerepay token address");
    require(token == partnerOrderBook[partnerId][borrower][hash].token_pledge, "invalid forcerepay token");
    require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != OrderState.ORDER_STATUS_ACCEPTED");
    require(msg.sender == admin, "forcerepay must be admin");
    require(now > partnerOrderBook[partnerId][borrower][hash].deadline, "cannot forcerepay before deadline");

    //合约管理员发送抵押资产到出借人,数量由上层传入
    partnerTokens[partnerId][token][borrower] = safeSub(partnerTokens[partnerId][token][borrower], lenderAmount);
    if (!EIP20Interface(token).asmTransfer(partnerOrderBook[partnerId][borrower][hash].lender, lenderAmount)) {
        return fail("forcerepay", Error.FORCE_REPAY_TX_ERROR);
    }

    //合约管理员发送抵押资产到平台合作方,数量由上层传入
    partnerTokens[partnerId][token][borrower] = safeSub(partnerTokens[partnerId][token][borrower], partnerFeeAmount);
    if (!EIP20Interface(token).asmTransfer(partnerAccounts[partnerId], partnerFeeAmount)) {
        return fail("forcerepay", Error.FORCE_REPAY_TX_ERROR);
    }

    //合约管理员发送抵押资产到项目方,数量由上层传入
    partnerTokens[partnerId][token][borrower] = safeSub(partnerTokens[partnerId][token][borrower], offcialFeeAmount);
    if (!EIP20Interface(token).asmTransfer(offcialFeeAccount, offcialFeeAmount)) {
        return fail("forcerepay", Error.FORCE_REPAY_TX_ERROR);
    }

    //合约管理员发送剩余抵押资产到借款方,数量由上层传入
    if (partnerTokens[partnerId][token][borrower] > 0) {
      if (!EIP20Interface(token).asmTransfer(borrower, partnerTokens[partnerId][token][borrower])) {
          return fail("forcerepay", Error.FORCE_REPAY_TX_ERROR);
      } else {
        partnerTokens[partnerId][token][borrower] = 0;
      }
    }

    delete partnerOrderBook[partnerId][borrower][hash];

    emit Forcerepay(partnerId, borrower, hash, token, msg.sender);
    return 0;
  }

  //价格波动平仓，borrower需要支付抵押资产给出借人（本金+利息），项目方（手续费）和平台合作方（手续费），如果还有剩余，剩余部分归还给A
  function closepstion(bytes32 partnerId, address borrower, bytes32 hash, address token, uint lenderAmount, uint offcialFeeAmount, uint partnerFeeAmount) public returns (uint){
    require(partnerAccounts[partnerId] != address(0), "parnerId must add first");
    
    require(partnerOrderBook[partnerId][borrower][hash].borrower != address(0), "order not found");
    require(token != address(0), "invalid token");
    require(token == partnerOrderBook[partnerId][borrower][hash].token_pledge, "invalid token");
    require(partnerOrderBook[partnerId][borrower][hash].state == OrderState.ORDER_STATUS_ACCEPTED, "state != OrderState.ORDER_STATUS_ACCEPTED");
    require(msg.sender == admin, "closepstion must be admin");

    //未逾期
    if (partnerOrderBook[partnerId][borrower][hash].deadline > now) {
      if (msg.sender != admin) {
        //only admin of this contract can do this operation before deadline
        return fail("closepstion", Error.CLOSE_POSITION_MUST_ADMIN_BEFORE_DEADLINE);
      }
    } else {
      if (!(msg.sender == admin || msg.sender == partnerOrderBook[partnerId][borrower][hash].lender)) {
        //only lender or admin of this contract can do this operation
        return fail("closepstion", Error.CLOSE_POSITION_MUST_ADMIN_OR_LENDER_AFTER_DEADLINE);
      }
    }

    //合约管理员发送抵押资产到出借人,数量由上层传入
    partnerTokens[partnerId][token][borrower] = safeSub(partnerTokens[partnerId][token][borrower], lenderAmount);
    if (!EIP20Interface(token).asmTransfer(partnerOrderBook[partnerId][borrower][hash].lender, lenderAmount)) {
        return fail("closepstion", Error.CLOSE_POSITION_TX_ERROR);
    }

    //合约管理员发送抵押资产到平台合作方,数量由上层传入
    partnerTokens[partnerId][token][borrower] = safeSub(partnerTokens[partnerId][token][borrower], partnerFeeAmount);
    if (!EIP20Interface(token).asmTransfer(partnerAccounts[partnerId], partnerFeeAmount)) {
        return fail("closepstion", Error.CLOSE_POSITION_TX_ERROR);
    }

    //合约管理员发送抵押资产到项目方,数量由上层传入
    partnerTokens[partnerId][token][borrower] = safeSub(partnerTokens[partnerId][token][borrower], offcialFeeAmount);
    if (!EIP20Interface(token).asmTransfer(offcialFeeAccount, offcialFeeAmount)) {
        return fail("closepstion", Error.CLOSE_POSITION_TX_ERROR);
    }

    //合约管理员发送剩余抵押资产到借款方,数量由上层传入
    if (partnerTokens[partnerId][token][borrower] > 0) {
      if (!EIP20Interface(token).asmTransfer(borrower, partnerTokens[partnerId][token][borrower])) {
          return fail("closepstion", Error.CLOSE_POSITION_TX_ERROR);
      } else {
        partnerTokens[partnerId][token][borrower] = 0;
      }
    }

    delete partnerOrderBook[partnerId][borrower][hash];

    emit Closepstion(partnerId, borrower, hash, token, address(this));

    return 0;
  }

    //ADDITIONAL HELPERS ADDED FOR TESTING
    function hash(
        bytes32 partnerId,
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
        return sha256(abi.encodePacked(address(this), partnerId, tokenGet, amountGet, tokenGive, amountGive, nonce, lendingCycle, pledgeRate, interestRate, feeRate));
    }
}
