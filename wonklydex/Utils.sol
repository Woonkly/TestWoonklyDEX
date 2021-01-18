// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;



library Utils {


function getStringLen(string memory str)  internal pure returns (uint){
    bytes memory tempEmptyStringTest = bytes(str); // Uses memory
    return tempEmptyStringTest.length;
}



function checkEven(uint testNo) internal  pure returns(bool){
        uint remainder = testNo%2;
        if(remainder==0)
            return true;
        else
            return false;
    }
    
}






