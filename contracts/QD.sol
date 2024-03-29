// SPDX-License-Identifier: MIT

pragma solidity 0.8.3; 

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
interface ILocker { // github.com/aurora-is-near/rainbow-token-connector/blob/master/erc20-connector/contracts/ERC20Locker.sol
    function lockToken(address ethToken, uint256 amount, string memory accountId) external;
} 

contract QD is Ownable, ERC20 {
    using SafeERC20 for ERC20;
    event Mint (address indexed reciever, uint cost_in_usd, uint qd_amt);
    // NEAR NEP-141s have this precision...
    uint constant internal _QD_DECIMALS = 24;
    uint constant internal _USDT_DECIMALS = 6;
    uint constant public PRICE_PRECISION = 1e18;
    uint constant public start_price = 22 * PRICE_PRECISION / 100;
    uint constant public final_price = 96 * PRICE_PRECISION / 100; // 9x6 = 54
    uint constant public MINT_QD_PER_DAY_MAX = 500_000;
    uint constant public SALE_START = 1647388800; // EOD Ides of March in GMT
    uint constant public SALE_LENGTH = 54 days;
    // twitter.com/Ukraine/status/1497594592438497282
    address constant public UA = 0x165CD37b4C644C2921454429E7F9358d18A45e14;
    uint public constant pie = 2_700_000_000_000_000_000_000_000_000_000; 
    uint public private_price = 6 * PRICE_PRECISION / 100; // 6th sense...
    uint public private_deposited;
    uint public public_deposited;
    uint public private_minted;
    // Set in constructor and never changed
    address immutable public lockyer;
    address immutable public tether;

    constructor(address _usdt, address _locker) ERC20("Qu!D", "QD") {
        private_minted = 2 * pie; // R = 5.4M, full circumference 
        _mint(_msgSender(), private_minted); // optimistically mint
        lockyer = _locker;
        tether = _usdt;
    }

    function withdraw() external {
        if (public_deposited > 0 && block.timestamp >= SALE_START + SALE_LENGTH) {
            ERC20(tether).approve(lockyer, public_deposited);
            ILocker(lockyer).lockToken(tether, public_deposited, "quid.near");
            public_deposited = 0; 
        } 
        if (private_deposited > 0) {
            ERC20(tether).safeTransfer(owner(), private_deposited);
            private_deposited = 0;
        }
    }

    function mint(uint qd_amt, address beneficiary) external returns (uint cost_in_usdt, uint aid) {  
        _mint(beneficiary, qd_amt);
        if (_msgSender() == owner()) {
            require(qd_amt == pie, "Wrong QD amount entered"); 
            require(private_price < start_price, "Can't allocate any more");
            
            cost_in_usdt = qd_amt * 10 ** _USDT_DECIMALS * private_price / PRICE_PRECISION / 10 ** _QD_DECIMALS; 
            private_price += 2 * PRICE_PRECISION / 100;
            private_deposited += cost_in_usdt;
            private_minted += qd_amt;   
        } else {
            require(qd_amt >= 100_000_000_000_000_000_000_000_000, "QD: MINT_R1"); // $100 minimum
            require(block.timestamp >= SALE_START && block.timestamp < SALE_START + SALE_LENGTH, "QD: MINT_R2"); // Too late
            require(totalSupply() - private_minted <= get_total_supply_cap(block.timestamp), "QD: MINT_R3"); // Cap minting

            cost_in_usdt = qd_amt_to_usdt_amt(qd_amt, block.timestamp); 
            aid = cost_in_usdt * 22 / 100; // 22% wartime tax to UA
            public_deposited += cost_in_usdt - aid;
        }
        ERC20(tether).safeTransferFrom(_msgSender(), address(this), cost_in_usdt); // reverts on failure (e.g. allowance)
        if (aid > 0) {
            ERC20(tether).safeTransfer(UA, aid);
        }
        emit Mint(beneficiary, cost_in_usdt, qd_amt);
    }
    function qd_amt_to_usdt_amt(uint qd_amt, uint block_timestamp) public pure returns (uint usdt_amount) {
        uint price = calculate_price(block_timestamp);
        // cost = amount / qd_multiplier * usdt_multipler * price
        usdt_amount = qd_amt * 10 ** _USDT_DECIMALS * price / PRICE_PRECISION / 10 ** _QD_DECIMALS;
    }
    function calculate_price( uint block_timestamp) public pure returns (uint price){
        uint time_elapsed = block_timestamp - SALE_START;
        // price = ((now - sale_start) // SALE_LENGTH) * (final_price - start_price) + start_price
        price = (final_price - start_price) * time_elapsed / SALE_LENGTH + start_price;
    }
    function get_total_supply_cap(uint block_timestamp) public pure returns (uint total_supply_cap) {
        uint time_elapsed = block_timestamp - SALE_START;
        total_supply_cap = MINT_QD_PER_DAY_MAX * 10 ** _QD_DECIMALS * time_elapsed / 1 days;
    }
    function decimals() public pure override(ERC20) returns (uint8) {
        return uint8(_QD_DECIMALS);
    }
}