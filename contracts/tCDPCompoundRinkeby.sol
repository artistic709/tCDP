pragma solidity ^0.5.12;


library SafeMath {

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) 
            return 0;
        uint256 c = a * b;
        require(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;
        return c;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);
        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}


contract ERC20 {
    using SafeMath for uint256;

    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowed;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal _totalSupply;

    /**
    * @dev Total number of tokens in existence
    */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
    * @dev Gets the balance of the specified address.
    * @param owner The address to query the balance of.
    * @return A uint256 representing the amount owned by the passed address.
    */
    function balanceOf(address owner) public view returns (uint256) {
        return _balances[owner];
    }

    /**
    * @dev Function to check the amount of tokens that an owner allowed to a spender.
    * @param owner address The address which owns the funds.
    * @param spender address The address which will spend the funds.
    * @return A uint256 specifying the amount of tokens still available for the spender.
    */
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowed[owner][spender];
    }

    /**
    * @dev Transfer token to a specified address
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    */
    function transfer(address to, uint256 value) public returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /**
    * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
    * Beware that changing an allowance with this method brings the risk that someone may use both the old
    * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
    * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
    * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    * @param spender The address which will spend the funds.
    * @param value The amount of tokens to be spent.
    */
    function approve(address spender, uint256 value) public returns (bool) {
        _allowed[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
    * @dev Transfer tokens from one address to another.
    * Note that while this function emits an Approval event, this is not required as per the specification,
    * and other compliant implementations may not emit the event.
    * @param from address The address which you want to send tokens from
    * @param to address The address which you want to transfer to
    * @param value uint256 the amount of tokens to be transferred
    */
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        _transfer(from, to, value);
        _allowed[msg.sender][to] = _allowed[msg.sender][to].sub(value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0));
        _balances[from] = _balances[from].sub(value);
        _balances[to] = _balances[to].add(value);
        emit Transfer(from, to, value);
    }

}

contract ERC20Mintable is ERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;

    function _mint(address to, uint256 amount) internal {
        _balances[to] = _balances[to].add(amount);
        _totalSupply = _totalSupply.add(amount);
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        _balances[from] = _balances[from].sub(amount);
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(from, address(0), amount);
    }
}


interface CErc20 {

    function borrow(uint256) external returns (uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);

    function repayBorrow(uint256) external returns (uint256);
}


interface CEth {
    function mint() external payable;

    function redeemUnderlying(uint redeemAmount) external returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);
    
    function supplyRatePerBlock() external view returns (uint256);
}


interface Comptroller {
    function markets(address) external returns (bool, uint256);

    function enterMarkets(address[] calldata)
        external
        returns (uint256[] memory);

    function getAccountLiquidity(address)
        external
        view
        returns (uint256, uint256, uint256);

    function oracle() external view returns(address);
}


interface PriceOracle {
    function getUnderlyingPrice(address) external view returns (uint256);
}

contract tCDP is ERC20Mintable {
    using SafeMath for *;

    uint256 constant dust = 1e6;

    Comptroller constant comptroller = Comptroller(0x2EAa9D77AE4D8f9cdD9FAAcd44016E746485bddb);
    //PriceOracle constant priceOracle = PriceOracle(0xDDc46a3B076aec7ab3Fc37420A8eDd2959764Ec4);

    CEth constant cEth = CEth(0xd6801a1DfFCd0a410336Ef88DeF4320D6DF1883e);
    CErc20 constant cDai = CErc20(0x6D7F0754FFeb405d23C51CE938289d4835bE3b14);
    ERC20 constant Dai = ERC20(0x5592EC0cfb4dbc12D3aB100b257153436a1f0FEa);

    constructor() public {
        symbol = "tCDP";
        name = "tokenized CDP";
        decimals = 18;
        Dai.approve(address(cDai), uint256(-1));
    }

    function initiate(uint256 amount) external payable {
        require(_totalSupply < dust, "initiated");
        require(msg.value > dust, "value too small");

        cEth.mint.value(msg.value)();

        address[] memory cTokens = new address[](1);
        cTokens[0] = address(cEth);
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        require(errors[0] == 0, "Comptroller.enterMarkets failed.");

        _mint(msg.sender, msg.value);
        cDai.borrow(amount);
        Dai.transfer(msg.sender, amount);
    }

    function collateral() public returns(uint256) {
        return cEth.balanceOfUnderlying(address(this));
    }

    function debt() public returns(uint256) {
        return cDai.borrowBalanceCurrent(address(this));
    }

    function mint() external payable returns(uint256) {
        require(_totalSupply >= dust, "not initiated");
        uint256 amount = msg.value;
        uint256 tokenToMint = _totalSupply.mul(amount).div(collateral());
        uint256 tokenToBorrow = debt().mul(amount).div(collateral());

        _mint(msg.sender, tokenToMint);

        cEth.mint.value(amount)();
        cDai.borrow(tokenToBorrow);
        Dai.transfer(msg.sender, tokenToBorrow);
    }

    function burn(uint256 amount) external {
        uint256 tokenToRepay = amount.mul(debt()).div(_totalSupply);
        uint256 tokenToDraw = amount.mul(collateral()).div(_totalSupply);

        _burn(msg.sender, amount);

        Dai.transferFrom(msg.sender, address(this), tokenToRepay);
        cDai.repayBorrow(tokenToRepay);
        cEth.redeemUnderlying(tokenToDraw);
        (bool success, ) = msg.sender.call.value(tokenToDraw)("");
        require(success, "Failed to transfer ether to msg.sender");
    }

    function() external payable{}
}

contract Exchange {
    function trade(
        address src,
        uint srcAmount,
        address dest,
        address destAddress,
        uint maxDestAmount,
        uint minConversionRate,
        address walletId )public payable returns(uint);
}

contract rebalanceCDP is tCDP {

    Exchange kyberNetwork = Exchange(0xF77eC7Ed5f5B9a5aee4cfa6FFCaC6A4C315BaC76);
    address etherAddr = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address ref = 0xD0533664013a82c31584B7FFDB215139f38Ad77A;

    uint256 public upperBound = 0.45 * 1e18; //45%
    uint256 public lowerBound = 0.35 * 1e18; //35%
    uint256 public bite = 0.025 * 1e18; //2.5%

    constructor() public {
        Dai.approve(address(kyberNetwork), uint256(-1));
    }

    function getUnderlyingPrice() public view returns(uint256) {
        address oracle = comptroller.oracle();
        PriceOracle priceOracle = PriceOracle(oracle);
        uint256 price = priceOracle.getUnderlyingPrice(address(cDai));
        return price;
    }

    function debtRatio() public returns(uint256) {
        address oracle = comptroller.oracle();
        PriceOracle priceOracle = PriceOracle(oracle);
        uint256 price = priceOracle.getUnderlyingPrice(address(cDai));
        uint256 ratio = debt().mul(price).div(collateral());
        return ratio;
    }

    function deleverage() public {
        require(_totalSupply >= dust, "not initiated");
        require(debtRatio() > upperBound, "debt ratio is good");
        uint256 amount = collateral().mul(bite).div(1e18);
        cEth.redeemUnderlying(amount);
        uint256 income = kyberNetwork.trade.value(amount)(etherAddr, amount, address(Dai), address(this), 1e28, 1, ref);
        cDai.repayBorrow(income);
    }

    function leverage() public {
        require(_totalSupply >= dust, "not initiated");
        require(debtRatio() < lowerBound, "debt ratio is good");
        uint256 amount = debt().mul(bite).div(1e18);
        cDai.borrow(amount);
        uint256 income = kyberNetwork.trade(address(Dai), amount, etherAddr, address(this), 1e28, 1, ref);
        cEth.mint.value(income)();
    }

    function CompoundDaiAPR() public view returns (uint256) {
        return cDai.borrowRatePerBlock().mul(2102400);
    }
    
    function CompoundEthAPR() public view returns (uint256) {
        return cEth.supplyRatePerBlock().mul(2102400);
    }

}
