methods{
    function Math.mulDiv(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivDownCVL(x,y,d);
}

function mulDivDownCVL(uint256 x, uint256 y, uint256 z) returns uint256 {
    assert z !=0, "mulDivDown error: cannot divide by zero";
    return require_uint256(x * y / z);
}