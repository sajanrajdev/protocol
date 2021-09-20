import time

from brownie import (
    accounts,
    network,
    interface,
    Quad,
    AdminUpgradeabilityProxy,
)
from config import PRODUCTION_TOKENS, PRODUCTION_WEIGHTS, PRODUCTION_INPUTS

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
    governance = dev.address
    manager = dev.address
    proxyAdmin = "0x0000000000000000000000000000000000000000" # In production, governance cannot be proxy admin.

    # Deploy Quad

    quad = deploy_quad(dev, proxyAdmin, governance, manager)

    quad.unpause({"from": governance})
    
    return quad

def deploy_quad(dev, proxyAdmin, governance, manager):

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
    
    print("Quad Arguments: ", args)


    quad_logic = Quad.deploy({"from": dev}) #Quad Logic

    time.sleep(sleep_between_tx)


    quad_proxy = AdminUpgradeabilityProxy.deploy(
        quad_logic,
        proxyAdmin,
        quad_logic.initialize.encode_input(*args),
        {"from": dev},
    )

     ## We delete from deploy and then fetch again so we can interact
    AdminUpgradeabilityProxy.remove(quad_proxy)
    quad_proxy = Quad.at(quad_proxy.address)

    console.print("[green]Quad was deployed at: [/green]", quad_proxy.address)

    return quad_proxy

def connect_account():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")
    return dev