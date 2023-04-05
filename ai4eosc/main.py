"""
Create an app with FastAPI
"""

from typing import Optional

from fastapi import Depends, FastAPI, Request, Response
from fastapi.security import HTTPBearer

# from ai4eosc.dependencies import get_query_token, get_token_header
# from .internal import admin

from ai4eosc.auth import init_flaat, flaat, get_user_info
from ai4eosc.routers import deployments, info, modules



app = FastAPI(
    # dependencies=[Depends(get_query_token)],
)

app.include_router(deployments.router)
app.include_router(info.router)
app.include_router(modules.router)

# app.include_router(
#     admin.router,
#     prefix="/admin",
#     tags=["admin"],
#     dependencies=[Depends(get_token_header)],
#     responses={418: {"description": "I'm a teapot"}},
# )

security = HTTPBearer()
init_flaat()


@app.get("/")
def root(
    authorization=Depends(security),
    ):
    user = get_user_info(token=authorization.credentials)
    return f"This is the AI4EOSC project's API. Current authenticated user: {user}"


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8081)
