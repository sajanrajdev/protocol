import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days


def test_mint_flow(quad, randomUser):
    # Setup
    snap = SnapshotManager(quad, "quadSnapshot")
    inputToken = quad.inputs(1)
    amount = 100000000000000000000
    qty = 25000000000000000000
    # End Setup
    snap.before()
    snap.quad_mint(inputToken, amount, qty, {"from": randomUser})
    snap.after()
   # Print table with metric, before, after and diff

   # Add assertions and reverts using the snap.before and snap.after objects
