import os
import sqlite3
import pandas as pd

# Try to import psycopg2 for PostgreSQL connectivity
try:
    import psycopg2
    HAS_POSTGRES = True
except ImportError:
    HAS_POSTGRES = False

def get_connection():
    # PostgreSQL Configuration check from Environment Variables
    pg_host = os.getenv("PGHOST")
    pg_port = os.getenv("PGPORT", "5432")
    pg_user = os.getenv("PGUSER")
    pg_password = os.getenv("PGPASSWORD")
    pg_database = os.getenv("PGDATABASE")

    if HAS_POSTGRES and pg_host and pg_user and pg_password and pg_database:
        try:
            conn = psycopg2.connect(
                host=pg_host,
                port=pg_port,
                user=pg_user,
                password=pg_password,
                database=pg_database,
                connect_timeout=3
            )
            return conn, "PostgreSQL"
        except Exception as e:
            # Fallback on failure
            pass

    # Default Fallback to SQLite
    sqlite_path = r"c:\Users\darwi\Downloads\sql_adv\quick_commerce.db"
    if os.path.exists(sqlite_path):
        conn = sqlite3.connect(sqlite_path)
        return conn, "SQLite (Local Cache)"
    else:
        # Fallback to an in-memory SQLite DB
        conn = sqlite3.connect(":memory:")
        return conn, "SQLite (In-Memory Mock)"

def run_query_df(query):
    conn, db_type = get_connection()
    try:
        df = pd.read_sql_query(query, conn)
        return df, db_type
    finally:
        conn.close()
