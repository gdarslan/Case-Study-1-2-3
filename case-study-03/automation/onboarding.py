"""
Employee Onboarding Automation — REQ-NCA-P3-01
Creates the employee in AWS IAM Identity Center, assigns them to the
correct group based on their role, and records them in the database.

Usage:
    python onboarding.py \
        --name "Jane Doe" \
        --email "jane.doe@example.com" \
        --department "Engineering" \
        --role developer

Roles: admin | developer | hr | readonly
"""

import argparse
import os
import sys
import boto3
import psycopg2
from dotenv import load_dotenv

load_dotenv()

# ─── Config ─────────────────────────────────────────────────────────────────

IDENTITY_STORE_ID = os.environ["IDENTITY_STORE_ID"]   # e.g. d-xxxxxxxxxx
SSO_INSTANCE_ARN  = os.environ["SSO_INSTANCE_ARN"]    # arn:aws:sso:::instance/...

DB_HOST = os.environ["DB_HOST"]
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASS = os.environ["DB_PASS"]

AWS_REGION = os.environ.get("AWS_REGION", "eu-central-1")

# Map role → IAM Identity Center group name
ROLE_GROUP_MAP = {
    "admin":     "innovatech-admins",
    "developer": "innovatech-developers",
    "hr":        "innovatech-hr",
    "readonly":  "innovatech-readonly",
}

# ─── AWS clients ────────────────────────────────────────────────────────────

identity_store = boto3.client("identitystore", region_name=AWS_REGION)
sso_admin      = boto3.client("sso-admin",     region_name=AWS_REGION)


def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT,
        dbname=DB_NAME, user=DB_USER, password=DB_PASS
    )


def get_or_create_group(group_name: str) -> str:
    """Return existing group ID or create the group and return its new ID."""
    response = identity_store.list_groups(
        IdentityStoreId=IDENTITY_STORE_ID,
        Filters=[{"AttributePath": "DisplayName", "AttributeValue": group_name}]
    )
    if response["Groups"]:
        return response["Groups"][0]["GroupId"]

    created = identity_store.create_group(
        IdentityStoreId=IDENTITY_STORE_ID,
        DisplayName=group_name,
        Description=f"Innovatech {group_name} group"
    )
    print(f"  [+] Created group: {group_name}")
    return created["GroupId"]


def create_sso_user(name: str, email: str) -> str:
    """Create a user in IAM Identity Center and return the UserId."""
    first, *rest = name.split()
    last = " ".join(rest) if rest else ""

    response = identity_store.create_user(
        IdentityStoreId=IDENTITY_STORE_ID,
        UserName=email,
        Name={"GivenName": first, "FamilyName": last},
        DisplayName=name,
        Emails=[{"Value": email, "Type": "work", "Primary": True}]
    )
    user_id = response["UserId"]
    print(f"  [+] Created SSO user: {email} ({user_id})")
    return user_id


def assign_user_to_group(user_id: str, group_id: str, group_name: str):
    identity_store.create_group_membership(
        IdentityStoreId=IDENTITY_STORE_ID,
        GroupId=group_id,
        MemberId={"UserId": user_id}
    )
    print(f"  [+] Assigned user to group: {group_name}")


def record_in_database(name: str, email: str, department: str, role: str, sso_user_id: str):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO employees (name, email, department, role, status, sso_user_id)
                VALUES (%s, %s, %s, %s, 'active', %s)
                ON CONFLICT (email) DO UPDATE
                    SET status      = 'active',
                        sso_user_id = EXCLUDED.sso_user_id,
                        department  = EXCLUDED.department,
                        role        = EXCLUDED.role
                RETURNING id
                """,
                (name, email, department, role, sso_user_id)
            )
            employee_id = cur.fetchone()[0]
        conn.commit()
        print(f"  [+] Database record created/updated (id={employee_id})")
    finally:
        conn.close()


def onboard(name: str, email: str, department: str, role: str):
    if role not in ROLE_GROUP_MAP:
        print(f"[!] Unknown role '{role}'. Valid roles: {list(ROLE_GROUP_MAP)}")
        sys.exit(1)

    print(f"\nOnboarding: {name} <{email}>")
    print(f"  Department : {department}")
    print(f"  Role       : {role}")
    print()

    group_name = ROLE_GROUP_MAP[role]
    group_id   = get_or_create_group(group_name)
    user_id    = create_sso_user(name, email)

    assign_user_to_group(user_id, group_id, group_name)
    record_in_database(name, email, department, role, user_id)

    print(f"\n[✓] Onboarding complete for {name}")
    print(f"    SSO User ID : {user_id}")
    print(f"    Group       : {group_name}")


# ─── CLI ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Onboard a new Innovatech employee")
    parser.add_argument("--name",       required=True, help="Full name")
    parser.add_argument("--email",      required=True, help="Work email address")
    parser.add_argument("--department", required=True, help="Department (e.g. Engineering)")
    parser.add_argument("--role",       required=True,
                        choices=list(ROLE_GROUP_MAP), help="Access role")
    args = parser.parse_args()

    onboard(args.name, args.email, args.department, args.role)
