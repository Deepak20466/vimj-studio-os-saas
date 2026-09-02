"""Create the first admin user. Run once after migrations: python scripts/seed_admin.py"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import SessionLocal
from app.models.user import User, UserRole
from app.security import hash_password


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--email", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--phone", default=None)
    args = parser.parse_args()

    db = SessionLocal()
    try:
        if db.query(User).filter(User.email == args.email).first():
            print(f"User {args.email} already exists.")
            return
        admin = User(
            email=args.email,
            password_hash=hash_password(args.password),
            name=args.name,
            phone=args.phone,
            role=UserRole.ADMIN,
        )
        db.add(admin)
        db.commit()
        print(f"Admin user created: {args.email}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
