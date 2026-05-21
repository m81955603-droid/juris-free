from fastapi import APIRouter
router = APIRouter()

@router.get("/health")
async def health():
    return {"status": "ok", "service": "juris-free-bolivia", "version": "1.0.0"}

@router.get("/")
async def root():
    return {"message": "JURIS-FREE Bolivia API — Sistema Juridico Open Source"}
