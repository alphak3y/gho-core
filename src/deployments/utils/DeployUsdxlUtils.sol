// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {stdJson} from "forge-std/StdJson.sol";
import {DeployUsdxlFileUtils} from "src/deployments/utils/DeployUsdxlFileUtils.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {IUsdxlToken} from "src/contracts/usdxl/interfaces/IUsdxlToken.sol";
import {UpgradeableUsdxlToken} from "src/contracts/usdxl/UpgradeableUsdxlToken.sol";
import {UsdxlOracle} from "src/contracts/facilitators/hyfi/oracle/UsdxlOracle.sol";
import {UsdxlAToken} from "src/contracts/facilitators/hyfi/tokens/UsdxlAToken.sol";
import {UsdxlVariableDebtToken} from "src/contracts/facilitators/hyfi/tokens/UsdxlVariableDebtToken.sol";
import {UsdxlInterestRateStrategy} from "src/contracts/facilitators/hyfi/interestStrategy/UsdxlInterestRateStrategy.sol";
import {UsdxlFlashMinter} from "src/contracts/facilitators/flashMinter/UsdxlFlashMinter.sol";
import {Gsm} from "src/contracts/facilitators/gsm/Gsm.sol";
import {FixedFeeStrategy} from "src/contracts/facilitators/gsm/feeStrategy/FixedFeeStrategy.sol";
import {FixedPriceStrategy} from "src/contracts/facilitators/gsm/priceStrategy/FixedPriceStrategy.sol";
import {IUsdxlConfigsTypes} from "src/deployments/interfaces/IUsdxlConfigsTypes.sol";

import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {AdminUpgradeabilityProxy} from
    "@aave/core-v3/contracts/dependencies/openzeppelin/upgradeability/AdminUpgradeabilityProxy.sol";
import {IDeployConfigTypes} from "@hypurrfi/deployments/configs/HyperTestnetReservesConfigs.sol";
import {DeployHyFiUtils} from "@hypurrfi/deployments/utils/DeployHyFiUtils.sol";
import {IERC20Metadata} from "@hypurrfi/contracts/dependencies/openzeppelin/interfaces/IERC20Metadata.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolConfigurator} from "@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol";
import {HyFiOracle} from "@hypurrfi/core/contracts/misc/HyFiOracle.sol";
import {ConfiguratorInputTypes} from "@aave/core-v3/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import {ERC20} from 'lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import {ZeroDiscountRateStrategy} from 'src/contracts/facilitators/hyfi/interestStrategy/ZeroDiscountRateStrategy.sol';

abstract contract DeployUsdxlUtils is DeployHyFiUtils, IUsdxlConfigsTypes, IDeployConfigTypes {
    using DeployUsdxlFileUtils for string;
    using stdJson for string;

    IUsdxlToken public usdxlToken;
    UsdxlAToken public usdxlAToken;
    address public usdxlTokenProxy;
    UsdxlVariableDebtToken public usdxlVariableDebtToken;
    UsdxlOracle public usdxlOracle;
    UsdxlInterestRateStrategy public usdxlInterestRateStrategy;
    UsdxlFlashMinter public flashMinter;
    UsdxlDeployRegistry public usdxlDeployRegistry;
    HypurrDeployRegistry public hypurrDeployRegistry;

    function _deployUsdxl(address proxyAdmin) internal {
        address[] memory tokens = new address[](1);
        address[] memory oracles = new address[](1);
        
        // 1. Deploy USDXL token implementation and proxy
        UpgradeableUsdxlToken usdxlTokenImpl = new UpgradeableUsdxlToken();

        bytes memory initParams = abi.encodeWithSignature("initialize(address)", deployer);

        usdxlTokenProxy = address(new TransparentUpgradeableProxy(address(usdxlTokenImpl), proxyAdmin, initParams));

        usdxlToken = IUsdxlToken(usdxlTokenProxy);

        tokens[0] = address(usdxlToken);

        // 2. Deploy USDXL Oracle
        usdxlOracle = new UsdxlOracle();

        oracles[0] = address(usdxlOracle);

        // 3. Deploy USDXL Interest Rate Strategy
        usdxlInterestRateStrategy = new UsdxlInterestRateStrategy(
            hypurrDeployRegistry.poolAddressesProvider,
            0.02e27 // 2% base rate
        );

        // 4. Deploy USDXL AToken and Variable Debt Token
        usdxlAToken = new UsdxlAToken(IPool(IPoolAddressesProvider(hypurrDeployRegistry.poolAddressesProvider).getPool()));

        usdxlVariableDebtToken =
            new UsdxlVariableDebtToken(IPool(IPoolAddressesProvider(hypurrDeployRegistry.poolAddressesProvider).getPool()));

        // 5. Deploy Flash Minter
        flashMinter = new UsdxlFlashMinter(
            address(usdxlToken),
            hypurrDeployRegistry.treasury,
            0, // no fee
            hypurrDeployRegistry.poolAddressesProvider
        );

        // 6. Grant facilitator manager role
        _grantFacilitatorManagerRole(deployer);

        // 7. Set USDXL Oracle
        _setUsdxlOracle(tokens, oracles);

        // 8. Set reserve config
        _initializeUsdxlReserve(tokens[0]);

        // 9. Disable stable debt
        _disableStableDebt(tokens);

        // 10. Update interest rate strategy
        _updateUsdxlInterestRateStrategy();

        // 11. Enable USDXL borrowing
        _enableUsdxlBorrowing();

        // 12. Add USDXL as entity
        _addUsdxlATokenAsEntity();

        // 13. Add USDXL flashminter as entity
        _addUsdxlFlashMinterAsEntity();

        // 14. Revoke facilitator manager role
        _revokeFacilitatorManagerRole(deployer);

        // 15. Set USDXL addresses
        _setUsdxlAddresses();

        ERC20 nonMintableErc20;

        nonMintableErc20 = new ERC20('Discount Token', 'DSCNT');

        ZeroDiscountRateStrategy discountRateStrategy;

        discountRateStrategy = new ZeroDiscountRateStrategy();

        _setDiscountTokenAndStrategy(address(discountRateStrategy), address(nonMintableErc20));

        // Export contract addresses
        _exportContracts();
    }

    function _exportContracts() internal {
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlTokenImpl", address(usdxlToken));
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlTokenProxy", usdxlTokenProxy);
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlOracle", address(usdxlOracle));
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlATokenImpl", address(usdxlAToken));
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlVariableDebtTokenImpl", address(usdxlVariableDebtToken));
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlFlashMinterImpl", address(flashMinter));
    }

    function _setDeployRegistry(string memory deployedContracts) internal {
        hypurrDeployRegistry = IDeployConfigTypes.HypurrDeployRegistry({
            hyTokenImpl: deployedContracts.readAddress(".hyTokenImpl"),
            hyFiOracle: deployedContracts.readAddress(".hyFiOracle"),
            aclManager: deployedContracts.readAddress(".aclManager"),
            admin: deployedContracts.readAddress(".admin"),
            defaultInterestRateStrategy: deployedContracts.readAddress(".defaultInterestRateStrategy"),
            deployer: deployedContracts.readAddress(".deployer"),
            emissionManager: deployedContracts.readAddress(".emissionManager"),
            incentives: deployedContracts.readAddress(".incentives"),
            incentivesImpl: deployedContracts.readAddress(".incentivesImpl"),
            pool: deployedContracts.readAddress(".pool"),
            poolAddressesProvider: deployedContracts.readAddress(".poolAddressesProvider"),
            poolAddressesProviderRegistry: deployedContracts.readAddress(".poolAddressesProviderRegistry"),
            poolConfigurator: deployedContracts.readAddress(".poolConfigurator"),
            poolConfiguratorImpl: deployedContracts.readAddress(".poolConfiguratorImpl"),
            poolImpl: deployedContracts.readAddress(".poolImpl"),
            protocolDataProvider: deployedContracts.readAddress(".protocolDataProvider"),
            disabledStableDebtTokenImpl: deployedContracts.readAddress(".disabledStableDebtTokenImpl"),
            treasury: deployedContracts.readAddress(".treasury"),
            treasuryImpl: deployedContracts.readAddress(".treasuryImpl"),
            uiIncentiveDataProvider: deployedContracts.readAddress(".uiIncentiveDataProvider"),
            uiPoolDataProvider: deployedContracts.readAddress(".uiPoolDataProvider"),
            variableDebtTokenImpl: deployedContracts.readAddress(".variableDebtTokenImpl"),
            walletBalanceProvider: deployedContracts.readAddress(".walletBalanceProvider"),
            wrappedHypeGateway: deployedContracts.readAddress(".wrappedHypeGateway")
        });
    }
    
    function _deployGsm(
        address token,
        address gsmOwner,
        uint256 maxCapacity
    ) internal returns (address gsmProxy) {
        // Deploy price and fee strategies
        FixedPriceStrategy fixedPriceStrategy = new FixedPriceStrategy(
            1e8, // Default price of $1.00
            address(token),
            IERC20Metadata(token).decimals()
        );

        FixedFeeStrategy fixedFeeStrategy = new FixedFeeStrategy(
            0.02e4, // 2% for buys
            0 // 0% for sells
        );

        // Deploy GSM implementation
        Gsm gsmImpl = new Gsm(address(usdxlToken), address(token), address(fixedPriceStrategy));

        // Deploy and initialize GSM proxy
        AdminUpgradeabilityProxy proxy = new AdminUpgradeabilityProxy(
            address(gsmImpl),
            address(0), // TODO: set admin to timelock
            ""
        );

        Gsm(address(proxy)).initialize(gsmOwner, hypurrDeployRegistry.treasury, uint128(maxCapacity));

        // Export contracts
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmImpl", address(gsmImpl));
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmProxy", address(proxy));
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmFixedPriceStrategyImpl", address(fixedPriceStrategy));
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmFixedFeeStrategyImpl", address(fixedFeeStrategy));

        return address(proxy);
    }

    function _grantFacilitatorManagerRole(address deployer) internal {
        UpgradeableUsdxlToken(address(usdxlTokenProxy)).grantRole(
            UpgradeableUsdxlToken(address(usdxlTokenProxy)).FACILITATOR_MANAGER_ROLE(), deployer
        );
    }

    function _revokeFacilitatorManagerRole(address deployer) internal {
        UpgradeableUsdxlToken(address(usdxlTokenProxy)).revokeRole(
            UpgradeableUsdxlToken(address(usdxlTokenProxy)).FACILITATOR_MANAGER_ROLE(),
            deployer
        );
    }

    function _setUsdxlOracle(
        address[] memory tokens,
        address[] memory oracles
    )
        internal
    {
        // set oracles
        _getHyFiOracle().setAssetSources(tokens, oracles);
    }

      function _initializeUsdxlReserve(
        address token
      )
        internal
      {
        ConfiguratorInputTypes.InitReserveInput[] memory inputs = new ConfiguratorInputTypes.InitReserveInput[](1);

        usdxlAToken = new UsdxlAToken(
          _getPoolInstance()
        );

        usdxlVariableDebtToken = new UsdxlVariableDebtToken(
          _getPoolInstance()
        );

        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlATokenImpl", address(usdxlAToken));
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlVariableDebtTokenImpl", address(usdxlVariableDebtToken));

        IERC20Metadata tokenMetadata = IERC20Metadata(token);

        inputs[0] = ConfiguratorInputTypes.InitReserveInput({
          aTokenImpl: address(usdxlAToken), // Address of the aToken implementation
          stableDebtTokenImpl: address(hypurrDeployRegistry.disabledStableDebtTokenImpl), // Disabled - not using stable debt in this implementation
          variableDebtTokenImpl: address(usdxlVariableDebtToken), // Address of the variable debt token implementation
          underlyingAssetDecimals: tokenMetadata.decimals(),
          interestRateStrategyAddress: hypurrDeployRegistry.defaultInterestRateStrategy, // Address of the interest rate strategy
          underlyingAsset: address(token), // Address of the underlying asset
          treasury: hypurrDeployRegistry.treasury, // Address of the treasury
          incentivesController: hypurrDeployRegistry.incentives, // Address of the incentives controller
          aTokenName: string(abi.encodePacked(tokenMetadata.symbol(), " Hypurr")),
          aTokenSymbol: string(abi.encodePacked("hy", tokenMetadata.symbol())),
          variableDebtTokenName: string(abi.encodePacked(tokenMetadata.symbol(), " Variable Debt Hypurr")),
          variableDebtTokenSymbol: string(abi.encodePacked("variableDebt", tokenMetadata.symbol())),
          stableDebtTokenName: "", // Empty as stable debt is disabled
          stableDebtTokenSymbol: "", // Empty as stable debt is disabled
          params: bytes("") // Additional parameters for initialization
        });

        // set reserves configs
        _getPoolConfigurator().initReserves(inputs);

        // export contract addresses
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlATokenProxy", _getUsdxlATokenProxy());
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlVariableDebtTokenProxy", _getUsdxlVariableDebtTokenProxy());
    }

    function _disableStableDebt(address[] memory tokens) internal {
        for (uint256 i; i < tokens.length;) {
            // Disable stable borrowing
            _getPoolConfigurator().setReserveStableRateBorrowing(tokens[i], false);
            unchecked {
                i++;
            }
        }
    }

    function _updateUsdxlInterestRateStrategy()
        internal
    {
        UsdxlInterestRateStrategy interestRateStrategy = new UsdxlInterestRateStrategy(
          address(hypurrDeployRegistry.poolAddressesProvider),
          0.02e27
        );

        _getPoolConfigurator().setReserveInterestRateStrategyAddress(address(_getUsdxlToken()), address(interestRateStrategy));
    }

    function _enableUsdxlBorrowing()
        internal
    {
        _getPoolConfigurator().setReserveBorrowing(address(usdxlTokenProxy), true);
    }

    function _addUsdxlATokenAsEntity()
        internal
    {
        // pull aToken proxy from reserves config
        _getUsdxlToken().addFacilitator(
          address(_getUsdxlATokenProxy()),
          'HypurrFi Market Loans', // entity label
          1e27 // entity mint limit (100mil)
        );
    }

    function _addUsdxlFlashMinterAsEntity()
        internal
    {
      _getUsdxlToken().addFacilitator(
        address(flashMinter),
        'HypurrFi Market Flash Loans', // entity label
        1e27 // entity mint limit (100mil)
      );
    }

    function _setUsdxlAddresses()
        internal
    {
      usdxlAToken.updateUsdxlTreasury(hypurrDeployRegistry.treasury);

      UsdxlAToken(_getUsdxlATokenProxy()).setVariableDebtToken(_getUsdxlVariableDebtTokenProxy());

      // set aToken
      UsdxlVariableDebtToken(_getUsdxlVariableDebtTokenProxy()).setAToken(_getUsdxlATokenProxy());
    }

    function _setDiscountTokenAndStrategy(
      address discountRateStrategy,
      address discountToken
    )
      internal
    {
      usdxlVariableDebtToken = UsdxlVariableDebtToken(_getUsdxlVariableDebtTokenProxy());
      if (discountRateStrategy != address(0))
        usdxlVariableDebtToken.updateDiscountRateStrategy(discountRateStrategy);
      if (discountToken != address(0))
        usdxlVariableDebtToken.updateDiscountToken(discountToken);
    }

    function _getUsdxlToken() internal view returns (IUsdxlToken) {
        return IUsdxlToken(usdxlTokenProxy);
    }

    function _getUsdxlATokenProxy() internal view returns (address) {
        // read from reserves config
        return _getPoolInstance().getReserveData(address(usdxlToken)).aTokenAddress;
    }

    function _getUsdxlVariableDebtTokenProxy() internal view returns (address) {
        // read from reserves config
        return _getPoolInstance().getReserveData(address(usdxlToken)).variableDebtTokenAddress;
    }

    function _getHyFiOracle() internal view returns (HyFiOracle) {
        return HyFiOracle(hypurrDeployRegistry.hyFiOracle);
    }

    function _getPoolConfigurator() internal view returns (IPoolConfigurator) {
        return IPoolConfigurator(hypurrDeployRegistry.poolConfigurator);
    }

    function _getPoolAddressesProvider() internal view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(hypurrDeployRegistry.poolAddressesProvider);
    }

    function _getPoolInstance() internal view returns (IPool) {
        return IPool(hypurrDeployRegistry.pool);
    }
}
