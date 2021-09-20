from brownie import (
    accounts,
    network,
    interface,
    Quad,
    AdminUpgradeabilityProxy,
)

from config import (
    PRODUCTION_TOKENS, PRODUCTION_WEIGHTS, PRODUCTION_INPUTS, QUAD_MULTISIG
)

from dotmap import DotMap, test
import pytest


@pytest.fixture
def deployed():
    """
    Deploys Quad and Proxy and wires them up for you to test
    """

    deployer = accounts[0]
    manager = accounts.at("0x0754f5901702246350D232E099033787438d8130", force=True)
    governance = accounts.at(QUAD_MULTISIG, force=True)
    proxyAdmin = accounts[2]
    randomUser = accounts.at("0xf258c32069e40d2AadCb8788BC0F29884845AEBA", force=True)

    # Deploy proxy and Quad instance

    args = [
        governance,
        manager,
        PRODUCTION_TOKENS,
        PRODUCTION_WEIGHTS,
        PRODUCTION_INPUTS,
        False,
        "",
        "",
    ]

    quad_logic = Quad.deploy({"from": deployer})

    quad_proxy = AdminUpgradeabilityProxy.deploy(
        quad_logic,
        proxyAdmin,
        quad_logic.initialize.encode_input(*args),
        {"from": deployer},
    )

     ## We delete from deploy and then fetch again so we can interact
    AdminUpgradeabilityProxy.remove(quad_proxy)
    quad_proxy = Quad.at(quad_proxy.address)

    quad_proxy.unpause({"from": governance})
    print("[green]Quad was deployed at: [/green]", quad_proxy.address)

    ## Setup dummy account for testing

    lp = interface.IERC20(quad_proxy)
    print("[green] LP supply before mint [/green]", lp.totalSupply())

    DAI = interface.IERC20("0xd586E7F844cEa2F87f50152665BCbc2C279D8d70")

    DAI.approve(
      quad_proxy,
      100000000000000000000, 
      {"from": randomUser}
    )

    return DotMap(
        deployer=deployer,
        manager=manager,
        quad=quad_proxy,
        governance=governance,
        proxyAdmin=proxyAdmin,
        tokens=PRODUCTION_TOKENS,
        weights=PRODUCTION_WEIGHTS,
        inputs=PRODUCTION_INPUTS,
        randomUser=randomUser,
    )

## Contracts ##

@pytest.fixture
def quad(deployed):
    return deployed.quad

## Tokens ##

@pytest.fixture
def tokens():
    return [PRODUCTION_TOKENS]

## Weights ##

@pytest.fixture
def weights():
    return [PRODUCTION_WEIGHTS]

## Inputs ##

@pytest.fixture
def inputs():
    return [PRODUCTION_INPUTS]

## Accounts ##


@pytest.fixture
def deployer(deployed):
    return deployed.deployer


@pytest.fixture
def manager(quad):
    return accounts.at(quad.manager(), force=True)


@pytest.fixture
def governance(quad):
    return accounts.at(quad.governance(), force=True)

@pytest.fixture
def randomUser(deployed):
    return deployed.randomUser

@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass