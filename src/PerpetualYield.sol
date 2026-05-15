// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

interface IERC20 {
    /// @dev Emitted when `value` tokens are moved from one account (`from`) to another (`to`).
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @dev Emitted when the allowance of a `spender` for an `owner` is set, where `value`
    /// is the new allowance.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Returns the amount of tokens in existence.
    function totalSupply() external view returns (uint256);

    /// @notice Returns the amount of tokens owned by `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Moves `amount` tokens from the caller's account to `to`.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Returns the remaining number of tokens that `spender` is allowed
    /// to spend on behalf of `owner`
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @dev Be aware of front-running risks: https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Moves `amount` tokens from `from` to `to` using the allowance mechanism.
    /// `amount` is then deducted from the caller's allowance.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Returns the name of the token.
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token.
    function symbol() external view returns (string memory);

    /// @notice Returns the decimals places of the token.
    function decimals() external view returns (uint8);
}


interface IERC3156FlashBorrower {
    /**
     * @dev Receive a flash loan.
     * @param initiator The initiator of the loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param fee The additional amount of tokens to repay.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     * @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
     */
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32);
}


interface IERC3156FlashLender {
    /**
     * @dev The amount of currency available to be lent.
     * @param token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view returns (uint256);

    /**
     * @dev The fee to be charged for a given loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount) external view returns (uint256);

    /**
     * @dev Initiate a flash loan.
     * @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}



contract PerpetualYield is IERC20, IERC3156FlashLender {
    error ReentrantCall();
    error NotOwner();
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();
    error UnsupportedToken();
    error CallbackFailed();
    error RepayNotApproved();
    error FeeTooHigh();

    string public constant name = "Perpetual Yield";
    string public constant symbol = "PY";
    uint8 public constant decimals = 18;

    uint256 private constant RATE = 10 ** 27;
    uint256 public constant GRACE_PERIOD = 7 days;
    uint256 public constant DECAY_PER_SECOND_RATE = 999999970800000000000000000;
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    address public owner;
    uint public flashFeeBps = 100 ;
    uint8 private status = 1;   

    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowance;
    mapping(address =>  uint256) public lastActivity;

    modifier nonReentrant() {
        if(status == 2) revert ReentrantCall();
        status = 2;
        _;
        status = 1;
    }

    modifier onlyOwner() {
        if(msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

   function rpow(uint256 x, uint256 n, uint256 scalar) internal pure returns (uint256 z) {
        z = n & 1 != 0 ? x : scalar; 
        for (n >>= 1; n != 0; n >>= 1) { 
            x = (x * x) / scalar; 
            if (n & 1 != 0) {
                z = (z * x) / scalar; 
            }
        }
    }
    
function balanceOf(address account) public view override returns (uint256) {
        uint256 principal = _balances[account];
        if (principal == 0) return 0; 

        uint256 timeElapsed = block.timestamp - lastActivity[account];
        if (timeElapsed <= GRACE_PERIOD) return principal; 
        
        unchecked {
            uint256 decayTime = timeElapsed - GRACE_PERIOD;
            uint256 decayFactor = rpow(DECAY_PER_SECOND_RATE, decayTime, RATE); 
            return (principal * decayFactor) / RATE; 
        }
    }

function _updateActivityAndDecay(address account) internal {
        if (account == address(0)) return;
        
        uint256 principal = _balances[account]; 
        if (principal > 0) {
            uint256 timeElapsed = block.timestamp - lastActivity[account];
            if (timeElapsed > GRACE_PERIOD) {
                unchecked {
                    uint256 decayTime = timeElapsed - GRACE_PERIOD;
                    uint256 decayFactor = rpow(DECAY_PER_SECOND_RATE, decayTime, RATE);
                    uint256 decayedBalance = (principal * decayFactor) / RATE;
                    
                    uint256 decayAmount = principal - decayedBalance;
                    if (decayAmount > 0) {
                        _balances[account] = decayedBalance;
                        _totalSupply -= decayAmount;
                    }
                }
            }
        }
        
        lastActivity[account] = block.timestamp;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner_, address spender) public view override returns (uint256) {
        return _allowance[owner_][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = _allowance[from][msg.sender];
        if (currentAllowance < amount) revert InsufficientAllowance();
        
        unchecked {
            _approve(from, msg.sender, currentAllowance - amount);
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();

        _updateActivityAndDecay(from);
        _updateActivityAndDecay(to);

        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance();
        
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function _approve(address owner_, address spender, uint256 amount) internal {
        if (owner_ == address(0) || spender == address(0)) revert ZeroAddress();
        _allowance[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        
        _updateActivityAndDecay(account); 

        unchecked {
            _totalSupply += amount;
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();

        _updateActivityAndDecay(account); 

        uint256 accountBalance = _balances[account];
        if (accountBalance < amount) revert InsufficientBalance();
        
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }



    function maxFlashLoan(address token) public view override returns (uint256) {
        if (token != address(this)) return 0;
        unchecked {
            return type(uint256).max - (type(uint256).max * uint256(flashFeeBps) / 10000);
        }
    }

    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        if (token != address(this)) revert UnsupportedToken();
        return (amount * uint256(flashFeeBps)) / 10000;
    }

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) public override nonReentrant returns (bool) {
        if (token != address(this)) revert UnsupportedToken();
        
        uint256 fee = (amount * uint256(flashFeeBps)) / 10000;
        address receiverAddr = address(receiver);
        address thisAddr = address(this);

        _mint(receiverAddr, amount);
        
        if (receiver.onFlashLoan(msg.sender, token, amount, fee, data) != CALLBACK_SUCCESS) {
            revert CallbackFailed();
        }

        uint256 repayment;
        unchecked { repayment = amount + fee; } 
        
        uint256 currentAllowance = _allowance[receiverAddr][thisAddr];
        if (currentAllowance < repayment) revert RepayNotApproved();
        
        unchecked {
            _approve(receiverAddr, thisAddr, currentAllowance - repayment);
        }

        _burn(receiverAddr, repayment);

        return true;
    }

    function externalMint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function externalBurn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function setFlashFeeBps(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > 1000) revert FeeTooHigh();
        flashFeeBps = newFeeBps;
    }
}