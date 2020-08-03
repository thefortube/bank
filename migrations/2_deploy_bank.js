var FixidityLib = artifacts.require("FixidityLib");
var LogarithmLib = artifacts.require("LogarithmLib");
var ExponentLib = artifacts.require("ExponentLib");
var InterestRateModel = artifacts.require("InterestRateModel");
var PriceOracles = artifacts.require("PriceOracles");
var PoolPawn = artifacts.require("PoolPawn");
var SignedSafeMath = artifacts.require("SignedSafeMath");

var fs = require("fs");

module.exports = async function(deployer, network) {
    network = /([a-z]+)(-fork)?/.exec(network)[1];
    var output = './deployed_' + network + ".json";
    if(fs.existsSync(output)) {
        fs.unlinkSync(output);
    }

    await deployer.deploy(SignedSafeMath);
    await deployer.link(SignedSafeMath, FixidityLib);
    await deployer.deploy(FixidityLib);
    await deployer.link(FixidityLib, LogarithmLib);
    await deployer.deploy(LogarithmLib);
    await deployer.link(LogarithmLib, ExponentLib);
    await deployer.link(FixidityLib, ExponentLib);
    await deployer.deploy(ExponentLib);

    await deployer.link(FixidityLib, InterestRateModel);
    await deployer.link(LogarithmLib, InterestRateModel);
    await deployer.link(ExponentLib, InterestRateModel);
    await deployer.deploy(InterestRateModel);

    await deployer.deploy(PriceOracles);
    await deployer.deploy(PoolPawn);
    
    var deployed = {
        FixidityLib: FixidityLib.address,
        LogarithmLib: LogarithmLib.address,
        ExponentLib: ExponentLib.address,
        InterestRateModel: InterestRateModel.address,
        PriceOracles: PriceOracles.address,
        PoolPawn: PoolPawn.address
    };

    fs.writeFileSync(output, JSON.stringify(deployed, null, 4));
};