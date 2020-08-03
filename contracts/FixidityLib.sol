pragma solidity 0.5.13;

import "./SignedSafeMath.sol";

library FixidityLib {
    using SignedSafeMath for int256;

    uint8 public constant initial_digits = 36;
    int256 public constant fixed_e = 2718281828459045235360287471352662498;
    int256 public constant fixed_pi = 3141592653589793238462643383279502884;
    int256
        public constant fixed_exp_10 = 22026465794806716516957900645284244000000;

    struct Fixidity {
        uint8 digits;
        int256 fixed_1;
        int256 fixed_e;
        int256 fixed_pi;
        int256 fixed_exp_10;
    }

    function init(Fixidity storage fixidity, uint8 digits) public {
        require(digits < 36, "digits should be less than 36");
        fixidity.digits = digits;
        fixidity.fixed_1 = int256(uint256(10)**uint256(digits));
        int256 t = int256(uint256(10)**uint256(initial_digits - digits));
        fixidity.fixed_e = fixed_e / t;
        fixidity.fixed_pi = fixed_pi / t;
        fixidity.fixed_exp_10 = fixed_exp_10 / t;
    }

    function round(Fixidity storage fixidity, int256 v)
        public
        view
        returns (int256)
    {
        return round_off(fixidity, v, fixidity.digits);
    }

    function floor(Fixidity storage fixidity, int256 v)
        public
        view
        returns (int256)
    {
        return v - (v % fixidity.fixed_1);
    }

    function multiply(
        Fixidity storage fixidity,
        int256 a,
        int256 b
    ) public view returns (int256) {
        int256 fixed_1 = fixidity.fixed_1;
        if (b == fixed_1) return a;
        int256 x1 = a / fixed_1;
        int256 x2 = a - fixed_1 * x1;
        int256 y1 = b / fixed_1;
        int256 y2 = b - fixed_1 * y1;
        return
            x1.mul(y1).mul(fixed_1).add(x1.mul(y2)).add(x2.mul(y1)).add(
                round_off(fixidity, x2.mul(y2), fixidity.digits).div(fixed_1)
            );
    }

    function divide(
        Fixidity storage fixidity,
        int256 a,
        int256 b
    ) public view returns (int256) {
        if (b == fixidity.fixed_1) return a;
        require(b != 0, "b should not be equal to 0");
        return
            multiply(fixidity, a % b, reciprocal(fixidity, b)) +
            (a / b) *
            fixidity.fixed_1;
    }

    function add(
        Fixidity storage fixidity,
        int256 a,
        int256 b
    ) public pure returns (int256) {
        int256 t = a + b;
        assert(t - a == b);
        return t;
    }

    function subtract(
        Fixidity storage fixidity,
        int256 a,
        int256 b
    ) public pure returns (int256) {
        int256 t = a - b;
        assert(t + b == a);
        return t;
    }

    function reciprocal(Fixidity storage fixidity, int256 a)
        public
        view
        returns (int256)
    {
        return
            round_off(
                fixidity,
                (10 * fixidity.fixed_1 * fixidity.fixed_1) / a,
                1
            ) / 10;
    }

    function round_off(
        Fixidity storage fixidity,
        int256 v,
        uint8 digits
    ) public pure returns (int256) {
        if (v == 0) {
            return 0;
        }
        int256 t = int256(uint256(10)**uint256(digits));
        int8 sign = 1;
        if (v < 0) {
            sign = -1;
            v = 0 - v;
        }
        if (v % t >= t / 2) {
            v = v + t - (v % t);
        } else {
            v = v - (v % t);
        }
        return v * sign;
    }

    function round_to(
        Fixidity storage fixidity,
        int256 v,
        uint8 digits
    ) public view returns (int256) {
        require(digits < fixidity.digits, "digits is out of range");
        return round_off(fixidity, v, fixidity.digits - digits);
    }

    function trunc_digits(
        Fixidity storage fixidity,
        int256 v,
        uint8 digits
    ) public view returns (int256) {
        if (digits == 0) return v;
        return round_off(fixidity, v, digits) / (10**digits);
    }
}
