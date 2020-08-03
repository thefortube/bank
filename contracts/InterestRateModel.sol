pragma solidity 0.5.13;

import "./FixidityLib.sol";
import "./ExponentLib.sol";
import "./LogarithmLib.sol";

contract InterestRateModel {
    using FixidityLib for FixidityLib.Fixidity;
    using ExponentLib for FixidityLib.Fixidity;
    using LogarithmLib for FixidityLib.Fixidity;

    FixidityLib.Fixidity public fixidity;
    address public admin;
    address public proposedAdmin;

    int256 public constant point1 = 20000000000000000; //0.02 *1e18
    int256 public constant point2 = 381966011250105152; //0.382*1e18, (3-sqrt(5))/2
    int256 public constant point3 = 618033988749894848; //0.618*1e18, (sqrt(5)-1)/2
    int256 public constant point4 = 980000000000000000; //0.98 *1e18
    //https://www.mathsisfun.com/numbers/e-eulers-number.html
    int256 public constant e = 2718281828459045235; //2.71828182845904523536*1e18

    int256 public constant minInterest = 15000000000000000; //0.015*1e18

    int256 public reserveRadio = 100000000000000000; //10% spread
    int256 public constant ONE_ETH = 1e18;
    int256 public constant k = 191337753576934987; //point1^(e-1)

    constructor() public {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin can do this!");
        _;
    }

    function proposeNewAdmin(address admin_) external onlyAdmin {
        proposedAdmin = admin_;
    }

    function claimAdministration() external {
        require(msg.sender == proposedAdmin, "Not proposed admin.");
        admin = proposedAdmin;
        proposedAdmin = address(0);
    }

    // function setAdmin(address newAdmin) external onlyAdmin {
    //     admin = newAdmin;
    // }

    function init(uint8 digits) external onlyAdmin {
        fixidity.init(digits);
    }

    function setReserveRatio(int256 radio) external onlyAdmin {
        reserveRadio = radio;
    }

    //y=0.015+x^e; x: [0, (3-sqrt(5))/2], [0,0.382]
    function curve1(int256 x) public view returns (int256 y) {
        // y = minInterest + x**e;
        int256 xPowE = fixidity.power_any(x, e); //x**e
        y = fixidity.add(minInterest, xPowE);
    }

    //y=0.015+((3-sqrt(5))/2)**(e-1)*x; x:[(3-sqrt(5))/2,(sqrt(5)-1)/2], [0.382,0.618]
    function lineraSegment(int256 x) public view returns (int256 y) {
        // require(x > point1 && x <= point2, "invalid x in lineraSegment");
        int256 k = k;
        int256 kx = fixidity.multiply(k, x);
        y = fixidity.add(minInterest, kx);
    }

    // y = ((3-sqrt(5))/2)^(e-1) - (1-x)^e + 0.015
    // y = 0.015 - (1-x)^e+point2^(e-1)
    function curve2(int256 x) public view returns (int256 y) {
        if (x == ONE_ETH) {
            y = 206337753576934987; //0.206337753576934987*ONE_ETH
        } else {
            int256 c = k; //point1^(e-1)
            c = fixidity.add(c, minInterest);
            int256 x2 = fixidity.power_any(fixidity.subtract(ONE_ETH, x), e);
            y = fixidity.subtract(c, x2);
        }
    }

    //获取使用率
    function getBorrowPercent(int256 cash, int256 borrow)
        public
        view
        returns (int256 y)
    {
        // int total = fixidity.add(cash, borrow);
        // if (total == 0) {
        //     y = 0;
        // } else {
        //     y = fixidity.divide(borrow, total);
        // }
        y = fixidity.add(cash, borrow);
        if (y != 0) {
            y = fixidity.divide(borrow, y);
        }
    }

    //loanRate
    function getLoanRate(int256 cash, int256 borrow)
        public
        view
        returns (int256 y)
    {
        int256 u = getBorrowPercent(cash, borrow);
        if (u == 0) {
            return minInterest;
        }

        if (
            fixidity.subtract(u, point1) < 0 ||
            fixidity.subtract(point4, u) <= 0 ||
            (fixidity.subtract(u, point2) >= 0 &&
                fixidity.subtract(point3, u) > 0)
        ) {
            y = lineraSegment(u);
        } else if (fixidity.subtract(u, point2) < 0) {
            y = curve1(u);
        } else {
            y = curve2(u);
        }
    }

    //depositRate
    function getDepositRate(int256 cash, int256 borrow)
        external
        view
        returns (int256 y)
    {
        int256 loanRate = getLoanRate(cash, borrow);
        int256 loanRatePercent = fixidity.multiply(
            loanRate,
            getBorrowPercent(cash, borrow)
        );
        y = fixidity.multiply(
            loanRatePercent,
            fixidity.subtract(ONE_ETH, reserveRadio)
        );
    }

    //index(a, n) = index(a, n-1) * (1 + r*t), index为本金
    function calculateInterestIndex(
        int256 index,
        int256 r,
        int256 t
    ) external view returns (int256 y) {
        if (t == 0) {
            y = index;
        } else {
            int256 rt = fixidity.multiply(r, t);
            int256 sum = fixidity.add(rt, fixidity.fixed_1);
            y = fixidity.multiply(index, sum); //返回本息
        }
    }

    //r为年利率,t为秒数,p*e^(rt)
    function pert(
        int256 principal,
        int256 r,
        int256 t
    ) external view returns (int256 y) {
        if (t == 0 || r == 0) {
            y = principal;
        } else {
            int256 r1 = fixidity.log_e(fixidity.add(r, fixidity.fixed_1)); //r1 = ln(r+1)
            int256 r2 = fixidity.divide(r1, 60 * 60 * 24 * 365 * ONE_ETH); //r2=r1/(60*60*24*365)
            int256 interest = fixidity.power_e(
                fixidity.multiply(r2, t * ONE_ETH)
            ); //e^(r2*t)
            y = fixidity.multiply(principal, interest); //返回本息
        }
    }

    function calculateBalance(
        int256 principal,
        int256 lastIndex,
        int256 newIndex
    ) external view returns (int256 y) {
        if (principal == 0 || lastIndex == 0) {
            y = 0;
        } else {
            y = fixidity.divide(
                fixidity.multiply(principal, newIndex),
                lastIndex
            );
        }
    }

    function mul(int256 a, int256 b) internal view returns (int256 c) {
        c = fixidity.multiply(a, b);
    }

    function mul3(
        int256 a,
        int256 b,
        int256 c
    ) internal view returns (int256 d) {
        d = mul(a, mul(b, c));
    }

    function getNewReserve(
        int256 oldReserve,
        int256 cash,
        int256 borrow,
        int256 blockDelta
    ) external view returns (int256 y) {
        int256 borrowRate = getLoanRate(cash, borrow);
        int256 simpleInterestFactor = fixidity.multiply(borrowRate, blockDelta);
        y = fixidity.add(
            oldReserve,
            mul3(simpleInterestFactor, borrow, reserveRadio)
        );
    }
}
