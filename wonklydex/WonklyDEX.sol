// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "./../contracts/math/SafeMath.sol";
import "./../contracts/token/ERC20/ERC20.sol";
import "./../contracts/access/Ownable.sol";
import "./InvestorManager.sol";


contract WonklyDEX is Ownable,InvestorManager {

  using SafeMath for uint256;
  IERC20 token;

    uint256 public totalLiquidity;
  //  mapping (address => uint256) public liquidity;
    uint16 _fee;
    bool _paused;

  constructor(address token_addr) public {
    token = IERC20(token_addr);
    _fee=997;
    _paused=true;
  }
  

    modifier IhaveEnoughTokens(uint256 token_amount) {
        require( token_amount <= getMyTokensBalance() ,"I do not have enough tokens " );
        _;
    }
  
  
    modifier IhaveEnoughCoins(uint256 coins) {
        require( coins <= getMyCoinBalance() ,"I do not have enough coins " );
        _;
    }
    
   
    modifier hasApprovedTokens(address sender, uint256 token_amount) {
    require(  token.allowance(sender,address(this)) >= token_amount , "Does not have approved tokens!"); //sender != address(0) &&
    _;
  }


    modifier HasLiquidity() {
         require(totalLiquidity>0,"DEX:NOT init - Cero  liquidity");
        _;
      }

  
    modifier Active() {
         require( !isPaused() ," Error is paused!");
        _;
      }

  
    function isPaused() public view returns(bool){
        return _paused;
    }
    
    
    event Paused(bool paused);
    function setPause(bool paused) public onlyOwner returns(bool){
        _paused=paused;
        emit Paused(_paused);
        return true;
    }
    

    function getFee() public view returns(uint16){
        return _fee;    
    }
    
    event FeeChanged(uint16 oldFee, uint16 newFee);

    function setFee(uint16 newFee) public onlyOwner returns(bool){
        require( (newFee>=0 && newFee<=1000),'Invalid Fee value! (0 <= fee  <= 1000)');
        uint16 old=_fee;
        _fee=newFee;
        emit FeeChanged(old,_fee);
        return true;
    }
    
    event CoinReceived(uint256 coins);
      receive() external payable {
            // React to receiving ether
            emit CoinReceived(msg.value);
        }
        

    fallback()  external payable { emit CoinReceived(msg.value); }
  
    function getMyCoinBalance() public view returns(uint256){
            address payable self = address(this);
            uint256 bal =  self.balance;    
            return bal;
    }
    
    function getMyTokensBalance() public view returns(uint256){
        return token.balanceOf(address(this));
    }

    function getSCtokenAddress() public view returns(address){
        return address(token);
    }
    
    
    function calcTokenToDeposit(uint256 coinDeposit) public view returns(uint256){
          require(coinDeposit<=address(this).balance,"coinDeposit exceeded SC balance!");    
          uint256 eth_reserve = address(this).balance.sub(coinDeposit);
          uint256 token_reserve = token.balanceOf(address(this));
          return (coinDeposit.mul(token_reserve) / eth_reserve).add(1);
    }
  

    
    function currentTokensToCoin(uint256 token_amount)public view returns(uint256){
          uint256 token_reserve = token.balanceOf(address(this));
          return price(token_amount, token_reserve, address(this).balance);
    }
    
  
    event PoolCreated(uint256 totalLiquidity,address investor,uint256 token_amount);
    
    function createPool(uint256 token_amount) public payable hasApprovedTokens(msg.sender, token_amount) onlyNewInvestor(msg.sender) returns (uint256) {
          require(totalLiquidity==0,"DEX:init - already has liquidity");
          require(msg.value > 0 ,"Ivalid wei value (0) !");
          totalLiquidity = address(this).balance;
          //liquidity[msg.sender] = totalLiquidity;
          newInvestor(msg.sender,totalLiquidity );
          require(token.transferFrom(msg.sender, address(this), token_amount));
          _paused=false;
          emit PoolCreated( totalLiquidity,msg.sender,token_amount);
          return totalLiquidity;
    }
    
    event PoolClosed(uint256 eth_reserve,uint256 token_reserve, uint256 liquidity,address destination);    
    function closePool() public onlyOwner HasLiquidity returns(bool){
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 eth_reserve = address(this).balance;
        require(token.transfer(owner(), token_reserve) ,"Error token.transfer tokens ");
        address payable ow = address(uint160(owner()));
        ow.transfer(eth_reserve);
        uint256 liq=totalLiquidity;
        totalLiquidity=0;
        removeAllInvestor();
        _paused=true;
        emit PoolClosed( eth_reserve, token_reserve, liq,ow);    
        return true;
    }
    


    function price(uint256 input_amount, uint256 input_reserve, uint256 output_reserve) public view  returns (uint256) {
          uint256 input_amount_with_fee = input_amount.mul( uint256(_fee));
          uint256 numerator = input_amount_with_fee.mul(output_reserve);
          uint256 denominator = input_reserve.mul(1000).add(input_amount_with_fee);
          return numerator / denominator;
    }



    function currentCoinToTokens(uint256 coin_amount) public view returns(uint256){
        uint256 token_reserve = token.balanceOf(address(this));
        return price(coin_amount, address(this).balance.sub(coin_amount), token_reserve);

    }

    event PurchasedTokens(address purchaser,uint256 coins, uint256 tokens_bought);
    
    function coinToToken() public payable Active HasLiquidity  returns (uint256) {
          uint256 token_reserve = token.balanceOf(address(this));
          uint256 tokens_bought = price(msg.value, address(this).balance.sub(msg.value), token_reserve);
          require( tokens_bought <= getMyTokensBalance() ,"I do not have enough tokens " );
          require(token.transfer(msg.sender, tokens_bought) ,"Error token.transfer tokens ");
          emit PurchasedTokens(msg.sender,  msg.value,  tokens_bought);
          return tokens_bought;
    }

    event TokensSold(address vendor,uint256 eth_bought,uint256 token_amount);
    
    function tokenToCoin(uint256 token_amount) Active HasLiquidity hasApprovedTokens(msg.sender, token_amount)  public returns (uint256) {
          uint256 token_reserve = token.balanceOf(address(this));
          uint256 eth_bought = price(token_amount, token_reserve, address(this).balance);
          require( eth_bought <= getMyCoinBalance() ,"I do not have enough coins " );
          msg.sender.transfer(eth_bought);
          require(token.transferFrom(msg.sender, address(this), token_amount));
          emit TokensSold(msg.sender,eth_bought, token_amount);
          return eth_bought;
    }

    event Deposit(address investor,uint256 coins, uint256 token_amount,uint256 liquidity_minted );
    event LiquidityChanged(uint256 oldLiq, uint256 newLiq);
    
    function deposit() public payable Active HasLiquidity  returns (uint256) {
          uint256 eth_reserve = address(this).balance.sub(msg.value);
          uint256 token_reserve = token.balanceOf(address(this));
          uint256 token_amount = (msg.value.mul(token_reserve) / eth_reserve).add(1);
          require( msg.sender != address(0) && token.allowance(msg.sender,address(this)) >= token_amount   , "hasApprovedTokens: SC does not have approved tokens!"); 
          uint256 liquidity_minted = msg.value.mul(totalLiquidity) / eth_reserve;
          //liquidity[msg.sender] = liquidity[msg.sender].add(liquidity_minted);
          adminInvestor(msg.sender, liquidity_minted);
          uint256 oldLiq=totalLiquidity;
          totalLiquidity = totalLiquidity.add(liquidity_minted);
          require(token.transferFrom(msg.sender, address(this), token_amount));
          emit Deposit(msg.sender, msg.value, token_amount, liquidity_minted );
          emit LiquidityChanged(oldLiq, totalLiquidity);
          return liquidity_minted;
    }



    function calcMaxLiqWithdraw() public view onlyInvestorExist(msg.sender) returns(uint256){
        //(liquidity[msg.sender] * totalLiquidity) / address(this).balance = amount  
        
        //return liquidity[msg.sender].mul(totalLiquidity) / address(this).balance;
        
        return getInvestorLiquidity(msg.sender).mul(totalLiquidity) / address(this).balance;
    }

    function calcMaxWithdraw() public view onlyInvestorExist(msg.sender) returns(uint256, uint256){
            uint256 amount=calcMaxLiqWithdraw();
            if(amount==0){
                return (0, 0);    
            }

            uint256 token_reserve = token.balanceOf(address(this));
            uint256 eth_amount = amount.mul(address(this).balance) / totalLiquidity;
            uint256 token_amount = amount.mul(token_reserve) / totalLiquidity;
            return (eth_amount, token_amount);
    }


    function calcWithdraw(uint256 amount) public view onlyInvestorExist(msg.sender) returns(uint256, uint256){
            if(amount==0){
                return (0, 0);    
            }

            uint256 token_reserve = token.balanceOf(address(this));
            uint256 eth_amount = amount.mul(address(this).balance) / totalLiquidity;
            uint256 token_amount = amount.mul(token_reserve) / totalLiquidity;
            return (eth_amount, token_amount);
    }

    
    event Withdraw(address investor,uint256 coins, uint256 token_amount,uint256 newliquidity);
    
    function withdraw(uint256 amount) public Active HasLiquidity onlyInvestorExist(msg.sender) returns (uint256, uint256) {
          uint256 token_reserve = token.balanceOf(address(this));
          uint256 eth_amount = amount.mul(address(this).balance) / totalLiquidity;
          uint256 token_amount = amount.mul(token_reserve) / totalLiquidity;
          uint256 inv_liq=getInvestorLiquidity(msg.sender);
          
          require( eth_amount <= getMyCoinBalance() ,"I do not have enough coins " );
          require( token_amount <= getMyTokensBalance() ,"I do not have enough tokens " );
          require( eth_amount <= inv_liq ,"Liquidity exceeded " );
          
          //liquidity[msg.sender] = liquidity[msg.sender].sub(eth_amount);
          
          setInvestorSubLiquidity(msg.sender, eth_amount);
          
          uint256 oldLiq=totalLiquidity;
          totalLiquidity = totalLiquidity.sub(eth_amount);
          msg.sender.transfer(eth_amount);
          require(token.transfer(msg.sender, token_amount));
          emit Withdraw(msg.sender, eth_amount, token_amount, totalLiquidity );
          emit LiquidityChanged(oldLiq, totalLiquidity);
          return (eth_amount, token_amount);
    }



}
