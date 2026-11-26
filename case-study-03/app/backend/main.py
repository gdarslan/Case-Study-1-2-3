from contextlib import asynccontextmanager
from typing import Optional, Literal
import os
import logging
from fastapi import FastAPI, HTTPException, Depends, Header
from pydantic import BaseModel, EmailStr, Field
from database import get_connection, init_db
from auth import authenticate

log = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(title="Innovatech HR API", version="1.0.0", lifespan=lifespan)

def require_user(authorization: str | None = Header(default=None)) -> str:
    role = authenticate(authorization, os.getenv("HR_ADMIN_TOKEN", ""), os.getenv("HR_VIEWER_TOKEN", ""))
    if role is None:
        raise HTTPException(status_code=401, detail="Authentication required",
                            headers={"WWW-Authenticate": "Bearer"})
    return role


def require_admin(role: str = Depends(require_user)) -> str:
    if role != "admin":
        raise HTTPException(status_code=403, detail="Administrator access required")
    return role


# ─── Schemas ────────────────────────────────────────────────────────────────

class EmployeeCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    email: EmailStr = Field(max_length=150)
    department: str = Field(min_length=1, max_length=100)
    role: Literal["developer", "admin", "hr", "readonly"]
    status: Literal["active", "inactive", "pending"] = "active"


class EmployeeUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=100)
    department: Optional[str] = Field(default=None, min_length=1, max_length=100)
    role: Optional[Literal["developer", "admin", "hr", "readonly"]] = None
    status: Optional[Literal["active", "inactive", "pending"]] = None


# ─── Routes ─────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/api/session")
def session(role: str = Depends(require_user)):
    return {"role": role}


@app.get("/api/employees", dependencies=[Depends(require_user)])
def list_employees():
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM employees ORDER BY id")
            return cur.fetchall()
    finally:
        conn.close()


@app.get("/api/employees/{employee_id}", dependencies=[Depends(require_user)])
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


@app.post("/api/employees", status_code=201, dependencies=[Depends(require_admin)])
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
        log.exception("Employee creation failed")
        raise HTTPException(status_code=500, detail="Unable to create employee")
    finally:
        conn.close()


@app.put("/api/employees/{employee_id}", dependencies=[Depends(require_admin)])
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


@app.delete("/api/employees/{employee_id}", status_code=204, dependencies=[Depends(require_admin)])
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
