import asyncio
import sys
import os

# Add backend to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'backend'))

from sqlalchemy.ext.asyncio import create_async_engine
from app.core.config import settings
from app.models.base import Base

# Import all models here to ensure they are registered with Base.metadata
import app.models

async def setup_db():
    print(f"Connecting to database...")
    engine = create_async_engine(settings.DATABASE_URL, echo=True)
    
    async with engine.begin() as conn:
        print("Creating tables...")
        await conn.run_sync(Base.metadata.create_all)
        print("Tables created successfully.")
    
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(setup_db())
