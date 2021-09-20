from brownie import (
    accounts,
)

from config import (
    PRODUCTION_TOKENS, PRODUCTION_WEIGHTS, PRODUCTION_INPUTS, QUAD_MULTISIG
)

# Objective: 

def test_deploy_correct_settings(deployed):
    """
    Verifies that you set up the Quad properly
    """
    quad = deployed.quad

    # Assert Roles
    assert quad.governance() == QUAD_MULTISIG

    # Assert right token params
    

   
# Verify correct roles of deployed vs. config