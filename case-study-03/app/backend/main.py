from contextlib import asynccontextmanager
from typing import Optional
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from database import get_connection, init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(title="Innovatech HR API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Schemas ────────────────────────────────────────────────────────────────

class EmployeeCreate(BaseModel):
    name: str
    email: EmailStr
    department: str
    role: str
    status: str = "active"


class EmployeeUpdate(BaseModel):
    name: Optional[str] = None
    department: Optional[str] = None
    role: Optional[str] = None
    status: Optional[str] = None


# ─── Routes ─────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/api/employees")
def list_employees():
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM employees ORDER BY id")
            return cur.fetchall()
    finally:
        conn.close()


@app.get("/api/employees/{employee_id}")
def get_employee(employee_id: int):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM employees WHERE id = %s", (employee_id,))
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Employee not found")
            return row
    finally:
        conn.close()


@app.post("/api/employees", status_code=201)
def create_employee(payload: EmployeeCreate):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO employees (name, email, department, role, status)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING *
                """,
                (payload.name, payload.email, payload.department, payload.role, payload.status),
            )
            row = cur.fetchone()
        conn.commit()
        return row
    except Exception as e:
        conn.rollback()
        if "unique" in str(e).lower():
            raise HTTPException(status_code=409, detail="Email already exists")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()


@app.put("/api/employees/{employee_id}")
def update_employee(employee_id: int, payload: EmployeeUpdate):
    fields = {k: v for k, v in payload.model_dump().items() if v is not None}
    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update")

    set_clause = ", ".join(f"{k} = %s" for k in fields)
    values = list(fields.values()) + [employee_id]

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"UPDATE employees SET {set_clause} WHERE id = %s RETURNING *",
                values,
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Employee not found")
        conn.commit()
        return row
    finally:
        conn.close()


@app.delete("/api/employees/{employee_id}", status_code=204)
def deactivate_employee(employee_id: int):
    """Soft delete — marks the employee inactive rather than removing the record."""
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE employees SET status = 'inactive' WHERE id = %s RETURNING id",
                (employee_id,),
            )
            if not cur.fetchone():
                raise HTTPException(status_code=404, detail="Employee not found")
        conn.commit()
    finally:
        conn.close()
