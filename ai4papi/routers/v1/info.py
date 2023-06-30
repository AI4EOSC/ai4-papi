"""
Misc routes.

Methods returning the conf are authenticated in order to be
able to fill the `Virtual Organization` field.
"""

from copy import deepcopy

from fastapi import APIRouter, HTTPException
from fastapi.security import HTTPBearer
import requests
import secrets

from ai4papi import quotas
import ai4papi.conf as papiconf


router = APIRouter(
    prefix="/info",
    tags=["info"],
    responses={404: {"description": "Not found"}},
)

security = HTTPBearer()


@router.get("/conf/{module_name}")
def get_default_deployment_conf(
    module_name: str,
    vo: str,
):
    """
    Returns the default configuration (dict) for creating a deployment
    for a specific module. It is prefilled with the appropriate
    docker image and the available docker tags.
    """
    #TODO: We are not checking if module exists in the marketplace because
    # we are treating each route as independent. In the future, this can
    # be done as an API call to the other route.

    # Generate the conf
    if module_name == 'DEEP-OC-federated-server':
        conf = deepcopy(papiconf.USER_FED_CONF)
    else:
        conf = deepcopy(papiconf.USER_MODULE_CONF)

    # Fill with correct Docker image
    conf["general"]["docker_image"]["value"] = f"deephdc/{module_name.lower()}"

    # Add available Docker tags
    url = f"https://registry.hub.docker.com/v2/repositories/deephdc/{module_name.lower()}/tags"
    try:
        r = requests.get(url)
        r.raise_for_status()
        r = r.json()
    except Exception:
        raise HTTPException(
            status_code=400,
            detail=f"Could not retrieve Docker tags from {module_name}.",
            )

    tags = [i["name"] for i in r["results"]]
    conf["general"]["docker_tag"]["options"] = tags
    conf["general"]["docker_tag"]["value"] = tags[0]

    # Use VS Code (Coder OSS) in the development container
    if module_name == 'DEEP-OC-generic-dev':
        conf["general"]["service"]["value"] = 'vscode'
        conf["general"]["service"]["options"].insert(0, 'vscode')
        conf["general"]["service"]["options"].remove('deepaas')  # no models installed in dev

    if module_name == 'DEEP-OC-federated-server':
        conf["general"]["federated_secret"]["value"] = secrets.token_hex()

    # Available GPU models
    # TODO: add automated discovery of GPU models reading the Clients metadata tags

    # Modify the resources limits for a given user or VO
    conf['hardware'] = quotas.limit_resources(
        module_name=module_name,
        vo=vo,
    )

    return conf
