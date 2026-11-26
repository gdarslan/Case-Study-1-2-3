"""
Employee Offboarding Automation — REQ-NCA-P3-01
Removes the employee from all IAM Identity Center groups, deletes their
SSO user, and marks them as inactive in the database.

Usage:
    python offboarding.py --email "jane.doe@example.com"
"""

import argparse
import os
import sys
import boto3
import psycopg2
from dotenv import load_dotenv

load_dotenv()

# ─── Config ─────────────────────────────────────────────────────────────────

IDENTITY_STORE_ID = os.environ["IDENTITY_STORE_ID"]
AWS_REGION        = os.environ.get("AWS_REGION", "eu-central-1")

DB_HOST = os.environ["DB_HOST"]
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASS = os.environ["DB_PASS"]

# ─── AWS client ─────────────────────────────────────────────────────────────

identity_store = boto3.client("identitystore", region_name=AWS_REGION)


def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT,
        dbname=DB_NAME, user=DB_USER, password=DB_PASS
    )


def find_sso_user(email: str) -> dict | None:
    """Look up a user by email in IAM Identity Center."""
    response = identity_store.list_users(
        IdentityStoreId=IDENTITY_STORE_ID,
        Filters=[{"AttributePath": "UserName", "AttributeValue": email}]
    )
    users = response.get("Users", [])
    return users[0] if users else None


def remove_from_all_groups(user_id: str):
    """Remove the user from every group they belong to."""
    response = identity_store.list_group_memberships_for_member(
        IdentityStoreId=IDENTITY_STORE_ID,
        MemberId={"UserId": user_id}
    )
    memberships = response.get("GroupMemberships", [])

    if not memberships:
        print("  [i] User has no group memberships to remove")
        return

    for membership in memberships:
        identity_store.delete_group_membership(
            IdentityStoreId=IDENTITY_STORE_ID,
            MembershipId=membership["MembershipId"]
        )
        print(f"  [-] Removed from group: {membership['GroupId']}")


def delete_sso_user(user_id: str):
    identity_store.delete_user(
        IdentityStoreId=IDENTITY_STORE_ID,
        UserId=user_id
    )
    print(f"  [-] Deleted SSO user: {user_id}")


def deactivate_in_database(email: str):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE employees SET status = 'inactive', sso_user_id = NULL WHERE email = %s RETURNING id",
                (email,)
            )
            row = cur.fetchone()
            if row:
                print(f"  [-] Database record marked inactive (id={row[0]})")
            else:
                print(f"  [!] No database record found for {email}")
        conn.commit()
    finally:
        conn.close()


def offboard(email: str):
    print(f"\nOffboarding: {email}\n")

    user = find_sso_user(email)
    if not user:
        print(f"[!] No SSO user found for {email}")
        print("    Proceeding to deactivate database record only.")
        deactivate_in_database(email)
        return

    user_id = user["UserId"]
    print(f"  [i] Found SSO user: {user.get('DisplayName', email)} ({user_id})")

    remove_from_all_groups(user_id)
    delete_sso_user(user_id)
    deactivate_in_database(email)

    print(f"\n[✓] Offboarding complete for {email}")
    print("    SSO access revoked, database record deactivated.")


# ─── CLI ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Offboard an Innovatech employee")
    parser.add_argument("--email", required=True, help="Employee work email address")
    args = parser.parse_args()

    offboard(args.email)
