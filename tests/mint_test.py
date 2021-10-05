import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days


def test_mint_flow(quad):
    # Setup
    snap = SnapshotManager(quad, "quadSnapshot")
    # End Setup
    snap.before()
   # Print table with metric, before, after and diff

   # Add assertions and reverts using the snap.before and snap.after objects
