// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAaveOracle} from '@aave/core-v3/contracts/interfaces/IAaveOracle.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IPoolConfigurator} from '@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol';
import {ConfiguratorInputTypes} from '@aave/core-v3/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol';

import {GhoToken} from 'src/contracts/gho/GhoToken.sol';
import {GhoOracle} from 'src/contracts/facilitators/aave/oracle/GhoOracle.sol';
import {GhoAToken} from 'src/contracts/facilitators/aave/tokens/GhoAToken.sol';
import {GhoVariableDebtToken} from 'src/contracts/facilitators/aave/tokens/GhoVariableDebtToken.sol';
import {GhoInterestRateStrategy} from 'src/contracts/facilitators/aave/interestStrategy/GhoInterestRateStrategy.sol';
import {GhoFlashMinter} from 'src/contracts/facilitators/flashMinter/GhoFlashMinter.sol';

import 'forge-std/console.sol';

contract LastTestnetReservesConfig {

  GhoAToken ghoAToken;
  GhoVariableDebtToken ghoVariableDebtToken;
  
  function _deployTestnetTokens(
    address deployer
  )
    internal
    returns (
        address[] memory tokens,
        address[] memory oracles
    )
  { 
    tokens  = new address[](1);

    tokens[0] = address(new GhoToken(deployer));

    oracles = new address[](1);

    oracles[0] = address(new GhoOracle());

    return (tokens, oracles);
  }

  function _fetchTestnetTokens(
    address deployer
  )
    internal
    returns (
        address[] memory tokens
    )
  { 
    tokens  = new address[](1);
    
    tokens[0] = address(0x0); // GHO

    return tokens;
  }

function _setGhoOracle(
    address[] memory tokens,
    address[] memory oracles
  )
    internal
  { 
    // set oracles
    _getAaveOracle().setAssetSources(tokens, oracles);
  }

  function _initializeGhoReserve(
    address[] memory tokens
  ) 
    internal
  {
    ConfiguratorInputTypes.InitReserveInput[] memory inputs = new ConfiguratorInputTypes.InitReserveInput[](1);

    ghoAToken = new GhoAToken(
      IPool(0xBD2f32C02140641f497B0Db7B365122214f7c548) // Pool
    );

    ghoVariableDebtToken = new GhoVariableDebtToken(
      IPool(0xBD2f32C02140641f497B0Db7B365122214f7c548)
    );

    GhoInterestRateStrategy ghoInterestRateStrategy = new GhoInterestRateStrategy(
      0x270542372e5a73c39E4290291AB88e2901cCEF2D, // PoolAddressesProvider
      15000000000000000000000000 // base variable borrow rate (1.5%)
    );

    inputs[0] = ConfiguratorInputTypes.InitReserveInput({
      aTokenImpl: address(ghoAToken), // Address of the aToken implementation
      variableDebtTokenImpl: address(ghoVariableDebtToken), // Address of the variable debt token implementation
      useVirtualBalance: false, // true for all normal assets and should be false only in special cases (ex. GHO) where an asset is minted instead of supplied.
      interestRateStrategyAddress: address(ghoInterestRateStrategy), // Address of the interest rate strategy
      underlyingAsset: address(tokens[0]), // GHO address
      treasury: address(0xa2CCdD20525d5225b4AB08c10D1aFfb6de84D518), // Address of the treasury
      incentivesController: address(0x21455b64CD8f992B2500a55243d2C179a77C83A1), // Address of the incentives controller
      aTokenName: 'USDXL Aave',
      aTokenSymbol: 'awUSDXL',
      variableDebtTokenName: 'Test USDXL Variable Debt Aave',
      variableDebtTokenSymbol: 'variableDebtTestUSDXL',
      params: bytes('0x10'), // Additional parameters for initialization
      interestRateData: bytes('')
    });
    
    // set reserves configs
    _getPoolConfigurator().initReserves(inputs);
  }

  function _enableCollateral(
    address[] memory tokens
  )
    internal
  {
    _getPoolConfigurator().configureReserveAsCollateral(
      tokens[0],
      8000, // LTV (80%)
      9000, // Liq. threshold (90%)
      10500 // Liq. bonus (5% tax)
    );
  }

  function _enableGhoBorrowing(
    address[] memory tokens
  )
    internal
  {
    _getPoolConfigurator().setReserveBorrowing(tokens[0], true);
  }

  function _addGhoATokenAsEntity(
    address[] memory tokens
  )
    internal
  {
    GhoToken(tokens[0]).addFacilitator(
      address(ghoAToken),
      'Aave V3 Last Testnet Market', // entity label
      1e27 // entity mint limit (100mil)
    );
  }

  function _addGhoFlashMinterAsEntity(
    address[] memory tokens
  )
    internal
  {
    GhoFlashMinter ghoFlashMinter = new GhoFlashMinter(
      tokens[0], // GHO token
      0xa2CCdD20525d5225b4AB08c10D1aFfb6de84D518, // TreasuryProxy
      0, // fee in bips for flash-minting (covered on repay)
      0x270542372e5a73c39E4290291AB88e2901cCEF2D // PoolAddressesProvider
    );

    GhoToken(tokens[0]).addFacilitator(
      address(ghoFlashMinter),
      'Aave V3 Last Testnet Market', // entity label
      1e27 // entity mint limit (100mil)
    );
  }

  function _setGhoAddresses(
    address[] memory tokens
  )
    internal
  {
    ghoAToken.updateGhoTreasury(0xa2CCdD20525d5225b4AB08c10D1aFfb6de84D518);

    ghoAToken.setVariableDebtToken(address(ghoVariableDebtToken));

    ghoVariableDebtToken.setAToken(address(ghoAToken));
  }

  function _setDiscountRateStrategy(
    address discountRateStrategy,
    address discountToken
  )
    internal
  {
    ghoVariableDebtToken.updateDiscountRateStrategy(discountRateStrategy);
    ghoVariableDebtToken.updateDiscountToken(discountToken);
  }

  function _getAaveOracle()
    internal
    pure
    returns (
      IAaveOracle
    )
  {
    return IAaveOracle(0xE6C26ED28215f2bb33C3F97768d250eFC98586b4);
  }

  function _getPoolConfigurator()
    internal
    pure
    returns (
      IPoolConfigurator
    )
  {
    return IPoolConfigurator(0x4c1E6019200329A039d5AD5b577838967250c0C3);
  }
}
