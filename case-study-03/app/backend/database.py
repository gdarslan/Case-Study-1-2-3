import os
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

load_dotenv()


def get_connection():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASS"],
        cursor_factory=psycopg2.extras.RealDictCursor,
    )


def init_db():
    """Create the employees table if it does not exist yet."""
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS employees (
                    id          SERIAL PRIMARY KEY,
                    name        VARCHAR(100)  NOT NULL,
                    email       VARCHAR(150)  NOT NULL UNIQUE,
                    department  VARCHAR(100)  NOT NULL,
                    role        VARCHAR(100)  NOT NULL,
                    status      VARCHAR(20)   NOT NULL DEFAULT 'active'
                                              CHECK (status IN ('active','inactive','pending')),
                    sso_user_id VARCHAR(200),
                    created_at  TIMESTAMP     NOT NULL DEFAULT NOW(),
                    updated_at  TIMESTAMP     NOT NULL DEFAULT NOW()
                )
            """)
        conn.commit()
    finally:
        conn.close()
