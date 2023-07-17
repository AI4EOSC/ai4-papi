import fastapi

from . import modules, tools


app = fastapi.APIRouter()
app.include_router(
    router=modules.router,
    prefix='/catalog',
    )
app.include_router(
    router=tools.router,
    prefix='/catalog',
    )
