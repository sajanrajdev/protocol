import time

from brownie import (
    accounts,
    network,
    interface,
    Quad,
    QuadExchange,
    AdminUpgradeabilityProxy,
)
from config import PRODUCTION_TOKENS, PRODUCTION_WEIGHTS, PRODUCTION_UNITS, PRODUCTION_INPUTS

import click
from rich.console import Console
console = Console()
sleep_between_tx = 1

def main():
    """
    FOR DEVELOPERS
    Deploys a Quad contract with parameters sent in the config. Also includes the deployment 
    of both proxy and implementation contracts using OZ Admin
    """

    # Get deployer account from local keystore
    dev = connect_account()

    # Get actors
    proxyAdmin = "0x0000000000000000000000000000000000000000" # In production, governance cannot be proxy admin.
    randomUser = accounts.at("0xf258c32069e40d2AadCb8788BC0F29884845AEBA", force=True)


    exchange = deploy_quad_exchange(dev, proxyAdmin)

    DAI = interface.IERC20("0xd586E7F844cEa2F87f50152665BCbc2C279D8d70")

    DAI.approve(
      exchange,
      10000000000000000000000, 
      {"from": randomUser}
    )

    # tx = exchange.getEstimatedQuadGivenAmount("0xd586E7F844cEa2F87f50152665BCbc2C279D8d70", 100000000000000000000, {"from": "0xf258c32069e40d2AadCb8788BC0F29884845AEBA"} )

    return exchange

def deploy_quad_exchange(dev, proxyAdmin):

    args = [
        PRODUCTION_TOKENS,
        PRODUCTION_WEIGHTS,
        PRODUCTION_UNITS,
        PRODUCTION_INPUTS 
    ]
    
    print("QuadExchange Arguments: ", args)


    quad_exchange_logic = QuadExchange.deploy({"from": dev}) #Quad Logic

    time.sleep(sleep_between_tx)


    quad_exchange_proxy = AdminUpgradeabilityProxy.deploy(
        quad_exchange_logic,
        proxyAdmin,
        quad_exchange_logic.initialize.encode_input(*args),
        {"from": dev},
    )
    
     ## We delete from deploy and then fetch again so we can interact
    AdminUpgradeabilityProxy.remove(quad_exchange_proxy)
    quad_exchange_proxy = QuadExchange.at(quad_exchange_proxy.address)

    console.print("[green]Quad Exchange was deployed at: [/green]", quad_exchange_proxy.address)

    return quad_exchange_proxy



def connect_account():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")
    return dev